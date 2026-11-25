import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  chmodSync, closeSync, constants, fstatSync, linkSync, lstatSync, mkdirSync, mkdtempSync,
  openSync, readdirSync, readSync, realpathSync, renameSync, rmSync, unlinkSync, writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const limit = 128_000;
const sensitive = /^(\.|node_modules$|__pycache__$|id_(rsa|dsa|ecdsa|ed25519)|credentials?([._-]|$)|secrets?([._-]|$))|\.(pem|p12|pfx|key)$/i;
const textResult = (text: string) => ({ content: [{ type: "text" as const, text }], details: {} });

const sandbox = "/usr/bin/sandbox-exec";
const sandboxPolicy = String.raw`
(version 1)
(deny default)
(allow process-exec process-fork sysctl-read)
(allow file-read-metadata)
(allow file-read* (subpath (param "ROOT")) (subpath (param "SCRATCH")) (subpath (param "PYTHON_RUNTIME"))
  (subpath "/System") (subpath "/usr") (subpath "/bin") (subpath "/sbin")
  (subpath "/Library/Apple") (subpath "/Library/Developer/CommandLineTools")
  (subpath "/opt/homebrew") (subpath "/private/var/db/dyld")
  (literal "/" "/dev/null" "/dev/urandom" "/dev/random"))
(deny file-read* (regex #"/\.(git|ssh|pi|env[^/]*|aws|netrc)(/|$)" #"\.(key|pem|p12|pfx)$"))
(allow file-write* (subpath (param "SCRATCH")) (literal "/dev/null"))`;

// A uv venv symlinks to a managed interpreter with its stdlib and dynamic
// libraries outside the project. Allow only that installation, not uv's cache,
// other Python versions, or an arbitrary target chosen by a project symlink.
function uvPython(root: string) {
  const bin = join(root, ".venv", "bin");
  try {
    if (realpathSync(bin) !== bin) return undefined;
    const python = realpathSync(join(bin, "python"));
    const runtime = dirname(dirname(python));
    const managed = join(realpathSync(homedir()), ".local", "share", "uv", "python");
    const version = basename(runtime).match(/^cpython-(\d+\.\d+)\.\d+t?-macos-[a-z0-9_]+-[a-z0-9_]+$/);
    if (dirname(runtime) !== managed || !version || dirname(python) !== join(runtime, "bin")) return undefined;
    if (basename(python) !== `python${version[1]}` && basename(python) !== `python${version[1]}t`) return undefined;
    if (!lstatSync(python).isFile()) return undefined;
    return runtime;
  } catch {
    return undefined;
  }
}

async function runCommand(root: string, command: string, signal?: AbortSignal) {
  const runtime = uvPython(root);
  const scratch = realpathSync(mkdtempSync(join(tmpdir(), "pi-chat-command-")));
  try {
    return await new Promise<string>((resolve, reject) => {
      const child = spawn(sandbox, ["-D", `ROOT=${root}`, "-D", `SCRATCH=${scratch}`,
        "-D", `PYTHON_RUNTIME=${runtime ?? scratch}`, "-p", sandboxPolicy,
        "/bin/sh", "-c", command], {
        cwd: root, detached: true, stdio: ["ignore", "pipe", "pipe"],
        env: { PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
          HOME: scratch, TMPDIR: scratch, LANG: "en_US.UTF-8", PYTHONDONTWRITEBYTECODE: "1", UV_OFFLINE: "1" },
      });
      const chunks: Buffer[] = [];
      const cap = 24_000;
      let size = 0;
      let stopped = false;
      function stop() {
        stopped = true;
        if (child.pid !== undefined) {
          try { process.kill(-child.pid, "SIGKILL"); } catch { /* already gone */ }
        }
      }
      const timer = setTimeout(stop, 30_000);
      const done = () => { clearTimeout(timer); signal?.removeEventListener("abort", stop); };
      signal?.addEventListener("abort", stop, { once: true });
      if (signal?.aborted) stop();
      child.stdout.on("data", capture);
      child.stderr.on("data", capture);
      function capture(bytes: Buffer) {
        if (size < cap) chunks.push(bytes.subarray(0, cap - size));
        size += bytes.length;
        if (size >= cap) stop();
      }
      child.once("error", (err) => { done(); reject(err); });
      child.once("close", (code) => {
        // Kill any detached-from-stdio background work still in this group.
        const summary = stopped ? "Stopped (cancelled, 30-second limit, or output limit)" : `Exit ${code}`;
        stop();
        done();
        resolve(`${summary}\n${Buffer.concat(chunks).toString("utf8")}`);
      });
    });
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

export default function (pi: ExtensionAPI) {
  const configured = process.env.NVIM_AI_PI_ROOT;
  if (!configured || !isAbsolute(configured)) throw new Error("Missing Pi Chat workspace root");
  const root = realpathSync(configured);
  if (root === sep || root === realpathSync(homedir())) throw new Error("Open Pi Chat from a project directory");

  function checked(path: string, kind: "directory" | "file" | "new") {
    const target = resolve(root, path);
    const rel = relative(root, target);
    const parts = rel === "" ? [] : rel.split(sep);
    if (isAbsolute(rel) || parts.some((part) => sensitive.test(part)) || /[\u0000-\u001f\u007f]/.test(path)) {
      throw new Error("Path is outside the workspace or is protected");
    }
    if (!parts.length && kind !== "directory") throw new Error("Select a file within the workspace");
    let current = root;
    for (let index = 0; index < parts.length; index++) {
      current = join(current, parts[index]);
      const stat = lstatSync(current, { throwIfNoEntry: false });
      const last = index === parts.length - 1;
      if (last && kind === "new" && !stat) return target;
      if (!stat || stat.isSymbolicLink()) throw new Error("Missing path or symbolic link");
      if (!last || kind === "directory") {
        if (!stat.isDirectory()) throw new Error("Expected a directory");
      } else if (kind === "new" || !stat.isFile() || stat.nlink !== 1 || stat.size > limit) {
        throw new Error("Expected a small, regular file, or an unused path for creation");
      }
    }
    return target;
  }

  function fileText(target: string) {
    const fd = openSync(target, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    try {
      const stat = fstatSync(fd);
      if (!stat.isFile() || stat.nlink !== 1 || stat.size > limit) throw new Error("Expected a small, regular text file");
      const bytes = Buffer.alloc(limit + 1);
      let length = 0;
      while (length < bytes.length) {
        const count = readSync(fd, bytes, length, bytes.length - length, null);
        if (!count) break;
        length += count;
      }
      const text = bytes.subarray(0, length);
      if (text.includes(0) || length > limit) throw new Error("Expected a small UTF-8 text file");
      return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(text);
    } finally {
      closeSync(fd);
    }
  }

  function* entries(directory: string) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (!sensitive.test(entry.name) && (entry.isDirectory() || entry.isFile())) yield entry;
    }
  }

  type Confirm = (title: string, message: string) => Promise<boolean>;
  async function approved(confirm: Confirm, payload: object, signal?: AbortSignal) {
    if (signal?.aborted) return false;
    const yes = await confirm("Review Pi workspace change", JSON.stringify(payload));
    return yes && !signal?.aborted;
  }

  async function change(
    path: string,
    replacement: (before: string) => string,
    create: boolean,
    confirm: Confirm,
    signal?: AbortSignal,
  ) {
    const kind = create ? "new" : "file";
    const target = checked(path, kind);
    const before = create ? "" : fileText(target);
    const after = replacement(before);
    if (after.includes("\0") || Buffer.byteLength(after) > limit) throw new Error("Proposed text exceeds the file limits");
    if (!create && after === before) return textResult("No changes proposed.");
    if (!(await approved(confirm, { operation: create ? "create" : "edit", path: target, before, after }, signal))) {
      return textResult("Change was not approved; no file was written.");
    }
    checked(target, kind);
    if (!create && fileText(target) !== before) throw new Error("File changed during review; read it again before editing");
    const mode = create ? 0o644 : lstatSync(target).mode & 0o777;
    const temp = mkdtempSync(join(dirname(target), ".pi-review-"));
    try {
      const staged = join(temp, "replacement");
      writeFileSync(staged, after, { flag: "wx", mode: 0o600 });
      chmodSync(staged, mode);
      if (create) linkSync(staged, target); // Refuse to replace a file that appeared during review.
      else renameSync(staged, target);
    } finally {
      rmSync(temp, { recursive: true, force: true });
    }
    return textResult(`Wrote ${relative(root, target)} after approval.`);
  }

  const pathParam = Type.String({ description: "A workspace-relative path (or an absolute path within this workspace)." });
  pi.registerTool({
    name: "workspace_list", label: "List workspace files", description: "List a directory in the current workspace. Use '.' to start at the root.",
    parameters: Type.Object({ path: pathParam }),
    async execute(_id, { path }) {
      const result = Array.from(entries(checked(path, "directory")), (entry) => entry.name + (entry.isDirectory() ? "/" : ""));
      return textResult(result.slice(0, 300).join("\n") + (result.length > 300 ? "\n[More entries omitted]" : ""));
    },
  });
  pi.registerTool({
    name: "workspace_search", label: "Search workspace", description: "Recursively find file names or literal text in small workspace files. Results include relative paths and matching line numbers.",
    parameters: Type.Object({ path: pathParam, query: Type.String({ minLength: 1, maxLength: 200 }),
      mode: Type.Union([Type.Literal("name"), Type.Literal("text")]) }),
    async execute(_id, { path, query, mode }, signal) {
      const start = checked(path, "directory");
      const pending = [start];
      const matches: string[] = [];
      let scanned = 0, bytes = 0, truncated = false;
      scan: while (pending.length) {
        const dir = pending.pop()!;
        try {
          for (const entry of entries(checked(dir, "directory"))) {
            if (signal?.aborted) throw new Error("Search cancelled");
            if (++scanned > 3000 || bytes > 8_000_000 || matches.length >= 100) { truncated = true; break scan; }
            const target = join(dir, entry.name);
            if (entry.isDirectory()) { pending.push(target); continue; }
            if (mode === "name") {
              if (entry.name.includes(query)) matches.push(relative(root, target));
            } else {
              try {
                const text = fileText(checked(target, "file"));
                bytes += Buffer.byteLength(text);
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                  if (!lines[i].includes(query)) continue;
                  matches.push(`${relative(root, target)}:${i + 1}: ${lines[i].slice(0, 300)}`);
                  if (matches.length >= 100) { truncated = true; break scan; }
                }
              } catch { /* Non-text, oversized, unreadable, or changed file. */ }
            }
          }
        } catch (error) {
          if (dir === start || signal?.aborted) throw error;
        }
      }
      return textResult((matches.join("\n") || "No matches.") + (truncated ? "\n[Search limit reached; narrow the directory or query.]" : ""));
    },
  });
  pi.registerTool({
    name: "workspace_read", label: "Read workspace file", description: "Read a UTF-8 text file inside the workspace. Hidden paths and symlinks are blocked.",
    parameters: Type.Object({ path: pathParam }),
    async execute(_id, { path }) { return textResult(fileText(checked(path, "file"))); },
  });
  pi.registerTool({
    name: "workspace_edit", label: "Propose workspace edit", description: "Replace exact text in an existing file. Provide either one oldText/newText pair or an array of disjoint edits. Neovim reviews the combined diff before writing.",
    parameters: Type.Object({ path: pathParam, oldText: Type.Optional(Type.String({ minLength: 1 })), newText: Type.Optional(Type.String()),
      edits: Type.Optional(Type.Array(Type.Object({ oldText: Type.String({ minLength: 1 }), newText: Type.String() }), { minItems: 1, maxItems: 50 })) }),
    async execute(_id, { path, oldText, newText, edits }, signal, _update, ctx) {
      if (edits ? oldText !== undefined || newText !== undefined : oldText === undefined || newText === undefined) {
        throw new Error("Provide either an edits array or one oldText/newText pair");
      }
      return change(path, (before) => {
        const spans = (edits ?? [{ oldText: oldText!, newText: newText! }]).map(({ oldText, newText }) => {
          const start = before.indexOf(oldText);
          if (start < 0 || before.indexOf(oldText, start + 1) >= 0) throw new Error("Each target must match exactly once in the original file");
          return { start, end: start + oldText.length, newText };
        }).sort((a, b) => a.start - b.start);
        let end = 0;
        const result = [];
        for (const span of spans) {
          if (span.start < end) throw new Error("Edits must not overlap");
          result.push(before.slice(end, span.start), span.newText);
          end = span.end;
        }
        return result.join("") + before.slice(end);
      }, false, (title, message) => ctx.ui.confirm(title, message, { signal, timeout: 120_000 }), signal);
    },
  });
  if (process.platform === "darwin" && lstatSync(sandbox, { throwIfNoEntry: false })?.isFile()) {
    pi.registerTool({
      name: "workspace_run", label: "Run a sandboxed command",
      description: "Request approval to run a shell command for inspection, tests, or linting. The workspace is read-only and network access is denied. Use workspace_edit or workspace_create for changes.",
      parameters: Type.Object({ command: Type.String({ minLength: 1, maxLength: 1024 }) }),
      async execute(_id, { command }, signal, _update, ctx) {
        if (/[\u0000-\u001f\u007f]/.test(command) || Buffer.byteLength(command) > 1024) throw new Error("Use a single command line");
        if (signal?.aborted || !(await ctx.ui.confirm("Run Pi workspace command", JSON.stringify({ command }), { signal, timeout: 120_000 })) || signal?.aborted) {
          return textResult("Command was not approved; nothing ran.");
        }
        return textResult(await runCommand(root, command, signal));
      },
    });
  }
  pi.registerTool({
    name: "workspace_create", label: "Propose new workspace file", description: "Create a UTF-8 file in an existing directory. Neovim must approve its contents. Cannot overwrite an existing file.",
    parameters: Type.Object({ path: pathParam, text: Type.String() }),
    async execute(_id, { path, text }, signal, _update, ctx) {
      return change(path, () => text, true, (title, message) => ctx.ui.confirm(title, message, { signal, timeout: 120_000 }), signal);
    },
  });
  pi.registerTool({
    name: "workspace_mkdir", label: "Propose directory creation", description: "Create one new workspace directory under an existing parent, after approval.",
    parameters: Type.Object({ path: pathParam }),
    async execute(_id, { path }, signal, _update, ctx) {
      const target = checked(path, "new");
      const confirm: Confirm = (title, message) => ctx.ui.confirm(title, message, { signal, timeout: 120_000 });
      if (!(await approved(confirm, { operation: "mkdir", path: target }, signal))) return textResult("Directory creation rejected.");
      mkdirSync(checked(target, "new"));
      return textResult(`Created ${relative(root, target)}/ after approval.`);
    },
  });
  pi.registerTool({
    name: "workspace_move", label: "Propose file move", description: "Move or rename one small workspace text file, after approval. The destination directory must exist, and existing files are never overwritten.",
    parameters: Type.Object({ path: pathParam, destination: pathParam }),
    async execute(_id, { path, destination }, signal, _update, ctx) {
      const source = checked(path, "file");
      const target = checked(destination, "new");
      const before = fileText(source);
      const confirm: Confirm = (title, message) => ctx.ui.confirm(title, message, { signal, timeout: 120_000 });
      if (!(await approved(confirm, { operation: "move", path: source, destination: target }, signal))) return textResult("Move rejected.");
      if (fileText(checked(source, "file")) !== before) throw new Error("Source changed during review");
      // Link fails atomically if the destination was created during review.
      linkSync(source, checked(target, "new"));
      try { unlinkSync(source); } catch (error) { unlinkSync(target); throw error; }
      return textResult(`Moved ${relative(root, source)} to ${relative(root, target)} after approval.`);
    },
  });
  pi.registerTool({
    name: "workspace_delete", label: "Propose file deletion", description: "Delete a single small workspace text file after reviewing the removed lines. Does not delete directories or symlinks.",
    parameters: Type.Object({ path: pathParam }),
    async execute(_id, { path }, signal, _update, ctx) {
      const target = checked(path, "file");
      const before = fileText(target);
      const confirm: Confirm = (title, message) => ctx.ui.confirm(title, message, { signal, timeout: 120_000 });
      if (!(await approved(confirm, { operation: "delete", path: target, before, after: "" }, signal))) return textResult("Deletion rejected.");
      if (fileText(checked(target, "file")) !== before) throw new Error("File changed during review");
      unlinkSync(target);
      return textResult(`Deleted ${relative(root, target)} after approval.`);
    },
  });
}
