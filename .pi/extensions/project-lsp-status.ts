import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { accessSync, constants, readdirSync, readFileSync } from "node:fs";
import { delimiter, extname, isAbsolute, join } from "node:path";

const STATUS_KEY = "project-lsp";
const CONFIG_FILE = "lsp.json";
const LOCKFILE = ["lsp", "lsp.lock.json"] as const;
const MAX_FILES = 5000;
const SKIPPED_DIRECTORIES = new Set([
  ".git",
  ".pi",
  ".venv",
  "build",
  "coverage",
  "dist",
  "node_modules",
  "out",
  "target",
  "vendor",
]);

const SERVER_EXTENSIONS: Record<string, readonly string[]> = {
  vtsls: [".cjs", ".cts", ".js", ".jsx", ".mjs", ".mts", ".ts", ".tsx"],
  pyright: [".py", ".pyi"],
  gopls: [".go"],
  "rust-analyzer": [".rs"],
  yamlls: [".yaml", ".yml"],
  jsonls: [".json", ".jsonc"],
};

const FILETYPE_EXTENSIONS: Record<string, string> = {
  javascript: ".js",
  javascriptreact: ".jsx",
  typescript: ".ts",
  typescriptreact: ".tsx",
  python: ".py",
  go: ".go",
  rust: ".rs",
  yaml: ".yaml",
  json: ".json",
  jsonc: ".jsonc",
};

type ServerConfig = {
  disabled?: boolean;
  filetypes?: string[];
  install?: {
    command?: string[];
  };
};

type LspConfig = {
  servers?: Record<string, ServerConfig>;
};

type LockEntry = {
  resolvedCommand?: string[];
};

type LspLockfile = {
  servers?: Record<string, LockEntry>;
};

function readJson<T>(path: string): T | null {
  try {
    return JSON.parse(readFileSync(path, "utf8")) as T;
  } catch {
    return null;
  }
}

function getConfig(): LspConfig {
  return readJson<LspConfig>(join(getAgentDir(), CONFIG_FILE)) ?? {};
}

function getLockfile(): LspLockfile {
  return readJson<LspLockfile>(join(getAgentDir(), ...LOCKFILE)) ?? {};
}

function expandHome(path: string): string {
  const home = process.env.HOME ?? process.env.USERPROFILE ?? "";
  if (path === "~") return home;
  if (path.startsWith("~/") || path.startsWith("~\\")) return join(home, path.slice(2));
  return path;
}

function commandAvailable(command: string): boolean {
  const expanded = expandHome(command);
  if (isAbsolute(expanded) || expanded.includes("/") || expanded.includes("\\")) {
    try {
      accessSync(expanded, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }

  const pathEntries = (process.env.PATH ?? "").split(delimiter).filter(Boolean);
  const candidates = process.platform === "win32" ? [expanded, `${expanded}.exe`, `${expanded}.cmd`] : [expanded];
  return pathEntries.some((entry) => candidates.some((candidate) => {
    try {
      accessSync(join(entry, candidate), constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }));
}

function getServerExtensions(serverId: string, server: ServerConfig): readonly string[] {
  if (server.filetypes && server.filetypes.length > 0) {
    return server.filetypes
      .map((filetype) => FILETYPE_EXTENSIONS[filetype] ?? filetype)
      .filter((extension) => extension.startsWith("."));
  }
  return SERVER_EXTENSIONS[serverId] ?? [];
}

function collectProjectExtensions(root: string): Set<string> {
  const extensions = new Set<string>();
  const pending = [root];
  let filesSeen = 0;

  while (pending.length > 0 && filesSeen < MAX_FILES) {
    const directory = pending.pop();
    if (!directory) continue;

    let entries;
    try {
      entries = readdirSync(directory, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!SKIPPED_DIRECTORIES.has(entry.name)) pending.push(join(directory, entry.name));
        continue;
      }
      if (!entry.isFile()) continue;

      filesSeen += 1;
      const extension = extname(entry.name).toLowerCase();
      if (extension) extensions.add(extension);
      if (filesSeen >= MAX_FILES) break;
    }
  }

  return extensions;
}

function formatStatus(root: string): string {
  const config = getConfig();
  const lockfile = getLockfile();
  const projectExtensions = collectProjectExtensions(root);
  const detected: string[] = [];
  const missing: string[] = [];

  for (const [serverId, server] of Object.entries(config.servers ?? {})) {
    if (server.disabled) continue;

    const supportedExtensions = getServerExtensions(serverId, server);
    if (!supportedExtensions.some((extension) => projectExtensions.has(extension))) continue;

    const command = server.install?.command?.[0];
    const lockedCommand = lockfile.servers?.[serverId]?.resolvedCommand?.[0];
    if ((lockedCommand && commandAvailable(lockedCommand)) || (command && commandAvailable(command))) {
      detected.push(serverId);
    } else {
      missing.push(serverId);
    }
  }

  detected.sort();
  missing.sort();
  if (detected.length === 0 && missing.length === 0) return "none detected";

  const parts = detected;
  if (missing.length > 0) parts.push(`missing: ${missing.join(", ")}`);
  return parts.join(" ");
}

function updateStatus(ctx: ExtensionContext, force = false): void {
  if (!ctx.hasUI) return;
  ctx.ui.setStatus(STATUS_KEY, formatStatus(ctx.cwd));
  if (force) ctx.ui.notify("Project LSP status refreshed.", "info");
}

export default function projectLspStatus(pi: ExtensionAPI): void {
  pi.on("session_start", async (_event, ctx) => updateStatus(ctx));
  pi.on("turn_end", async (_event, ctx) => updateStatus(ctx));
  pi.on("session_shutdown", async (_event, ctx) => ctx.ui.setStatus(STATUS_KEY, undefined));

  pi.registerCommand("lsp-project", {
    description: "Refresh the project LSP powerline status",
    handler: async (_args, ctx) => updateStatus(ctx, true),
  });
}
