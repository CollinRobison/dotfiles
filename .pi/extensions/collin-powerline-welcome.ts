import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, relative } from "node:path";
import { VERSION, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { type Component, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const ALPHA_ART = [
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠟⠛⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠁⠀⠘⣿⣿⠟⠋⠉⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠟⠋⠉⠀⠀⠀⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠁⠹⣿⡿⠀⠀⠀⠀⠉⠀⠀⠀⠀⠀⠀⠻⠿⠟⠛⠛⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⠀⠀⠈⠉⠉⠛⠛⠛⠛⠿⠿⠿⠿⠿⠏⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⠆⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠛⠛⠋⠉⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⢹⣿⣿⣿⣶⣦⣄⡀⠀⠀⠀⠀⠀⠀⠠⠾⣿⠀⢿⠿⠛⠁⠀⠀⠀⢠⠀⠀⠀⠀⠀⠀⠀⠒⠛⢋⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠙⠿⣿⣿⡇⢸⠿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣴⣿⠀⠀⠀⠀⠀⠀⠀⠀⠠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⠷⠆⠀⠀⠀⠀⠀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⣴⡆⢸⣿⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⡦⠀⠀⠀⠀⠀⠀⢻⣦⣄⠀⣀⣀⣀⡀⢀⣤⣤⣤⣶⣶⣾⡇⠀⣿⣿⣿⣿⡇⢸⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢻⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠈⢿⣿⠀⣿⣿⣿⡇⢸⣿⣿⣿⣿⣿⣿⡇⠀⣿⣿⣿⣿⡇⢸⠟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⠀⣿⣿⣿⡇⢸⣿⣿⣿⣿⣿⣿⡇⠀⣿⣿⣿⣿⠇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠿⠇⢸⣿⣿⣿⣿⣿⣿⡇⠀⠿⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣿⣿",
  "⣿⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠉⠉⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿",
  "⣿⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣶⣤⡀⠀⢀⠀⠀⠀⣿⣿⣿",
  "⣿⣿⣿⡇⠀⠀⠀⠀⠀⣴⣿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣿⣿⣿⣄⣾⣆⣾⣤⣿⣿⣿",
  "⣿⣿⣿⣧⣶⡀⣸⣦⣸⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⣀⡀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠄⠀⠀⠀⠀⠀⠀⠀⣠⣶⣿⣿⣿⣿⣷⣄⠀⠀⠀⣠⣴⣿⣿⣿⣿⣿⣄⠀⠀⠀⠀⠀⠀⠀⠀⠸⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⣄⣀⣀⣀⣀⣤⣤⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣶⣦⣤⣤⣤⣤⣤⣤⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿",
  "⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿"
];

const ASCII_LOGO = [
  "  ######  ",
  " ##    ## ",
  " ##    ## ",
  "  ######  ",
  " ##       ",
  " ##       ",
];

const PURPLE_VIVID = "#a855f7";
const PURPLE_SOFT = "#b86cf7";

type WelcomeTheme = ExtensionContext["ui"]["theme"];

interface WelcomeData {
  cwd: string;
  branch?: string;
  model: string;
  provider: string;
  thinking: string;
  loaded: {
    extensions: number;
    skills: number;
    themes: number;
    prompts: number;
  };
  recentSessions: string[];
}

function gitBranch(cwd: string): string | undefined {
  try {
    const branch = execFileSync("git", ["-C", cwd, "branch", "--show-current"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return branch || undefined;
  } catch {
    return undefined;
  }
}

function shortCwd(cwd: string): string {
  const home = homedir();
  if (cwd === home) return "~";
  if (cwd.startsWith(`${home}/`)) return `~/${relative(home, cwd)}`;
  return cwd;
}

function countFiles(paths: string[], extensions: string[]): number {
  const seen = new Set<string>();
  for (const directory of paths) {
    if (!existsSync(directory)) continue;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.isFile() && extensions.some((extension) => entry.name.endsWith(extension))) {
        seen.add(join(directory, entry.name));
      }
    }
  }
  return seen.size;
}

function countSkillDirectories(paths: string[]): number {
  const seen = new Set<string>();
  for (const directory of paths) {
    if (!existsSync(directory)) continue;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.isDirectory() && existsSync(join(directory, entry.name, "SKILL.md"))) {
        seen.add(join(directory, entry.name));
      }
    }
  }
  return seen.size;
}

function sessionProjectName(path: string, directory: string): string {
  try {
    const firstLine = readFileSync(path, "utf8").split(/\r?\n/u, 1)[0]?.trim();
    const header = firstLine ? JSON.parse(firstLine) as { cwd?: unknown } : undefined;
    if (typeof header?.cwd === "string" && header.cwd.length > 0) {
      return basename(header.cwd) || header.cwd;
    }
  } catch {
    // Fall back to the encoded session directory below.
  }

  const fallback = basename(directory).replace(/^-+|-+$/gu, "").split("-").filter(Boolean);
  return fallback.at(-1) || basename(directory);
}

function recentSessions(): string[] {
  const root = join(homedir(), ".pi", "agent", "sessions");
  const files: Array<{ name: string; mtime: number }> = [];

  function visit(directory: string, depth: number): void {
    if (!existsSync(directory) || depth > 2) return;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(path, depth + 1);
      } else if (entry.name.endsWith(".jsonl")) {
        try {
          files.push({ name: sessionProjectName(path, directory), mtime: statSync(path).mtimeMs });
        } catch {
          // Ignore sessions that disappear while the dashboard is loading.
        }
      }
    }
  }

  try {
    visit(root, 0);
  } catch {
    return [];
  }

  return [...new Set(files.sort((a, b) => b.mtime - a.mtime).map((file) => file.name))].slice(0, 3);
}

function welcomeEnabled(ctx: ExtensionContext): boolean {
  const projectSettings = join(ctx.cwd, ".pi", "settings.json");
  const globalSettings = join(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent"), "settings.json");

  for (const path of [projectSettings, globalSettings]) {
    try {
      if (!existsSync(path)) continue;
      const settings = JSON.parse(readFileSync(path, "utf8")) as {
        "collin-powerline-welcome"?: { show?: unknown };
      };
      if (settings["collin-powerline-welcome"]?.show !== undefined) {
        return settings["collin-powerline-welcome"].show === true;
      }
    } catch {
      // Ignore malformed or unavailable settings and use the default.
    }
  }

  return true;
}

function getWelcomeData(ctx: ExtensionContext): WelcomeData {
  const model = ctx.model;
  const provider = model?.provider ?? "no provider";
  const projectPi = join(ctx.cwd, ".pi");
  const globalPi = join(homedir(), ".pi", "agent");

  return {
    cwd: shortCwd(ctx.cwd),
    branch: gitBranch(ctx.cwd),
    model: model?.id ?? "no model",
    provider: ctx.modelRegistry.getProviderDisplayName(provider),
    thinking: ctx.thinkingLevel ?? "off",
    loaded: {
      extensions: countFiles([join(projectPi, "extensions"), join(globalPi, "extensions")], [".ts", ".js"]),
      skills: countSkillDirectories([join(projectPi, "skills"), join(globalPi, "skills")]),
      themes: countFiles([join(projectPi, "themes"), join(globalPi, "themes")], [".json"]),
      prompts: countFiles([join(projectPi, "prompts"), join(globalPi, "prompts")], [".md"]),
    },
    recentSessions: recentSessions(),
  };
}

function hexForeground(hex: string, text: string): string {
  return `\x1b[38;2;${parseInt(hex.slice(1, 3), 16)};${parseInt(hex.slice(3, 5), 16)};${parseInt(hex.slice(5, 7), 16)}m${text}\x1b[39m`;
}

function mixHex(start: string, end: string, amount: number): string {
  const channel = (hex: string, offset: number) => parseInt(hex.slice(offset, offset + 2), 16);
  const mix = (offset: number) => Math.round(channel(start, offset) + (channel(end, offset) - channel(start, offset)) * amount);
  return `#${[1, 3, 5].map((offset) => mix(offset).toString(16).padStart(2, "0")).join("")}`;
}

function gradientText(text: string): string {
  const chars = [...text];
  const coloredChars = chars.filter((char) => char !== " ").length;
  let coloredIndex = 0;

  return chars
    .map((char) => {
      if (char === " ") return char;
      const amount = coloredChars <= 1 ? 0 : coloredIndex / (coloredChars - 1);
      coloredIndex++;
      return hexForeground(mixHex(PURPLE_VIVID, PURPLE_SOFT, amount), char);
    })
    .join("");
}

function center(text: string, width: number): string {
  const clipped = visibleWidth(text) > width ? truncateToWidth(text, width, "") : text;
  const padding = Math.max(0, width - visibleWidth(clipped));
  const left = Math.floor(padding / 2);
  return `${" ".repeat(left)}${clipped}${" ".repeat(padding - left)}`;
}

function fit(text: string, width: number): string {
  const clipped = visibleWidth(text) > width ? truncateToWidth(text, width, "…") : text;
  return `${clipped}${" ".repeat(Math.max(0, width - visibleWidth(clipped)))}`;
}

function borderLine(width: number, left: string, right: string): string {
  const innerWidth = Math.max(0, width - 2);
  const content = `${left}${right}`;
  const dashCount = Math.max(0, innerWidth - visibleWidth(content));
  return `${hexForeground(PURPLE_VIVID, "╭")}${hexForeground(PURPLE_VIVID, "─".repeat(Math.floor(dashCount / 2)))}${content}${hexForeground(PURPLE_VIVID, "─".repeat(Math.ceil(dashCount / 2)))}${hexForeground(PURPLE_VIVID, "╮")}`;
}

function bottomBorder(width: number): string {
  const label = " any key to continue ";
  const innerWidth = Math.max(0, width - 2);
  const dashCount = Math.max(0, innerWidth - label.length);
  return `${hexForeground(PURPLE_VIVID, "╰")}${hexForeground(PURPLE_VIVID, "─".repeat(Math.floor(dashCount / 2)))}${hexForeground(PURPLE_SOFT, label)}${hexForeground(PURPLE_VIVID, "─".repeat(Math.ceil(dashCount / 2)))}${hexForeground(PURPLE_VIVID, "╯")}`;
}

function line(theme: WelcomeTheme, label: string, value: string): string {
  return `${theme.fg("muted", `${label}:`)} ${theme.fg("text", value)}`;
}

function card(theme: WelcomeTheme, width: number, title: string, rows: string[]): string[] {
  const boxWidth = Math.max(24, width);
  const innerWidth = boxWidth - 2;
  const label = ` ${title} `;
  const dashCount = Math.max(0, innerWidth - visibleWidth(label));
  const border = (text: string) => hexForeground(PURPLE_SOFT, text);
  const titleText = theme.fg("accent", theme.bold(label));
  const top = `${border("╭")}${border("─".repeat(Math.floor(dashCount / 2)))}${titleText}${border("─".repeat(Math.ceil(dashCount / 2)))}${border("╮")}`;
  const contentWidth = Math.max(1, boxWidth - 4);
  const content = rows.map((row) => `${border("│")} ${fit(row, contentWidth)} ${border("│")}`);
  const bottom = `${border("╰")}${border("─".repeat(innerWidth))}${border("╯")}`;
  return [top, ...content, bottom];
}

function buildInfo(theme: WelcomeTheme, data: WelcomeData, width: number): string[] {
  const location = data.branch ? `${data.cwd}  ${theme.fg("accent", `(${data.branch})`)}` : data.cwd;
  const loaded = [
    `${theme.fg("accent", String(data.loaded.extensions))} ${theme.fg("muted", "extensions")}`,
    `${theme.fg("accent", String(data.loaded.skills))} ${theme.fg("muted", "skills")}`,
    `${theme.fg("accent", String(data.loaded.themes))} ${theme.fg("muted", "themes")}`,
    `${theme.fg("accent", String(data.loaded.prompts))} ${theme.fg("muted", "prompts")}`,
  ];
  const recent = data.recentSessions.length > 0
    ? data.recentSessions.map((session) => `${theme.fg("muted", "•")} ${theme.fg("text", session)}`)
    : [theme.fg("dim", "No recent sessions")];

  return [
    ...card(theme, width, "project", [
      line(theme, "path", location),
      line(theme, "model", `${data.provider} / ${data.model}`),
      line(theme, "thinking", data.thinking),
    ]),
    "",
    ...card(theme, width, "loaded", loaded),
    "",
    ...card(theme, width, "recent sessions", recent),
    "",
    ...card(theme, width, "useful commands", [
      `${theme.fg("muted", "/new")}  start a fresh session`,
      `${theme.fg("muted", "/resume")}  switch sessions`,
      `${theme.fg("muted", "/tree")}  rewind and continue from a message`,
      `${theme.fg("muted", "/fork")}  branch from an earlier message`,
      `${theme.fg("muted", "/compact")}  reduce context size manually`,
      `${theme.fg("muted", "/session")}  inspect session file and usage`,
      `${theme.fg("muted", "/reload")}  reload extensions and settings`,
      `${theme.fg("muted", "/welcome")}  show this screen again`,
    ]),
    "",
    ...card(theme, width, "keyboard shortcuts", [
      `${theme.fg("accent", "Ctrl+P")}  cycle models (also path/session picker)`,
      `${theme.fg("accent", "Shift+Tab")}  cycle thinking level`,
      `${theme.fg("accent", "Ctrl+O")}  expand or collapse tool output`,
      `${theme.fg("accent", "Alt+Enter")}  queue a follow-up while running`,
      `${theme.fg("accent", "Alt+↑")}  restore queued messages`,
      `${theme.fg("accent", "Ctrl+T")}  collapse or expand thinking blocks`,
      `${theme.fg("accent", "Ctrl+X")}  copy the last assistant message`,
      `${theme.fg("dim", "/hotkeys")}  show the complete shortcut list`,
      `${theme.fg("dim", "Any key")}  continue`,
    ]),
  ];
}

class WelcomeScreen implements Component {
  focused = false;

  constructor(
    private readonly theme: WelcomeTheme,
    private readonly data: WelcomeData,
    private readonly dismiss: () => void,
  ) {}

  handleInput(_data: string): void {
    this.dismiss();
  }

  invalidate(): void {}

  render(width: number): string[] {
    const boxWidth = Math.max(40, Math.min(112, width - 2));
    const showAlphaArt = width >= 100;
    const showAsciiLogo = width >= 70;
    const showImage = showAlphaArt || showAsciiLogo;
    const art = showAlphaArt ? ALPHA_ART : ASCII_LOGO;
    const leftWidth = showAlphaArt ? 60 : showAsciiLogo ? 20 : 0;
    const rightWidth = leftWidth > 0 ? Math.max(24, boxWidth - leftWidth - 3) : boxWidth;
    const title = hexForeground(PURPLE_SOFT, ` ${this.theme.bold("pi agent")} `);
    const subtitle = hexForeground(PURPLE_SOFT, ` v${VERSION} `);
    const infoLines = buildInfo(this.theme, this.data, rightWidth);

    if (!showImage) {
      return [
        "",
        borderLine(boxWidth, "──", title + subtitle),
        ...infoLines,
        bottomBorder(boxWidth),
        "",
      ].map((item) => truncateToWidth(item, width, ""));
    }

    const artLines = art.map((item) => center(gradientText(item), leftWidth));
    const leftLines = [
      "",
      center(this.theme.fg("accent", this.theme.bold("Welcome back!")), leftWidth),
      "",
      ...artLines,
      "",
      center(this.theme.fg("text", this.data.model), leftWidth),
      center(this.theme.fg("muted", this.data.provider), leftWidth),
    ];
    const rows = Math.max(leftLines.length, infoLines.length);
    const output = ["", borderLine(boxWidth, "──", title + subtitle)];

    for (let index = 0; index < rows; index++) {
      const left = fit(leftLines[index] ?? "", leftWidth);
      const right = fit(infoLines[index] ?? "", rightWidth);
      output.push(
        `${hexForeground(PURPLE_VIVID, "│")}${left}${hexForeground(PURPLE_VIVID, "│")}${right}${hexForeground(PURPLE_VIVID, "│")}`,
      );
    }

    output.push(bottomBorder(boxWidth), "");
    return output.map((item) => truncateToWidth(item, width, ""));
  }
}

export default function collinPowerlineWelcome(pi: ExtensionAPI): void {
  const WELCOME_WIDGET_KEY = "collin-powerline-welcome";
  let active = false;
  let dismissActive: (() => void) | undefined;
  let terminalInputUnsubscribe: (() => void) | undefined;
  let startupTimer: ReturnType<typeof setTimeout> | undefined;

  function dismissWelcome(): void {
    if (startupTimer !== undefined) {
      clearTimeout(startupTimer);
      startupTimer = undefined;
    }
    dismissActive?.();
  }

  function scheduleStartupWelcome(ctx: ExtensionContext): void {
    if (startupTimer !== undefined) clearTimeout(startupTimer);
    startupTimer = setTimeout(() => {
      startupTimer = undefined;
      showWelcome(ctx);
    }, 100);
  }

  function showWelcome(ctx: ExtensionContext): void {
    if (ctx.mode !== "tui" || active) return;
    active = true;

    const dismiss = () => {
      if (!active) return;
      active = false;
      if (dismissActive === dismiss) dismissActive = undefined;
      terminalInputUnsubscribe?.();
      terminalInputUnsubscribe = undefined;
      ctx.ui.setWidget(WELCOME_WIDGET_KEY, undefined);
    };

    dismissActive = dismiss;
    ctx.ui.setWidget(
      WELCOME_WIDGET_KEY,
      (_tui, theme) => new WelcomeScreen(theme, getWelcomeData(ctx), dismiss),
      { placement: "belowEditor" },
    );
    terminalInputUnsubscribe = ctx.ui.onTerminalInput(() => {
      dismiss();
    });
  }

  pi.registerCommand("welcome", {
    description: "Show the Pi welcome dashboard",
    handler: async (_args, ctx) => showWelcome(ctx),
  });

  pi.on("session_start", async (event, ctx) => {
    if (!welcomeEnabled(ctx)) return;
    if (event.reason === "startup" || event.reason === "reload") {
      // Let Pi finish laying out the editor and other startup widgets first.
      scheduleStartupWelcome(ctx);
    }
  });

  pi.on("agent_start", async (_event, _ctx) => {
    dismissWelcome();
  });

  pi.on("tool_call", async (_event, _ctx) => {
    dismissWelcome();
  });

  pi.on("session_shutdown", async () => {
    dismissWelcome();
    terminalInputUnsubscribe?.();
    terminalInputUnsubscribe = undefined;
    dismissActive = undefined;
    active = false;
  });
}
