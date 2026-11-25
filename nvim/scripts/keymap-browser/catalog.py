"""Combined source, runtime, built-in and external shortcut inventory."""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from shortcuts import ANGLE_KEY, external_shortcuts, legacy, tokens

HERE = Path(__file__).resolve().parent
CONFIG = HERE.parents[1]
ATLAS = CONFIG / "scripts" / "keymap-atlas" / "regenerate-keymap-atlas.py"
MODE_NAMES = {"n": "Normal", "x": "Visual", "s": "Select", "o": "Operator-pending",
              "i": "Insert", "l": "Language", "c": "Command-line", "t": "Terminal"}
MODE_GROUPS = {"": ("n", "x", "s", "o"), "v": ("x", "s"), "!": ("i", "c")}
GUIDE = None


def guide():
    global GUIDE
    if GUIDE is None:
        sys.path.insert(0, str(ATLAS.parent))
        spec = importlib.util.spec_from_file_location("atlas_generator", ATLAS)
        GUIDE = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = GUIDE
        spec.loader.exec_module(GUIDE)
    return GUIDE


def nvim_bin():
    return os.environ.get("NVIM_KEYMAPS_NVIM") or shutil.which("nvim") or "nvim"


def nvim_env(**extra):
    env = dict(os.environ, **extra)
    # A launcher started by Neovim can inherit the parent's RPC address.
    env.pop("NVIM", None)
    env.pop("NVIM_LISTEN_ADDRESS", None)
    return env


def mode_codes(modes):
    return list(dict.fromkeys(item for mode in modes for item in MODE_GROUPS.get(mode, (mode,))))


def source_payload(config):
    files = sorted((config / "lua").rglob("*.lua"))
    if (config / "init.lua").is_file():
        files.insert(0, config / "init.lua")
    result = subprocess.run([nvim_bin(), "--clean", "--headless", "-l", str(HERE / "source.lua"),
                             *map(str, files)], env=nvim_env(), capture_output=True, timeout=10)
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        raise RuntimeError("Neovim could not index Lua declarations. " + detail[-1600:])
    return json.loads(result.stdout)


def static_rows(config):
    payload = source_payload(config)
    rows = []
    atlas = guide()
    for item in payload["rows"]:
        path = Path(item["file"])
        rel = path.relative_to(config)
        digest = payload["digests"][item["file"]]
        item.update(
            id=f"{rel.as_posix()}:{item['start']}:{digest[:20]}", digest=digest, file=rel.as_posix(), origin="Config",
            group=atlas.category(rel), modes=mode_codes(item["modes"]),
            desc=item.get("desc") or atlas.best_effort_description(item["rhs"]),
            editable=path.resolve().is_relative_to(config.resolve()),
        )
        rows.append(item)
    commands = {item["name"]: item for item in payload["commands"]}
    for name, item in commands.items():
        rel = Path(item["file"]).relative_to(config)
        group = atlas.category(rel)
        rows.append(dict(id=f"command:{name}", kind="command", origin="Config", key=":" + name,
                         file=rel.as_posix(), line=item["line"], context="Ex command", scope="", modes=[],
                         group="User commands" if group == "Other configured mappings" else group,
                         desc=item.get("desc") or atlas.describe_command(name), editable=False))
    return rows, Path(payload["runtime"])


def runtime_snapshot(config):
    init = config / "init.lua"
    if not init.exists():
        init = config / "init.vim"
    if not init.exists():
        return {}, "No Neovim init file available for the runtime audit"
    with tempfile.TemporaryDirectory(prefix="nvim-keymaps-") as directory:
        probe = Path(directory)
        out = probe / "keymaps.json"
        env = nvim_env(KEYMAP_PROBE_DIR=directory, KEYMAP_PROBE_OUT=str(out),
                   KEYMAP_CONFIG=str(config), KEYMAP_RUNTIME_SCRIPT=str(HERE / "runtime.lua"))
        # A temporary cwd avoids activating project-local config during standalone discovery.
        command = [nvim_bin(), "--headless", "-n", "-i", "NONE",
                   "--cmd", "lua vim.opt.rtp:prepend(vim.env.KEYMAP_CONFIG)", "-u", str(init),
                   "-c", "lua dofile(vim.env.KEYMAP_RUNTIME_SCRIPT)"]
        try:
            proc = subprocess.run(command, cwd=probe, env=env, capture_output=True, timeout=15)
            if out.exists():
                return json.loads(out.read_bytes()), None
            diagnostic = proc.stderr.decode(errors="replace").strip().splitlines()
            return {}, f"Neovim runtime audit failed{': ' + diagnostic[-1][:180] if diagnostic else ''}"
        except (subprocess.SubprocessError, OSError, ValueError) as error:
            return {}, f"Neovim runtime audit unavailable ({type(error).__name__})"


INDEX_GROUPS = {"1": ("i", "Insert mode"), "2": ("n", "Normal mode"),
                "2.1": ("ox", "Text objects"), "2.2": ("n", "Window commands"),
                "2.3": ("n", "Bracket commands"), "2.4": ("n", "g commands"),
                "2.5": ("n", "z commands"), "2.6": ("o", "Operator-pending"),
                "3": ("x", "Visual mode"), "4": ("c", "Command-line editing"),
                "5": ("t", "Terminal mode")}


def index_key(display):
    # Placeholder arguments are documentation. Match the trigger keys before them.
    display = re.sub(r'^\["[a-z]\]\s*', "", display)
    trigger = re.split(r"\s*\{[^{}]+\}", display, maxsplit=1)[0].strip()
    if trigger in ("other", "others") or not trigger:
        return ""
    words = []
    for part in trigger.split():
        if part.startswith("CTRL-SHIFT-"):
            words.append("<C-S-" + part[len("CTRL-SHIFT-"):] + ">")
        elif part.startswith("CTRL-"):
            words.append("<C-" + part[5:] + ">")
        else:
            words.append(part)
    return "".join(words)


def builtin_rows(runtime):
    doc = runtime / "doc" / "index.txt"
    group = None
    context = None
    result = []
    for line in doc.read_text(encoding="utf-8").splitlines():
        if (section := re.match(r"^(\d+(?:\.\d+)?)\.?\s+\S", line)) and "\t*" in line:
            group = INDEX_GROUPS.get(section[1])
            context = None
        if not group:
            continue
        if line.startswith("commands in completion mode"):
            context = "Insert completion"
        elif line.startswith("commands in CTRL-X submode"):
            context = "Insert CTRL-X submode"
        match = re.match(r"^\|([^\t]+?)\|[ \t]+(.+)$", line)
        if not match:
            if context == "Insert completion" and line.startswith("\t\t"):
                match = re.match(r"^\t\t()(.+)$", line)
            if not match:
                continue
        columns = re.split(r"\t+| {2,}", match[2].strip(), maxsplit=1)
        if len(columns) != 2:
            continue
        tag, display, desc = match[1], *columns
        desc = desc.strip()
        inherit_motion = group[0] == "n" and bool(re.match(r"^1\s", desc))
        desc = re.sub(r"^[12]\s+", "", desc)
        key = index_key(display)
        if not key or desc.startswith(("not used", "reserved for")):
            continue
        modes = list(group[0])
        if inherit_motion:
            modes.extend(("x", "o"))
        if desc.startswith("Select mode:"):
            modes = ["s"]
        result.append({
            "origin": "Built-in", "key": key, "display": display, "modes": modes, "desc": desc,
            "context": context or "Neovim command", "scope": "", "group": group[1],
            "file": "Neovim help", "help": tag,
        })
    # Terminal commands in index.txt are described in paragraphs instead of a table.
    for key, tag, desc in (
        ("<C-\\><C-n>", "CTRL-\\_CTRL-N", "Leave Terminal mode and go to Normal mode"),
        ("<C-\\><C-o>", "t_CTRL-\\_CTRL-O", "Execute one Normal-mode command, then return to Terminal mode"),
    ):
        result.append(dict(origin="Built-in", key=key, modes=["t"], desc=desc, scope="",
                           context="Neovim command", group="Terminal mode", file="Neovim help", help=tag))
    return result


def same_scope(left, right):
    lhs, rhs = left.split("|"), right.split("|")
    # An LSP can attach to any relevant filetype. Unknown buffer scope is similarly conditional.
    return bool(set(lhs) & set(rhs) or set(lhs + rhs) & {"*", "lsp"}) and bool(left) and bool(right)


def snapshot_rows(snapshot, config, runtime):
    for row in snapshot.get("rows", []):
        source = row.get("file") or ""
        if source:
            path = Path(source).expanduser()
            if path.is_absolute():
                path = path.resolve()
                if path.is_relative_to(config):
                    source = path.relative_to(config).as_posix()
                elif path.is_relative_to(runtime):
                    source = "Neovim runtime/" + str(path.relative_to(runtime))
                elif "lazy" in path.parts:
                    source = "/".join(path.parts[path.parts.index("lazy") + 1:])
        origin = "Built-in" if source.startswith("Neovim runtime/") else "Runtime"
        group = "Neovim default mappings" if origin == "Built-in" else "Active plugin & session mappings"
        desc = row.get("desc") or row.get("rhs") or "Lua callback"
        yield dict(row, file=source, desc=desc, modes=[row["mode"]], group=group, origin=origin, editable=False)


class Catalog:
    def __init__(self, config, live=None):
        self.config = config.resolve()
        self.live = live or {}
        self.retired = []
        self.refresh(probe=True)

    def refresh(self, probe=False):
        source, runtime = static_rows(self.config)
        self.source = source
        if probe or not hasattr(self, "runtime"):
            self.runtime, self.runtime_warning = runtime_snapshot(self.config)
            self.builtins = builtin_rows(runtime)
        self.external, self.warnings = external_shortcuts()
        if self.runtime_warning:
            self.warnings.insert(0, self.runtime_warning)
        self.leader = self.runtime.get("leader", self.live.get("leader", "\\"))
        self.localleader = self.runtime.get("localleader", self.live.get("localleader", "\\"))
        search = set()
        for row in source:
            for mode in row["modes"]:
                search.add((mode, self.keys(row["key"]), row["scope"]))
        active = {}
        for snapshot in (self.runtime, self.live):
            for row in snapshot_rows(snapshot, self.config, runtime):
                key = self.keys(row["key"])
                mode, scope = row["modes"][0], row["scope"]
                known = (mode, key, scope) in search
                if not known and scope:
                    known = any((mode, key, candidate) in search
                                for candidate in ("markdown|mermaid", "*", "lsp")
                                if same_scope(scope, candidate))
                retired = any(key == old_key and mode in old_modes and
                              (scope == old_scope or same_scope(scope, old_scope))
                              for old_key, old_modes, old_scope in self.retired) if snapshot is self.live else False
                if not known and not retired:
                    active[(mode, key, scope, row["desc"])] = row
        candidates = source + list(active.values()) + self.builtins + self.external
        rows, seen = [], set()
        for row in candidates:
            row.setdefault("scope", "")
            row.setdefault("modes", [])
            row.setdefault("editable", False)
            row.setdefault("group", row["origin"] + " shortcuts")
            row.setdefault("id", f"{row['origin']}:{len(rows)}")
            row["chords"] = () if row.get("kind") == "command" else self.keys(row["key"])
            identity = (row["origin"], row["key"], row["desc"], tuple(row["modes"]), row["scope"],
                        row["context"], row["id"] if row["editable"] else "")
            if identity not in seen:
                rows.append(row)
                seen.add(identity)
        self.rows = rows
        self.by_id = {row["id"]: row for row in rows}

    def keys(self, key):
        return tokens(key, self.leader, self.localleader)

    def propose(self, row, new):
        if not isinstance(new, str) or not new or len(new) > 128 or any(ord(k) < 32 or ord(k) == 127 for k in new):
            raise ValueError("Enter 1–128 keys in Neovim notation, such as <leader>ff or <C-p>.")
        key = self.keys(new)
        if not key or new == row["key"]:
            raise ValueError("Enter a new shortcut.")
        # Validate names and modifiers using Neovim itself without executing the proposed keys.
        names = [match[0] for match in ANGLE_KEY.finditer(new)
                 if match[0].lower() not in ("<leader>", "<localleader>")]
        env = nvim_env(KEYMAP_VALIDATE=json.dumps(names))
        script = ('for _, part in ipairs(vim.json.decode(vim.env.KEYMAP_VALIDATE)) do '
                  'if vim.keycode(part) == part then vim.cmd("cquit 1"); return end end')
        proc = subprocess.run([nvim_bin(), "--clean", "--headless", "-c", "lua " + script, "-c", "qa!"],
                              env=env, capture_output=True, timeout=5)
        if proc.returncode:
            raise ValueError("Neovim did not recognize a key name. Use notation such as <C-p>, <Space>, or <F8>.")
        issues = []
        builtin_prefix = []
        for other in self.rows:
            if row["id"] == other["id"]:
                continue
            origin = other["origin"]
            scopes = (row["scope"], other["scope"])
            chords = other["chords"]
            shorter = min(len(chords), len(key))
            if not shorter:
                continue
            equals = key == chords
            prefix = not equals and key[:shorter] == chords[:shorter]
            if origin in ("Kitty", "System"):
                if origin == "Kitty" and not other["scope"] and (equals or prefix):
                    issues.append(("Kitty can intercept these keys", other))
                elif origin == "Kitty" and other["scope"] and (equals or prefix):
                    issues.append(("Kitty can intercept these keys in its named mode", other))
                elif origin == "System" and (equals or (prefix and len(chords) < len(key))):
                    issues.append(("System shortcut can intercept these keys", other))
                continue
            if not set(row["modes"]) & set(other["modes"]):
                continue
            if all(scopes) and not same_scope(*scopes):
                continue
            alias = not equals and legacy(key) == legacy(chords)
            if origin == "Built-in" and other.get("help") is not None:
                if equals or alias:
                    issues.append(("Shadows a built-in command" if equals else "May share a terminal keycode", other))
                elif prefix and len(key) < len(chords):
                    builtin_prefix.append(other)
            elif equals or prefix or alias:
                if alias:
                    label = "May share a terminal keycode"
                elif prefix:
                    label = "Overlapping key sequence"
                elif bool(scopes[0]) != bool(scopes[1]):
                    label = "Buffer mapping takes precedence"
                else:
                    label = "Same keys in an overlapping mode"
                issues.append((label, other))
        if builtin_prefix and not any(label == "Shadows a built-in command" for label, _ in issues):
            other = dict(builtin_prefix[0], desc=f"{len(builtin_prefix)} built-in sequences begin with these keys")
            issues.append(("Changes a built-in command prefix", other))
        return [{"message": label, "key": other["key"], "desc": other["desc"], "origin": other["origin"],
                 "context": other["context"], "file": other.get("file", ""), "modes": other["modes"]}
                for label, other in issues]


def public_row(row):
    return {key: value for key, value in row.items() if key not in ("digest", "start", "finish", "style", "chords")}
