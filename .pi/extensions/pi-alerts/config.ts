import { CONFIG_DIR_NAME, getAgentDir } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import { existsSync, readFileSync, statSync } from "node:fs";

export type AlertType = "complete" | "error" | "permission" | "question";

type EventConfig = { notification: boolean; sound: boolean; bell: boolean; soundName: string };

export type AlertsConfig = {
	enabled: boolean;
	focus: { suppressWhenFocused: boolean; failOpen: boolean };
	events: Record<AlertType, EventConfig>;
	notification: { clickToFocus: boolean; timeoutSeconds: number };
	questionTools: string[];
	debug: boolean;
};

const DEFAULT_CONFIG: AlertsConfig = {
	enabled: false,
	focus: { suppressWhenFocused: true, failOpen: true },
	events: {
		complete: { notification: true, sound: true, bell: false, soundName: "Glass" },
		error: { notification: true, sound: true, bell: false, soundName: "Basso" },
		permission: { notification: true, sound: true, bell: false, soundName: "Sosumi" },
		question: { notification: true, sound: true, bell: false, soundName: "Pop" },
	},
	notification: { clickToFocus: true, timeoutSeconds: 0 },
	questionTools: ["question", "ask_user_question", "questionnaire"],
	debug: false,
};

type CachedFile = { stamp: number; value: Record<string, unknown> };
const cache = new Map<string, CachedFile>();

function record(value: unknown): Record<string, unknown> {
	return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function readFile(path: string): Record<string, unknown> {
	try {
		if (!existsSync(path)) return {};
		const stamp = statSync(path).mtimeMs;
		const previous = cache.get(path);
		if (previous?.stamp === stamp) return previous.value;
		const value = record(JSON.parse(readFileSync(path, "utf8")));
		cache.set(path, { stamp, value });
		return value;
	} catch {
		return {};
	}
}

function merge(base: AlertsConfig, ...sources: Record<string, unknown>[]): AlertsConfig {
	const result: AlertsConfig = structuredClone(base);
	for (const source of sources) {
		if (typeof source.enabled === "boolean") result.enabled = source.enabled;
		const focus = record(source.focus);
		if (typeof focus.suppressWhenFocused === "boolean") result.focus.suppressWhenFocused = focus.suppressWhenFocused;
		if (typeof focus.failOpen === "boolean") result.focus.failOpen = focus.failOpen;
		const notification = record(source.notification);
		if (typeof notification.clickToFocus === "boolean") result.notification.clickToFocus = notification.clickToFocus;
		if (typeof notification.timeoutSeconds === "number" && Number.isFinite(notification.timeoutSeconds)) {
			result.notification.timeoutSeconds = Math.max(0, Math.min(60, Math.round(notification.timeoutSeconds)));
		}
		if (Array.isArray(source.questionTools)) {
			result.questionTools = source.questionTools.filter((value): value is string => typeof value === "string");
		}
		if (typeof source.debug === "boolean") result.debug = source.debug;
		const events = record(source.events);
		for (const type of Object.keys(result.events) as AlertType[]) {
			const event = record(events[type]);
			for (const channel of ["notification", "sound", "bell"] as const) {
				if (typeof event[channel] === "boolean") result.events[type][channel] = event[channel];
			}
			if (typeof event.soundName === "string" && event.soundName.trim()) result.events[type].soundName = event.soundName.trim();
		}
	}
	return result;
}

export function globalConfigPath(): string {
	return join(getAgentDir(), "pi-alerts.json");
}

export function projectConfigPath(cwd: string): string {
	return join(cwd, CONFIG_DIR_NAME, "pi-alerts.json");
}

export function loadConfig(cwd: string, trusted: boolean): AlertsConfig {
	const global = readFile(globalConfigPath());
	const project = trusted ? readFile(projectConfigPath(cwd)) : {};
	return merge(DEFAULT_CONFIG, global, project);
}
