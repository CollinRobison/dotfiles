import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  fuzzyFilter,
  type AutocompleteItem,
  type AutocompleteProvider,
} from "@earendil-works/pi-tui";
import { readdir } from "node:fs/promises";
import { basename, isAbsolute, join, sep } from "node:path";

const ADD_DIR_STATE = "add-dir:state";
const MAX_ADDED_DIRECTORIES = 12;
const MAX_FILES_PER_DIRECTORY = 2500;
const MAX_TOTAL_PATHS = 6000;
const MAX_SUGGESTIONS = 30;
const CACHE_TTL_MS = 5000;
const SKIPPED_DIRECTORIES = new Set([".git", "node_modules"]);
const SKIPPED_PI_DIRECTORIES = new Set(["git", "npm", "sessions"]);

type AddedDirectory = {
  absolutePath: string;
  label: string;
};

type ExternalPath = {
  directory: AddedDirectory;
  relativePath: string;
  absolutePath: string;
  isDirectory: boolean;
};

type DirectoryCache = {
  key: string;
  expiresAt: number;
  paths: ExternalPath[];
};

let activeContext: ExtensionContext | undefined;
let providerRegistered = false;
let directoryCache: DirectoryCache | undefined;

function getAddedDirectories(ctx: ExtensionContext): AddedDirectory[] {
  let directories: AddedDirectory[] = [];

  for (const entry of ctx.sessionManager.getBranch()) {
    const customEntry = entry as {
      type?: string;
      customType?: string;
      data?: unknown;
    };
    if (customEntry.type !== "custom" || customEntry.customType !== ADD_DIR_STATE) continue;

    const data = customEntry.data as { dirs?: unknown } | undefined;
    if (!Array.isArray(data?.dirs)) continue;

    directories = data.dirs.flatMap((value): AddedDirectory[] => {
      if (!value || typeof value !== "object") return [];
      const candidate = value as { absolutePath?: unknown; label?: unknown };
      if (
        typeof candidate.absolutePath !== "string" ||
        candidate.absolutePath.length === 0 ||
        !isAbsolute(candidate.absolutePath)
      ) return [];
      return [{
        absolutePath: candidate.absolutePath,
        label: typeof candidate.label === "string" && candidate.label.length > 0
          ? candidate.label
          : basename(candidate.absolutePath),
      }];
    });
  }

  const unique = new Map<string, AddedDirectory>();
  for (const directory of directories) unique.set(directory.absolutePath, directory);
  return [...unique.values()].slice(0, MAX_ADDED_DIRECTORIES);
}

async function scanDirectory(
  directory: AddedDirectory,
  signal: AbortSignal,
): Promise<ExternalPath[]> {
  const paths: ExternalPath[] = [];
  const pending = [{ absolutePath: directory.absolutePath, relativePath: "" }];

  while (pending.length > 0 && paths.length < MAX_FILES_PER_DIRECTORY) {
    if (signal.aborted) return [];
    const current = pending.pop();
    if (!current) continue;

    let entries;
    try {
      entries = await readdir(current.absolutePath, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (signal.aborted) return [];
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory() && SKIPPED_DIRECTORIES.has(entry.name)) continue;
      if (entry.isDirectory() && current.relativePath === ".pi" && SKIPPED_PI_DIRECTORIES.has(entry.name)) continue;
      if (!entry.isDirectory() && !entry.isFile()) continue;

      const entryRelativePath = current.relativePath
        ? `${current.relativePath}/${entry.name}`
        : entry.name;
      const entryAbsolutePath = join(current.absolutePath, entry.name);
      const isDirectory = entry.isDirectory();

      paths.push({
        directory,
        relativePath: entryRelativePath.replaceAll(sep, "/"),
        absolutePath: entryAbsolutePath,
        isDirectory,
      });

      if (isDirectory && paths.length < MAX_FILES_PER_DIRECTORY) {
        pending.push({ absolutePath: entryAbsolutePath, relativePath: entryRelativePath });
      }
      if (paths.length >= MAX_FILES_PER_DIRECTORY) break;
    }
  }

  return paths;
}

async function getExternalPaths(
  directories: AddedDirectory[],
  signal: AbortSignal,
): Promise<ExternalPath[]> {
  const key = directories.map(({ absolutePath }) => absolutePath).join("\0");
  if (directoryCache && directoryCache.key === key && directoryCache.expiresAt > Date.now()) {
    return directoryCache.paths;
  }

  const paths: ExternalPath[] = [];
  for (const directory of directories) {
    const remaining = MAX_TOTAL_PATHS - paths.length;
    if (remaining <= 0) break;

    const scanned = await scanDirectory(directory, signal);
    paths.push(...scanned.slice(0, remaining));
    if (signal.aborted) return [];
  }

  directoryCache = { key, expiresAt: Date.now() + CACHE_TTL_MS, paths };
  return paths;
}

function extractExternalAtPrefix(text: string): { prefix: string; query: string } | undefined {
  const match = text.match(/(?:^|[\s"'=])(@[^\s"'=]*)$/);
  if (!match) return undefined;

  const prefix = match[1];
  const query = prefix.slice(1);
  // Let Pi's native provider handle explicit local, home, and absolute paths.
  if (query.startsWith("/") || query.startsWith("~/") || query.startsWith("./") || query.startsWith("../")) {
    return undefined;
  }
  return { prefix, query };
}

function formatAttachmentPath(path: string): string {
  const normalized = path.replaceAll(sep, "/");
  if (!/[\s"']/.test(normalized)) return `@${normalized}`;
  return `@"${normalized.replaceAll('"', '\\"')}"`;
}

function makeSuggestions(paths: ExternalPath[], query: string): AutocompleteItem[] {
  if (query.length === 0) return [];

  const candidates = paths.map((path) => ({
    path,
    searchText: `${path.directory.label}/${path.relativePath}`,
  }));
  const matches = fuzzyFilter(candidates, query, (candidate) => candidate.searchText)
    .slice(0, MAX_SUGGESTIONS);

  return matches.map(({ path }) => ({
    value: formatAttachmentPath(path.absolutePath + (path.isDirectory ? sep : "")),
    label: `${path.directory.label}/${path.relativePath}${path.isDirectory ? "/" : ""}`,
    description: path.directory.absolutePath,
  }));
}

function createProvider(current: AutocompleteProvider): AutocompleteProvider {
  return {
    triggerCharacters: ["@"],

    async getSuggestions(lines, cursorLine, cursorCol, options) {
      const line = lines[cursorLine] ?? "";
      const beforeCursor = line.slice(0, cursorCol);
      const atPrefix = extractExternalAtPrefix(beforeCursor);
      if (!atPrefix) return current.getSuggestions(lines, cursorLine, cursorCol, options);

      const ctx = activeContext;
      if (!ctx) return current.getSuggestions(lines, cursorLine, cursorCol, options);

      const directories = getAddedDirectories(ctx);
      if (directories.length === 0) return current.getSuggestions(lines, cursorLine, cursorCol, options);

      const [externalItems, nativeSuggestions] = await Promise.all([
        getExternalPaths(directories, options.signal),
        current.getSuggestions(lines, cursorLine, cursorCol, options),
      ]);
      if (options.signal.aborted) return null;

      const externalSuggestions = makeSuggestions(externalItems, atPrefix.query);
      if (externalSuggestions.length === 0) return nativeSuggestions;

      const seen = new Set<string>();
      const items = [...externalSuggestions, ...(nativeSuggestions?.items ?? [])]
        .filter((item) => {
          if (seen.has(item.value)) return false;
          seen.add(item.value);
          return true;
        })
        .slice(0, MAX_SUGGESTIONS);

      return { items, prefix: atPrefix.prefix };
    },

    applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
      return current.applyCompletion(lines, cursorLine, cursorCol, item, prefix);
    },

    shouldTriggerFileCompletion(lines, cursorLine, cursorCol) {
      return current.shouldTriggerFileCompletion?.(lines, cursorLine, cursorCol) ?? true;
    },
  };
}

function trackContext(ctx: ExtensionContext, pi: ExtensionAPI): void {
  activeContext = ctx;
  // Keep external-directory access explicitly user-controlled. The companion
  // package exposes an LLM-callable add_directory tool; /add-dir is the only
  // path this setup uses to grant a directory access to the session.
  const activeTools = pi.getActiveTools();
  if (activeTools.includes("add_directory")) {
    pi.setActiveTools(activeTools.filter((name) => name !== "add_directory"));
  }
  if (!ctx.hasUI || providerRegistered) return;

  ctx.ui.addAutocompleteProvider((current) => createProvider(current));
  providerRegistered = true;
}

export default function externalDirectoryAutocomplete(pi: ExtensionAPI): void {
  // session_start also fires after /resume, /new, /fork, and /clone.
  pi.on("session_start", async (_event, ctx) => trackContext(ctx, pi));
  pi.on("session_tree", async (_event, ctx) => trackContext(ctx, pi));
  pi.on("session_shutdown", async () => {
    activeContext = undefined;
    directoryCache = undefined;
  });
}
