import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { basename } from "node:path";
import { execFileSync, spawn, spawnSync } from "node:child_process";
import { readlinkSync, writeFileSync } from "node:fs";
import { loadConfig, type AlertType, type AlertsConfig } from "./config.ts";

const PERMISSION_CHANNEL = "pi-permission-system:permission-request";
const QUESTION_TOOLS = new Set(["question", "ask_user_question", "questionnaire"]);

const MAC_APPS: Record<string, { name: string; bundle: string }> = {
	ghostty: { name: "Ghostty", bundle: "com.mitchellh.ghostty" },
	"iterm.app": { name: "iTerm2", bundle: "com.googlecode.iterm2" },
	apple_terminal: { name: "Terminal", bundle: "com.apple.Terminal" },
	terminal: { name: "Terminal", bundle: "com.apple.Terminal" },
	wezterm: { name: "WezTerm", bundle: "com.github.wez.wezterm" },
	"wezterm-gui": { name: "WezTerm", bundle: "com.github.wez.wezterm" },
	kitty: { name: "kitty", bundle: "net.kovidgoyal.kitty" },
	vscode: { name: "Visual Studio Code", bundle: "com.microsoft.VSCode" },
	cursor: { name: "Cursor", bundle: "com.todesktop.230313mzl4w4u92" },
	zed: { name: "Zed", bundle: "dev.zed.Zed" },
};

const MAC_FALLBACK_APPS = new Set([
	"ghostty", "iterm2", "iterm.app", "terminal", "apple_terminal", "wezterm", "wezterm-gui",
	"kitty", "visual studio code", "code", "cursor", "zed", "alacritty", "warp", "rio",
]);

const LINUX_APPS = new Set([
	"ghostty", "konsole", "gnome-terminal", "gnome-terminal-server", "xterm", "alacritty",
	"kitty", "wezterm", "wezterm-gui", "tilix", "terminator", "foot", "footclient", "code",
	"code-oss", "cursor", "zed", "rio", "xfce4-terminal", "mate-terminal", "kgx",
]);

const WINDOWS_APPS = new Set([
	"windowsterminal", "openconsole", "conhost", "powershell", "pwsh", "cmd", "wt",
	"wezterm", "wezterm-gui", "alacritty", "kitty", "tabby", "warp", "rio", "code", "cursor",
]);

type FocusInfo = { focused: boolean; reliable: boolean; app?: string; bundle?: string };

type PermissionEvent = { state?: string };

function normalize(value: string): string {
	return value.toLowerCase().replace(/\.app$/, "").replace(/\.exe$/, "").trim();
}

function commandExists(command: string): boolean {
	try {
		if (process.platform === "win32") {
			const result = spawnSync("where.exe", [command], { stdio: "ignore", timeout: 500 });
			return result.status === 0;
		}
		const result = spawnSync("sh", ["-lc", `command -v ${JSON.stringify(command)}`], {
			stdio: ["ignore", "pipe", "ignore"], encoding: "utf8", timeout: 500,
		});
		return result.status === 0 && Boolean(result.stdout.trim());
	} catch {
		return false;
	}
}

function run(command: string, args: string[], timeout = 1000): string | null {
	try {
		return execFileSync(command, args, {
			encoding: "utf8", timeout, stdio: ["ignore", "pipe", "ignore"],
		}).trim() || null;
	} catch {
		return null;
	}
}

function expectedMacApps(): Set<string> {
	const term = normalize(process.env.TERM_PROGRAM ?? "");
	if (process.env.TMUX && (!term || term === "tmux" || term === "screen")) return MAC_FALLBACK_APPS;
	if (term === "iterm" || term === "iterm2") return new Set(["iterm2", "iterm.app"]);
	if (term === "apple_terminal") return new Set(["terminal", "apple_terminal"]);
	if (term === "vscode") return new Set(["visual studio code", "code"]);
	if (term) return new Set([term]);
	return MAC_FALLBACK_APPS;
}

function macFrontmostApp(): string | null {
	const front = run("lsappinfo", ["front"]);
	if (front) {
		const info = run("lsappinfo", ["info", "-only", "name", front]);
		const match = info?.match(/name\s*=\s*"([^"]+)"/i);
		if (match?.[1]) return match[1];
	}
	return run("osascript", ["-e", "tell application \"System Events\" to return name of first application process whose frontmost is true"]);
}

function linuxFrontmostApp(): string | null {
	const x11 = run("xdotool", ["getactivewindow", "getwindowclassname"]);
	if (x11) return x11;
	const hypr = run("hyprctl", ["activewindow", "-j"]);
	if (hypr) {
		try { return (JSON.parse(hypr).class ?? JSON.parse(hypr).initialClass) as string | null; } catch { /* fallback */ }
	}
	const niri = run("niri", ["msg", "--json", "focused-window"]);
	if (niri) {
		try { return (JSON.parse(niri).app_id ?? JSON.parse(niri).appId) as string | null; } catch { /* fallback */ }
	}
	const sway = run("swaymsg", ["-t", "get_tree"]);
	if (sway) {
		try {
			const find = (node: any): string | null => {
				if (node.focused) return node.app_id ?? node.window_properties?.class ?? null;
				for (const child of [...(node.nodes ?? []), ...(node.floating_nodes ?? [])]) {
					const result = find(child); if (result) return result;
				}
				return null;
			};
			return find(JSON.parse(sway));
		} catch { /* fallback */ }
	}
	return run("kdotool", ["getactivewindow", "getwindowclassname"]);
}

function windowsFrontmostApp(): string | null {
	const script = `
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PiAlertsFocus {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int processId);
}
"@
$pid = 0
$window = [PiAlertsFocus]::GetForegroundWindow()
if ($window -ne [IntPtr]::Zero) {
  [PiAlertsFocus]::GetWindowThreadProcessId($window, [ref]$pid) | Out-Null
  if ($pid -gt 0) { (Get-Process -Id $pid -ErrorAction SilentlyContinue).ProcessName }
}`;
	return run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], 3000)
		?? run("pwsh", ["-NoProfile", "-NonInteractive", "-Command", script], 3000);
}

function detectFocus(): FocusInfo {
	if (process.platform === "darwin") {
		const app = macFrontmostApp();
		if (!app) return { focused: false, reliable: false };
		const normalized = normalize(app);
		const focused = expectedMacApps().has(normalized);
		const metadata = Object.values(MAC_APPS).find((item) => normalize(item.name) === normalized);
		return { focused, reliable: true, app, bundle: metadata?.bundle };
	}
	if (process.platform === "linux") {
		const app = linuxFrontmostApp();
		if (!app) return { focused: false, reliable: false };
		const normalized = normalize(app);
		return { focused: [...LINUX_APPS].some((candidate) => normalized.includes(candidate)), reliable: true, app };
	}
	if (process.platform === "win32") {
		const app = windowsFrontmostApp();
		if (!app) return { focused: false, reliable: false };
		const normalized = normalize(app);
		return { focused: [...WINDOWS_APPS].some((candidate) => normalized.includes(candidate)), reliable: true, app };
	}
	return { focused: false, reliable: false };
}

function currentMacApp(): { bundle?: string } {
	const term = normalize(process.env.TERM_PROGRAM ?? "");
	if (term === "iterm" || term === "iterm2") return MAC_APPS["iterm.app"];
	if (term === "apple_terminal") return MAC_APPS.apple_terminal;
	if (term === "vscode") return MAC_APPS.vscode;
	return MAC_APPS[term] ?? {};
}

function escapeAppleScript(value: string): string {
	return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\r?\n/g, " ");
}

function escapeXml(value: string): string {
	return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}

function spawnCommand(command: string, args: string[]): boolean {
	try {
		const child = spawn(command, args, { stdio: "ignore", detached: true });
		child.unref();
		return true;
	} catch {
		return false;
	}
}

function sendMac(title: string, subtitle: string, body: string, group: string, sound: boolean, soundName: string, clickToFocus: boolean, timeoutSeconds: number): boolean {
	const app = currentMacApp();
	if (commandExists("alerter")) {
		const args = ["--title", title, "--subtitle", subtitle, "--message", body, "--group", group, "--timeout", String(timeoutSeconds)];
		if (clickToFocus && app.bundle) args.push("--sender", app.bundle);
		if (sound) args.push("--sound", soundName);
		return spawnCommand("alerter", args);
	}
	if (commandExists("terminal-notifier")) {
		const args = ["-title", title, "-subtitle", subtitle, "-message", body, "-group", group];
		if (clickToFocus && app.bundle) args.push("-activate", app.bundle);
		if (sound) args.push("-sound", soundName);
		return spawnCommand("terminal-notifier", args);
	}
	const soundClause = sound ? ` sound name "${escapeAppleScript(soundName)}"` : "";
	const script = `display notification \"${escapeAppleScript(body)}\" with title \"${escapeAppleScript(title)}\" subtitle \"${escapeAppleScript(subtitle)}\"${soundClause}`;
	return spawnCommand("osascript", ["-e", script]);
}

function sendLinux(title: string, subtitle: string, body: string, group: string, type: AlertType): boolean {
	if (!commandExists("notify-send")) return false;
	const urgency = type === "error" || type === "permission" ? "critical" : "normal";
	return spawnCommand("notify-send", ["--app-name=Pi", `--urgency=${urgency}`, `--hint=string:x-canonical-private-synchronous:${group}`, `${title} — ${subtitle}`, body]);
}

function sendWindows(title: string, subtitle: string, body: string, sound: boolean): boolean {
	const powershell = commandExists("powershell.exe") ? "powershell.exe" : commandExists("pwsh") ? "pwsh" : null;
	if (!powershell) return false;
	const audio = sound ? "<audio src=\"ms-winsoundevent:Notification.Default\"/>" : "";
	const xml = `<toast><visual><binding template="ToastGeneric"><text>${escapeXml(title)}</text><text>${escapeXml(`${subtitle}: ${body}`)}</text></binding></visual>${audio}</toast>`;
	const encoded = Buffer.from(`
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml('${xml.replace(/'/g, "''")}')
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Pi').Show($toast)
`, "utf16le").toString("base64");
	return spawnCommand(powershell, ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded]);
}

function sendBell(): void {
	try {
		const tty = [0, 1, 2].map((fd) => `/dev/fd/${fd}`).find((path) => {
			try { return readlinkSync(path).startsWith("/dev/tty"); } catch { return false; }
		});
		if (tty) writeFileSync(tty, "\x07");
		else if (process.stdout.isTTY) process.stdout.write("\x07");
	} catch { /* best effort */ }
}

function sendPlatformAlert(title: string, subtitle: string, body: string, group: string, type: AlertType, sound: boolean, soundName: string, clickToFocus: boolean, timeoutSeconds: number): boolean {
	if (process.platform === "darwin") return sendMac(title, subtitle, body, group, sound, soundName, clickToFocus, timeoutSeconds);
	if (process.platform === "linux") return sendLinux(title, subtitle, body, group, type);
	if (process.platform === "win32") return sendWindows(title, subtitle, body, sound);
	return false;
}

function eventCopy(type: AlertType): { emoji: string; label: string; body: string } {
	switch (type) {
		case "complete": return { emoji: "✅", label: "Complete", body: "Agent finished" };
		case "error": return { emoji: "❌", label: "Error", body: "Pi encountered an error" };
		case "permission": return { emoji: "⚠️", label: "Permission required", body: "Pi is waiting for approval" };
		case "question": return { emoji: "❓", label: "Input needed", body: "Pi is waiting for your answer" };
	}
}

function sessionGroup(ctx: ExtensionContext, type: AlertType): string {
	let session = "session";
	try { session = ctx.sessionManager.getSessionId(); } catch { /* fallback */ }
	return `pi-${session}-${type === "complete" ? "routine" : type}`.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function isAgentError(event: unknown): boolean {
	const record = event as { messages?: unknown[] } | undefined;
	if (!Array.isArray(record?.messages)) return false;
	return record.messages.some((message) => {
		const item = message as { role?: string; stopReason?: string; errorMessage?: string };
		return item.role === "assistant" && (item.stopReason === "error" || Boolean(item.errorMessage));
	});
}

function shouldRunInMode(ctx: ExtensionContext): boolean {
	return ctx.mode !== "print" && ctx.mode !== "json";
}

type TabTitleState = "idle" | "working" | AlertType;

function updateTabTitle(
	ctx: ExtensionContext,
	state: TabTitleState,
	sessionName: string | undefined,
	config: AlertsConfig,
): void {
	if (!shouldRunInMode(ctx) || !ctx.hasUI || !config.enabled || !config.tabTitle.enabled) return;

	const icon = state === "idle" ? "•" : state === "working" ? "⏳" : eventCopy(state).emoji;
	const session = sessionName ? ` · ${sessionName}` : "";
	ctx.ui.setTitle(`${icon} Pi · ${basename(ctx.cwd)}${session}`);
}

export default function piAlerts(pi: ExtensionAPI): void {
	let activeContext: ExtensionContext | undefined;
	let terminalError = false;
	let permissionTimer: ReturnType<typeof setTimeout> | undefined;
	let permissionContext: ExtensionContext | undefined;

	const emit = (type: AlertType, ctx: ExtensionContext, force = false): void => {
		if (!shouldRunInMode(ctx)) return;
		const config = loadConfig(ctx.cwd, ctx.isProjectTrusted());
		if (!force && !config.enabled) return;
		updateTabTitle(ctx, type, pi.getSessionName(), config);
		if (!force && !config.events[type].notification && !config.events[type].sound && !config.events[type].bell) return;
		const copy = eventCopy(type);
		const title = `${copy.emoji} Pi · ${basename(ctx.cwd)}${pi.getSessionName() ? ` · ${pi.getSessionName()}` : ""}`;
		const eventConfig = config.events[type];
		const focused = detectFocus();
		if (!force && config.focus.suppressWhenFocused && (focused.focused || (!focused.reliable && !config.focus.failOpen))) return;
		const group = sessionGroup(ctx, type);
		const sent = eventConfig.notification && sendPlatformAlert(
			title,
			copy.label,
			copy.body,
			group,
			type,
			eventConfig.sound,
			eventConfig.soundName,
			config.notification.clickToFocus,
			config.notification.timeoutSeconds,
		);
		if (eventConfig.bell && !sent) sendBell();
	};

	pi.registerCommand("pi-alerts", {
		description: "Test or inspect Pi alerts",
		handler: async (args, ctx) => {
			const [command, requestedType] = args.trim().split(/\s+/);
			if (command === "status") {
				const config = loadConfig(ctx.cwd, ctx.isProjectTrusted());
				const focus = detectFocus();
				const app = focus.app ?? "unknown";
				const backend = process.platform === "darwin"
					? commandExists("alerter") ? "alerter" : commandExists("terminal-notifier") ? "terminal-notifier" : "osascript"
					: process.platform === "linux" ? commandExists("notify-send") ? "notify-send" : "none"
					: process.platform === "win32" ? "PowerShell toast" : "none";
				ctx.ui.notify(`Enabled: ${config.enabled}\nFocused: ${focus.focused ? "yes" : "no"} (${app})\nBackend: ${backend}`, "info");
				return;
			}
			const type = (requestedType ?? "complete") as AlertType;
			if (!["complete", "error", "permission", "question"].includes(type)) {
				ctx.ui.notify("Usage: /pi-alerts [status|test [complete|error|permission|question]]", "warning");
				return;
			}
			emit(type, ctx, true);
			ctx.ui.notify(`Sent ${type} alert test.`, "info");
		},
	});

	pi.on("session_start", (_event, ctx) => {
		activeContext = ctx;
		terminalError = false;
		updateTabTitle(ctx, "idle", pi.getSessionName(), loadConfig(ctx.cwd, ctx.isProjectTrusted()));
	});
	pi.on("session_shutdown", () => {
		activeContext = undefined;
		if (permissionTimer) clearTimeout(permissionTimer);
	});
	pi.on("agent_start", (_event, ctx) => {
		terminalError = false;
		updateTabTitle(ctx, "working", pi.getSessionName(), loadConfig(ctx.cwd, ctx.isProjectTrusted()));
	});
	pi.on("agent_end", (event) => { if (isAgentError(event)) terminalError = true; });
	pi.on("agent_settled", (_event, ctx) => {
		emit(terminalError ? "error" : "complete", ctx);
		terminalError = false;
	});
	pi.on("tool_execution_start", (event, ctx) => {
		const config = loadConfig(ctx.cwd, ctx.isProjectTrusted());
		if (QUESTION_TOOLS.has(event.toolName.toLowerCase()) || config.questionTools.includes(event.toolName)) emit("question", ctx);
	});
	pi.events.on(PERMISSION_CHANNEL, (payload) => {
		const permission = payload as PermissionEvent | undefined;
		if (permission?.state !== "waiting" || !activeContext) return;
		permissionContext = activeContext;
		if (permissionTimer) clearTimeout(permissionTimer);
		permissionTimer = setTimeout(() => {
			const ctx = permissionContext;
			permissionContext = undefined;
			permissionTimer = undefined;
			if (ctx) emit("permission", ctx);
		}, 250);
	});
}
