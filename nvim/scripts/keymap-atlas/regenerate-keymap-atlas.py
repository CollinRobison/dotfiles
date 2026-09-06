#!/usr/bin/env python3
"""Build a source-driven, searchable Neovim field guide.

Run from the dotfiles root:
    python3 nvim/scripts/keymap-atlas/regenerate-keymap-atlas.py

The document is regenerated from the current Lua configuration. Built-in Vim
reference material is intentionally stable; every configured mapping is parsed
from source each run, so changed/new keys replace their prior entries instead of
being appended to a frozen PDF.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from atlas_guide_content import CORE_SECTIONS, INDEX_PROMPTS

NVIM = Path(__file__).resolve().parents[2]
LUA = NVIM / "lua"
DESKTOP = Path.home() / "Desktop"
HTML_OUT = DESKTOP / "Nvim-Dark-Complete-Atlas.html"
PDF_OUT = DESKTOP / "Nvim-Dark-Complete-Atlas.pdf"
REPO_PDF = NVIM / "docs" / "Nvim-Dark-Complete-Atlas.pdf"
CATEGORY_FILE = Path(__file__).with_name("atlas-categories.json")

MODE_NAMES = {"n": "Normal", "v": "Visual", "x": "Visual", "o": "Operator-pending", "i": "Insert", "s": "Select", "c": "Command", "t": "Terminal"}
CATEGORY = {
    "dap": "Debugging", "neotest": "Testing", "lsp": "LSP, Completion & Diagnostics",
    "markdown": "Markdown", "gitsigns": "Git", "telescope": "Find & Navigate",
    "nvimtree": "NvimTree", "lazygit": "Git", "todo-comments": "Find & Navigate",
    "bufferlines": "Buffers & Windows", "auto-session": "Workspaces & Sessions",
    "indent-blankline": "UI & Editing", "autopairs": "UI & Editing", "remap": "Personal Controls",
    "which-key": "Personal Controls", "alpha": "Dashboard",
}

# This is reference material, not a snapshot of a mutable plugin mapping.
ESSENTIALS = {
    "Move precisely, then act": [
        ("Normal", "h j k l", "Move left / down / up / right."),
        ("Normal", "w b e", "Next word start / previous word start / word end."),
        ("Normal", "0 ^ $", "Line start / first nonblank / line end."),
        ("Normal", "gg G", "First / last line of the file."),
        ("Normal", "f{char} ; ,", "Find on a line; repeat forward / backward."),
        ("Normal", "/text n N", "Search; next / previous result."),
        ("Normal", "Ctrl-o Ctrl-i", "Older / newer jump location."),
    ],
    "Edit with operators & text objects": [
        ("Normal", "d c y", "Delete / change / yank; pair with a motion or object."),
        ("Normal", "ciw daw yi\"", "Change inner word / delete a word / yank inside quotes."),
        ("Normal", "i( a( ip ap", "Inner / around parentheses; inner / around paragraph."),
        ("Normal", "dd cc yy", "Delete / change / yank a whole line."),
        ("Normal", "p P", "Paste after / before the cursor or line."),
        ("Normal", "u Ctrl-r .", "Undo / redo / repeat the last change."),
    ],
    "Files, windows & working memory": [
        ("Command", ":e {file} :w :q", "Open file / save / quit."),
        ("Normal", ":b {buffer}", "Switch buffer by name or number."),
        ("Normal", "Ctrl-w h j k l", "Move between split windows."),
        ("Normal", "za zc zo", "Toggle / close / open a fold."),
        ("Normal", "m{a} '{a}", "Set a mark / jump to its line."),
        ("Normal", "q{a} q @a @@", "Record macro / stop / run / repeat macro."),
    ],
    "Select, complete & inspect": [
        ("Visual", "v V Ctrl-v", "Character / line / block selection."),
        ("Normal", "]s [s z=", "Next misspelling / previous / suggestions."),
        ("Insert", "Ctrl-n Ctrl-p", "Built-in next / previous completion candidate."),
        ("Insert", "Ctrl-y Ctrl-e", "Accept / cancel built-in completion."),
        ("Normal", ":help {topic}", "Open built-in help; use Ctrl-] to follow tags."),
    ],
}

@dataclass(frozen=True)
class Mapping:
    mode: str
    key: str
    description: str
    category: str
    source: str
    context: str = "Global"


def balanced(text: str, start: int, opener: str = "{", closer: str = "}") -> tuple[str, int] | None:
    """Return one balanced Lua-ish block, respecting quoted strings."""
    depth = 0; quote = None; escaped = False
    for i in range(start, len(text)):
        char = text[i]
        if quote:
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == quote: quote = None
            continue
        if char in "\"'": quote = char; continue
        if char == opener: depth += 1
        elif char == closer:
            depth -= 1
            if depth == 0: return text[start:i + 1], i + 1
    return None


def split_top_level(block: str) -> list[str]:
    """Split a Lua table body into entries at top-level commas."""
    items, start, depth, quote, escaped = [], 0, 0, None, False
    for i, char in enumerate(block):
        if quote:
            if escaped: escaped = False
            elif char == "\\": escaped = True
            elif char == quote: quote = None
            continue
        if char in "\"'": quote = char
        elif char in "{(": depth += 1
        elif char in "})": depth -= 1
        elif char == "," and depth == 0:
            items.append(block[start:i]); start = i + 1
    items.append(block[start:])
    return items


def quoted_values(value: str) -> list[str]:
    return re.findall(r'"((?:\\.|[^"\\])*)"', value)


def display_key(key: str) -> str:
    key = key.replace("<leader>", "Space ").replace("<localleader>", "LocalSpace ")
    key = key.replace("<C-Space>", "Ctrl-Space").replace("<CR>", "Enter")
    key = key.replace("<Esc>", "Esc").replace("<Tab>", "Tab").replace("<S-Tab>", "Shift-Tab")
    key = re.sub(r"<C-([^>]+)>", r"Ctrl-\1", key)
    key = re.sub(r"<S-([^>]+)>", r"Shift-\1", key)
    return key


def best_effort_description(rhs: str) -> str:
    command = re.search(r'<cmd>\s*([^<]+)<CR>', rhs)
    if command:
        return "Run " + command.group(1).strip()
    target = re.search(r'(?:require\(["\']([^"\']+)["\']\)|([\w.]+))', rhs)
    if target:
        return "Use " + next(value for value in target.groups() if value)
    return "Custom callback (add a Lua desc to refine this explanation)"


def modes(value: str) -> list[str]:
    found = quoted_values(value)
    return [MODE_NAMES.get(mode, mode) for mode in found] or ["Normal"]


def file_context(path: Path) -> str:
    stem = path.stem
    if stem == "markdown": return "Markdown buffer"
    if stem == "lsp": return "LSP buffer (when attached)"
    if stem == "nvimtree": return "NvimTree"
    if stem == "alpha": return "Dashboard buffer"
    return "Global"


def category(path: Path) -> str:
    return CATEGORY.get(path.stem, "Other configured mappings")


def extract_table_entries(text: str, marker: str, path: Path) -> list[Mapping]:
    """Extract Lazy/which-key entries containing key plus desc from a table."""
    out: list[Mapping] = []
    cursor = 0
    while True:
        hit = text.find(marker, cursor)
        if hit < 0: break
        start = text.find("{", hit)
        found = balanced(text, start) if start >= 0 else None
        cursor = (found[1] if found else hit + len(marker))
        if not found: continue
        table = found[0][1:-1]
        for entry in split_top_level(table):
            entry = entry.strip()
            if not entry.startswith("{"): continue
            values = quoted_values(entry)
            description = re.search(r'desc\s*=\s*"([^"]+)"', entry)
            if not values: continue
            action = description.group(1) if description else best_effort_description(values[1] if len(values) > 1 else "")
            mode_match = re.search(r'mode\s*=\s*({[^}]+}|"[^"]+")', entry)
            context = file_context(path) if "buffer" in entry else "Global"
            for mode in modes(mode_match.group(1) if mode_match else '"n"'):
                out.append(Mapping(mode, display_key(values[0]), action, category(path), path.name, context))
    return out


def extract_keymap_calls(text: str, path: Path) -> list[Mapping]:
    """Extract vim.keymap.set calls, including callback mappings with desc."""
    out: list[Mapping] = []; marker = "vim.keymap.set("; cursor = 0
    while True:
        hit = text.find(marker, cursor)
        if hit < 0: break
        start = hit + len(marker) - 1
        found = balanced(text, start, "(", ")")
        cursor = found[1] if found else hit + len(marker)
        if not found: continue
        call = found[0][1:-1]
        desc = re.search(r'desc\s*=\s*"([^"]+)"', call)
        args = split_top_level(call)
        if len(args) < 2: continue
        key_values = quoted_values(args[1])
        if not key_values: continue
        action = desc.group(1) if desc else best_effort_description(args[2] if len(args) > 2 else "")
        context = file_context(path) if "buffer" in call else "Global"
        for mode in modes(args[0]):
            out.append(Mapping(mode, display_key(key_values[0]), action, category(path), path.name, context))
    return out


def extract_wrapper_maps(text: str, path: Path) -> list[Mapping]:
    """Extract local map(lhs, rhs, desc) calls used by DAP and Neotest."""
    out: list[Mapping] = []
    for hit in re.finditer(r'(?<!function\s)\bmap\(', text):
        found = balanced(text, hit.end() - 1, "(", ")")
        if not found: continue
        call = found[0][1:-1]
        args = split_top_level(call)
        if len(args) < 3: continue
        key_values = quoted_values(args[0]); desc_values = quoted_values(args[-1])
        if key_values and desc_values:
            out.append(Mapping("Normal", display_key(key_values[0]), desc_values[-1], category(path), path.name, "Global"))
    return out


def extract_special_mappings(text: str, path: Path) -> list[Mapping]:
    """Cover configured mappings expressed as data rather than a desc-bearing API call."""
    out: list[Mapping] = []
    if path.stem == "alpha":
        marker = "launcher_keys ="
        hit = text.find(marker)
        start = text.find("{", hit) if hit >= 0 else -1
        found = balanced(text, start) if start >= 0 else None
        if found:
            dashboard_actions = {
                "ene": "Start a new empty file", "Telescope find_files": "Find files", "Telescope keymaps": "Find keymaps",
                "Telescope project": "Switch projects", "Telescope oldfiles": "Open recent files", "Telescope live_grep": "Search project text",
                "LazyGit": "Open LazyGit", "NvimTreeToggle": "Toggle file explorer", "Lazy": "Open plugin manager",
                "qa": "Quit Neovim", "AutoSession search": "Find and restore a session",
            }
            for key, command in re.findall(r'(\w+)\s*=\s*"([^"]+)"', found[0]):
                action = command.removeprefix("<cmd>").removesuffix("<CR>")
                action = dashboard_actions.get(action, next((label for prefix, label in (("Telescope project", "Switch projects"), ("Telescope oldfiles", "Open recent files"), ("Telescope find_files", "Find files"), ("Telescope live_grep", "Search project text")) if action.startswith(prefix)), f"Run {action}"))
                out.append(Mapping("Normal", display_key(key), action, "Dashboard", path.name, "Dashboard buffer"))
    if path.stem == "markdown":
        enter = re.search(r'MkdnEnter\s*=\s*{\s*({[^}]+})\s*,\s*"(<CR>)"\s*}', text)
        if enter:
            for mode in modes(enter.group(1)):
                out.append(Mapping(mode, display_key(enter.group(2)), "Mkdnflow smart Enter", "Markdown", path.name, "Markdown buffer"))
    return out


def extract_mappings() -> list[Mapping]:
    entries: list[Mapping] = []
    for path in sorted(LUA.rglob("*.lua")):
        text = path.read_text(errors="replace")
        entries.extend(extract_table_entries(text, "keys =", path))
        entries.extend(extract_table_entries(text, "which_key.add(", path))
        entries.extend(extract_keymap_calls(text, path))
        entries.extend(extract_wrapper_maps(text, path))
        entries.extend(extract_special_mappings(text, path))
    # Prefer exact context/source entries, but avoid duplicate key-description rows.
    seen: set[tuple[str, str, str, str]] = set(); output=[]
    for entry in entries:
        key = (entry.mode, entry.key, entry.description, entry.context)
        if key not in seen:
            seen.add(key); output.append(entry)
    return sorted(output, key=lambda item: (item.category, item.context, item.key.lower(), item.key))


def mapping_identity(item: Mapping) -> str:
    return "|".join((item.source, item.mode, item.key, item.context))


def apply_saved_categories(entries: list[Mapping], interactive: bool) -> list[Mapping]:
    data = json.loads(CATEGORY_FILE.read_text()) if CATEGORY_FILE.exists() else {"mapping_categories": {}}
    saved: dict[str, str] = data.setdefault("mapping_categories", {})
    available = sorted(set(CATEGORY.values()))
    changed = False; output: list[Mapping] = []
    for item in entries:
        identity = mapping_identity(item)
        target = saved.get(identity, item.category)
        if target == "Other configured mappings":
            if interactive and sys.stdin.isatty():
                print(f"\nNew atlas mapping: {item.key} — {item.description} ({item.source})")
                print("Categories: " + ", ".join(available))
                answer = input("Category (or type a new name): ").strip()
                if answer:
                    target = answer; saved[identity] = target; changed = True
            else:
                target = "New / uncategorized configuration"
        output.append(Mapping(item.mode, item.key, item.description, target, item.source, item.context))
    if changed:
        CATEGORY_FILE.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
        print(f"Saved category choices: {CATEGORY_FILE}")
    return output


def extract_tools() -> list[tuple[str, str]]:
    """Inventory plugins plus configured language/debug/format/lint tools."""
    tools: set[tuple[str, str]] = set()
    for path in sorted(LUA.rglob("*.lua")):
        text = path.read_text(errors="replace")
        for plugin in re.findall(r'["\']([\w.-]+/[\w.-]+)["\']', text):
            tools.add((f"Plugin: {plugin}", path.name))
        for server in re.findall(r'vim\.lsp\.config\(\s*["\']([^"\']+)["\']', text):
            tools.add((f"LSP server: {server}", path.name))
        for executable in re.findall(r'(?:command|executable)\s*=\s*["\']([^"\']+)["\']', text):
            tools.add((f"Executable: {executable}", path.name))
        for executable in re.findall(r'executable\(\s*["\']([^"\']+)["\']', text):
            tools.add((f"Executable: {executable}", path.name))
        for adapter in re.findall(r'dap\.adapters\.([\w_-]+)', text):
            tools.add((f"DAP adapter: {adapter}", path.name))
        if path.stem == "markdown":
            for formatter in re.findall(r'formatters_by_ft\s*=\s*{([\s\S]*?)}\s*,', text):
                for name in quoted_values(formatter): tools.add((f"Formatter: {name}", path.name))
            for linter in re.findall(r'linters_by_ft\.\w+\s*=\s*{([^}]+)}', text):
                for name in quoted_values(linter): tools.add((f"Linter: {name}", path.name))
    return sorted(tools, key=lambda item: item[0].lower())


def describe_command(command: str) -> str:
    """Explain source-declared command entry points in reader-facing language."""
    lower = command.lower()
    exact = {
        "bdelete": "Close the current buffer without quitting Neovim.", "BufferLineCycleNext": "Select the next buffer in the buffer line.", "BufferLineCyclePrev": "Select the previous buffer in the buffer line.",
        "BufferLinePick": "Show letter labels so you can jump directly to an open buffer.", "ene": "Open a new empty buffer.", "IBLToggle": "Show or hide indentation guides.",
        "IBLToggleScope": "Show or hide the current indentation scope highlight.", "qa": "Quit all Neovim windows.", "TodoQuickFix": "Collect TODO-style comments in the quickfix list.",
        "TodoLocList": "Collect TODO-style comments in the current window’s location list.", "MkdnFollowLink": "Open the Markdown link under the cursor.", "MkdnNextLink": "Jump to the next Markdown link.",
        "MkdnPrevLink": "Jump to the previous Markdown link.", "MkdnTableFormat": "Align and format the Markdown table at the cursor.", "MkdnToggleToDo": "Toggle the Markdown task checkbox at the cursor.",
        "MkdnFoldSection": "Fold the Markdown section at the cursor.", "MkdnUnfoldSection": "Unfold the Markdown section at the cursor.",
    }
    if command in exact:
        return exact[command]
    known = {
        "masoninstalldebugadapters": "Install the debugger adapters configured for this Neovim setup.",
        "telescope": "Open a searchable picker; the following argument selects files, text, help, Git, or another source.",
        "nvimtreetoggle": "Open or close the file explorer.",
        "lazygit": "Open the terminal Git interface for the repository.",
        "autosession": "Save, search, or restore an editor workspace session.",
        "markview": "Toggle rendered Markdown, hybrid view, or a preview split.",
        "mkdn": "Use Mkdnflow to navigate Markdown links and edit tasks, tables, or headings.",
        "test": "Run the configured test target (nearest test, file, or suite).",
        "dap": "Control a debug session, breakpoints, stepping, and inspection.",
        "conform": "Inspect or invoke configured formatting behavior.",
        "lazy": "Open the plugin manager.",
    }
    for needle, description in known.items():
        if needle in lower:
            return description
    return "User-facing command declared by this configuration; run it after typing a colon in Normal mode."


def extract_commands() -> list[tuple[str, str, str]]:
    """Collect direct :command entry points declared in current Lua source."""
    commands: dict[str, tuple[str, str]] = {}
    for path in sorted(LUA.rglob("*.lua")):
        text = path.read_text(errors="replace")
        for name in re.findall(r'nvim_create_user_command\(\s*["\']([^"\']+)', text):
            commands[name] = (describe_command(name), path.name)
        for name in re.findall(r'<cmd>([A-Za-z][A-Za-z0-9]+)', text):
            commands.setdefault(name, (describe_command(name), path.name))
    return [(name, description, source) for name, (description, source) in sorted(commands.items(), key=lambda item: item[0].lower())]


def command_rows(items: list[tuple[str, str, str]]) -> str:
    return "".join(f"<tr><td><code>:{html.escape(name)}</code></td><td>{html.escape(description)}</td><td><code>{html.escape(source)}</code></td></tr>" for name, description, source in items)


def runtime_description(desc: str, rhs: str) -> str:
    """Turn runtime map metadata into a reader-facing action where possible."""
    if desc.startswith(":help "):
        return "Vim built-in; see " + desc
    commands = {
        ":bprevious": "Switch to previous buffer", ":bnext": "Switch to next buffer", ":bfirst": "Switch to first buffer", ":blast": "Switch to last buffer",
        ":tabprevious": "Switch to previous tab", ":tabnext": "Switch to next tab", ":tabfirst": "Switch to first tab", ":tablast": "Switch to last tab",
        ":rewind": "Jump to the first item in the argument list", ":previous": "Jump to the previous argument-list item", ":next": "Jump to the next argument-list item",
        ":bdelete": "Delete the current buffer", ":edit": "Open a file for editing", ":quit": "Quit the current window",
    }
    return commands.get(desc, desc or best_effort_description(rhs))


def runtime_audit() -> tuple[list[Mapping], str]:
    """Collect active user-facing runtime maps for the appendix and cross-check source."""
    with tempfile.TemporaryDirectory(prefix="nvim-atlas-") as temp:
        root = Path(temp); cfg = root / "config"; cfg.mkdir(); (cfg / "nvim").symlink_to(NVIM)
        output = root / "maps.json"; probe = root / "probe.md"; probe.write_text("# Atlas probe\n")
        lua = '''local modes={"n","v","x","o","i","s","c","t"}; local o={global={},markdown={},nvimtree={},lsp_clients=0}; local function add(target,buf) for _,m in ipairs(modes) do local maps=buf and vim.api.nvim_buf_get_keymap(buf,m) or vim.api.nvim_get_keymap(m); for _,k in ipairs(maps) do if k.desc and not k.lhs:match("<Plug>") then table.insert(target,{mode=m,lhs=k.lhs,desc=k.desc,rhs=k.rhs or ""}) end end end end; add(o.global,nil); vim.cmd("edit " .. vim.fn.fnameescape(os.getenv("ATLAS_MARKDOWN_PROBE"))); vim.bo.filetype="markdown"; vim.api.nvim_exec_autocmds("FileType",{buffer=0,modeline=false}); add(o.markdown,0); local ok=pcall(vim.cmd,"NvimTreeOpen"); if ok then for _,b in ipairs(vim.api.nvim_list_bufs()) do if vim.bo[b].filetype=="NvimTree" then add(o.nvimtree,b) end end end; o.lsp_clients=#vim.lsp.get_clients(); vim.fn.writefile({vim.json.encode(o)}, os.getenv("ATLAS_RUNTIME_JSON"))'''
        env = dict(**__import__("os").environ, XDG_CONFIG_HOME=str(cfg), ATLAS_RUNTIME_JSON=str(output), ATLAS_MARKDOWN_PROBE=str(probe))
        try:
            subprocess.run(["nvim", "--headless", "+lua " + lua, "+qa"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90, check=True)
            payload = json.loads(output.read_text())
            contexts = (("global", "Global"), ("markdown", "Markdown buffer"), ("nvimtree", "NvimTree"))
            entries: list[Mapping] = []
            for scope, context in contexts:
                for item in payload[scope]:
                    rhs = item.get("rhs", "")
                    description = runtime_description(str(item.get("desc", "")), rhs)
                    entries.append(Mapping(MODE_NAMES.get(str(item["mode"]), str(item["mode"])), display_key(item["lhs"]), description, "Runtime-discovered keymaps", f"runtime:{scope}", context))
            detail = f"Runtime cross-check: global {len(payload['global'])}, Markdown buffer {len(payload['markdown'])}, NvimTree buffer {len(payload['nvimtree'])}; LSP clients attached {payload['lsp_clients']}"
            return entries, detail
        except Exception as exc:
            return [], f"Runtime cross-check unavailable ({type(exc).__name__}); source inventory remains authoritative"


def keycaps(value: str) -> str:
    return " ".join(f"<kbd>{html.escape(part)}</kbd>" for part in value.split(" / "))


def mapping_rows(items: list[Mapping]) -> str:
    return "".join(f"<tr><td>{html.escape(item.mode)}</td><td>{keycaps(item.key)}</td><td>{html.escape(item.description)}</td><td>{html.escape(item.context)}</td></tr>" for item in items)


def describe_tool(tool: str) -> str:
    """Plain-English capability for the configured integration inventory."""
    lowered = tool.lower()
    known = {
        "telescope": "Search files, text, buffers, help, keymaps, and Git information.",
        "nvim-tree": "Browse files and reveal the current file in a tree.",
        "gitsigns": "Navigate, preview, stage, reset, and blame changed Git hunks.",
        "neotest": "Run tests, inspect output, and debug a test through DAP.",
        "nvim-dap": "Pause a program, step through execution, and inspect debugger state.",
        "markview": "Render Markdown while you edit it.",
        "mkdnflow": "Follow links, manage tasks, tables, headings, and Markdown navigation.",
        "lazygit": "Open a terminal Git interface for status, commits, branches, and logs.",
        "auto-session": "Save and restore working layouts and open buffers.",
        "image.nvim": "Display supported images inline in Neovim when the terminal graphics backend is available.",
        "bufferline": "Show open buffers as a navigable tab-like strip.",
        "nvim-autopairs": "Automatically insert and manage matching quotes, brackets, and parentheses while typing.",
        "lualine": "Show file, Git, diagnostic, mode, and status information in the statusline.",
        "indent-blankline": "Draw indentation guides and optionally highlight the current scope.",
        "nvim-web-devicons": "Provide file-type icons to the file explorer, bufferline, Telescope, and status UI.",
        "mini.icons": "Provide compact file-type icons to Neovim UI integrations.",
        "treesitter": "Use syntax-aware parsing for highlighting, text objects, indentation, and code structure.",
        "todo-comments": "Recognize TODO-style annotations and make them searchable through lists and Telescope.",
        "alpha-nvim": "Show a start dashboard with shortcuts for files, projects, sessions, Git, and plugins.",
        "which-key": "Display available keybinding continuations after a key prefix.",
        "mason": "Install and manage external language servers, formatters, linters, and debug adapters.",
    }
    for needle, description in known.items():
        if needle in lowered: return description
    if tool.startswith("LSP server:"): return "Adds language-aware diagnostics, navigation, completion, formatting, and refactors when attached."
    if tool.startswith("DAP adapter:"): return "Connects Neovim’s debugging controls to this language/runtime."
    if tool.startswith("Formatter:"): return "Rewrites source into the project’s configured formatting style."
    if tool.startswith("Linter:"): return "Checks source for style, correctness, or writing issues."
    if tool.startswith("Executable:"): return "External command used by a configured editor integration."
    return "Configured integration; use its matching mapping or command in this guide."


def tool_rows(items: list[tuple[str, str]]) -> str:
    return "".join(f"<tr><td><code>{html.escape(tool)}</code></td><td>{html.escape(describe_tool(tool))}</td><td><code>{html.escape(source)}</code></td></tr>" for tool, source in items)


def reference_rows(items: list[tuple[str, str, str]]) -> str:
    return "".join(f"<tr><td>{html.escape(mode)}</td><td>{keycaps(key)}</td><td>{html.escape(desc)}</td></tr>" for mode,key,desc in items)


def quick_card(number: str, title: str, detail: str) -> str:
    return f"<div class='quick'><span>{number}</span><div><b>{html.escape(title)}</b><p>{html.escape(detail)}</p></div></div>"


def page_header(title: str, eyebrow: str, count: int) -> str:
    title_class = " compact" if len(title) > 30 else ""
    return f"<header><div><p class='eyebrow'>{html.escape(eyebrow)}</p><h1 class='{title_class.strip()}'>{html.escape(title)}</h1></div><div class='meta'>Collin’s setup • Leader = Space<br><b>Last regenerated: {date.today().isoformat()}</b><br>{count} configured mappings</div></header><div class='rule'></div>"


def teaching_page(title: str, subtitle: str, columns: list[tuple[str, list[tuple[str, str]]]], note: str, highlights: list[Mapping], count: int) -> str:
    cards = "".join(f"<div class='teach-card'><h2>{html.escape(heading)}</h2><table><tbody>" + "".join(f"<tr><td>{keycaps(key)}</td><td>{html.escape(action)}</td></tr>" for key, action in rows) + "</tbody></table></div>" for heading, rows in columns)
    current = ""
    if highlights:
        current = "<div class='current'><b>Your current configuration</b><table><thead><tr><th>Key</th><th>Action</th><th>Context</th></tr></thead><tbody>" + "".join(f"<tr><td>{keycaps(row.key)}</td><td>{html.escape(row.description)}</td><td>{html.escape(row.context)}</td></tr>" for row in highlights[:6]) + "</tbody></table></div>"
    return f"<section>{page_header(title,'BUILT-IN VIM LANGUAGE + YOUR CONFIGURATION',count)}<div class='teach-grid'>{cards}</div><div class='callout'>{html.escape(note)}</div>{current}</section>"


def build_html(entries: list[Mapping], tools: list[tuple[str, str]], commands: list[tuple[str, str, str]], runtime_count: int, runtime_note: str) -> str:
    grouped: dict[str, list[Mapping]] = defaultdict(list)
    for entry in entries: grouped[entry.category].append(entry)
    quick = "".join([
        quick_card("1", "Find", "Space f f opens files; Space f g searches project text."),
        quick_card("2", "Move", "w / b move by word; / then n searches; gg / G jump in a file."),
        quick_card("3", "Change", "Use operator + object: ciw changes a word, daw deletes a word."),
        quick_card("4", "Check", "Space l f formats an LSP buffer; :w saves; Space l g opens LazyGit."),
    ])
    cover_header = page_header("Neovim\nComplete\nField Guide", "BUILT-INS + YOUR VERIFIED CONFIGURATION", len(entries))
    pages = [f"""<section class='cover'>{cover_header}<p class='lede'>A practical, searchable map of the Vim language and the mappings declared in this checkout. Every custom row below is rebuilt from the current Lua configuration—new or changed keys replace the old documentation.</p><div class='quick-grid'>{quick}</div><div class='callout'><b>How to read this:</b> <em>Space f f</em> means press Space, then f, then f. Context labels identify keys that only appear in Markdown, NvimTree, dashboard, or LSP-attached buffers.</div><p class='audit'>{html.escape(runtime_note)}: {runtime_count} described runtime mappings observed. The source inventory is the published command truth; runtime data is used as a cross-check.</p></section>"""]
    core_categories = [
        ["Personal Controls"], ["UI & Editing"], ["Find & Navigate"], ["Buffers & Windows", "Workspaces & Sessions"],
        ["Git", "LSP, Completion & Diagnostics"], ["Markdown"], ["UI & Editing"], ["Dashboard", "Workspaces & Sessions", "Personal Controls"],
        ["Testing", "Debugging", "LSP, Completion & Diagnostics"],
    ]
    for index, (title, subtitle, columns, note) in enumerate(CORE_SECTIONS):
        highlights = [row for name in core_categories[index] for row in grouped.get(name, [])]
        pages.append(teaching_page(title, subtitle, columns, note, highlights, len(entries)))
    index_cards = "".join(f"<div class='index-card'><b>{html.escape(title)}</b><p>{html.escape(words)}</p></div>" for title, words in INDEX_PROMPTS)
    pages.append(f"<section>{page_header('Ctrl+F index','FIND THE COMMAND BY WHAT YOU WANT TO DO',len(entries))}<p class='lede'>Search this PDF for an exact key string or an ordinary word. The guide repeats literal keys in the teaching sections and keeps a complete generated appendix after them.</p><div class='index-grid'>{index_cards}</div><div class='callout'><b>Discover anything else:</b> Space f k opens searchable active keymaps. <code>:help keyword</code> explains built-ins; <code>:map</code>, <code>:nmap</code>, and <code>:imap</code> inspect mappings directly; <code>:checkhealth</code> diagnoses the setup.</div></section>")
    tool_parts = (len(tools) + 11) // 12
    tool_chunk_size = (len(tools) + tool_parts - 1) // tool_parts
    for start in range(0, len(tools), tool_chunk_size):
        chunk = tools[start:start + tool_chunk_size]
        suffix = "" if start == 0 else f" · part {start // tool_chunk_size + 1} of {tool_parts}"
        pages.append(f"<section>{page_header('Configured Tooling' + suffix,'COMPLETE GENERATED APPENDIX',len(entries))}<p class='section-note'>Declared integrations are listed even when they do not expose a direct user mapping.</p><table><thead><tr><th>Tool / plugin</th><th>What it enables</th><th>Configuration source</th></tr></thead><tbody>{tool_rows(chunk)}</tbody></table></section>")
    command_parts = max(1, (len(commands) + 11) // 12)
    command_chunk_size = max(1, (len(commands) + command_parts - 1) // command_parts)
    for start in range(0, len(commands), command_chunk_size):
        chunk = commands[start:start + command_chunk_size]
        suffix = "" if start == 0 else f" · part {start // command_chunk_size + 1} of {command_parts}"
        pages.append(f"<section>{page_header('Commands & automatic behavior' + suffix,'COMPLETE GENERATED APPENDIX',len(entries))}<p class='section-note'>Type these after <code>:</code> in Normal mode. The tooling inventory explains capabilities that happen automatically or do not have a direct keybinding.</p><table><thead><tr><th>Command</th><th>What it does</th><th>Configuration source</th></tr></thead><tbody>{command_rows(chunk)}</tbody></table></section>")
    for title in sorted(grouped):
        rows = grouped[title]
        sources = html.escape(', '.join(sorted({row.source for row in rows})))
        # Balance continuation pages while keeping at most 15 rows per page;
        # a category of 16 maps becomes two useful 8-row pages, not 15 + 1.
        parts = (len(rows) + 14) // 15
        chunk_size = (len(rows) + parts - 1) // parts
        for start in range(0, len(rows), chunk_size):
            chunk = rows[start:start + chunk_size]
            suffix = "" if start == 0 else f" · part {start // chunk_size + 1} of {parts}"
            pages.append(f"<section>{page_header(title + suffix,'COMPLETE GENERATED APPENDIX',len(entries))}<p class='section-note'>Extracted from <code>{sources}</code>.</p><table><thead><tr><th>Mode</th><th>Key</th><th>Action</th><th>Context</th></tr></thead><tbody>{mapping_rows(chunk)}</tbody></table></section>")
    return f"""<!doctype html><html><head><meta charset='utf-8'><title>Neovim Complete Field Guide</title><style>
@page{{size:letter landscape;margin:.42in;background:#090f17}}*{{box-sizing:border-box}}body{{margin:0;background:#090f17;color:#e7edf5;font:11pt/1.3 Arial,sans-serif}}section{{min-height:7.4in;position:relative;page-break-after:always;padding-bottom:.28in}}header{{display:flex;justify-content:space-between;align-items:flex-start}}.eyebrow{{color:#46e3d8;font-size:9pt;font-weight:bold;letter-spacing:1.8px;margin:0 0 5px}}h1{{white-space:pre-line;color:#f5f8fc;font-size:31pt;line-height:.97;margin:0}}h1.compact{{font-size:24pt;line-height:1.05}}.meta{{color:#b7c8d6;text-align:right;font-size:9pt;line-height:1.55}}.meta b{{color:#d5f5f3}}.rule{{height:3px;background:#35d4d1;margin:16px 0}}.lede{{font-size:14pt;max-width:8.5in;color:#d5e1ed;margin:0 0 17px}}.quick-grid{{display:grid;grid-template-columns:1fr 1fr;gap:12px}}.teach-grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}}.teach-card{{background:#102331;border:1px solid #285e76;border-radius:8px;padding:9px}}.teach-card h2{{font-size:11pt;margin:0 0 6px;color:#65e6dc}}.teach-card table{{font-size:8.5pt}}.teach-card td{{padding:5px}}.teach-card td:first-child{{width:45%;min-width:140px;padding-right:9px}}.current{{margin-top:11px}}.current b{{color:#65e6dc}}.current table{{font-size:8.5pt;margin-top:5px}}.index-grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}}.index-card{{background:#102331;border:1px solid #285e76;border-radius:8px;padding:13px;min-height:86px}}.index-card b{{color:#65e6dc;font-size:12pt}}.index-card p{{color:#c4d1dd;margin:6px 0 0}}.quick{{display:flex;gap:12px;background:#102331;border:1px solid #285e76;border-radius:8px;padding:13px;min-height:92px}}.quick span{{color:#49ddd6;font-size:25pt;font-weight:bold;line-height:1}}.quick b{{color:#eaf5ff;font-size:13pt}}.quick p{{margin:4px 0 0;color:#c4d1dd}}.callout{{margin-top:15px;padding:13px;background:#123d43;border-left:5px solid #20d5ae;color:#d8f6ef}}.audit{{margin:10px 0 0;color:#aabccc;font-size:8.5pt}}h2{{color:#55e3d7;letter-spacing:1px}}.section-note{{color:#b9cad8;margin:0 0 10px}}code{{color:#c9f3f4}}table{{width:100%;border-collapse:collapse;font-size:9.3pt}}th{{background:#14394d;color:#dffaff;text-align:left;padding:7px}}td{{border:1px solid #28556a;padding:7px;vertical-align:top;overflow-wrap:anywhere;word-break:normal}}tr:nth-child(even){{background:#0d1d2b}}kbd{{display:inline-block;line-height:1.2;margin:0 4px 0 0;vertical-align:middle;background:#183c50;border:1px solid #4183a1;border-radius:4px;color:#c9f7fb;font:bold 9pt monospace;padding:3px 5px;white-space:nowrap}}footer{{position:fixed;bottom:.12in;right:.42in;color:#aabccc;font-size:8pt}}</style></head><body>{''.join(pages)}<footer>Neovim Field Guide • Ctrl-F searchable • source-driven regeneration</footer></body></html>"""


def render(html_path: Path, pdf_path: Path) -> None:
    weasy = shutil.which("weasyprint")
    command = [weasy, str(html_path), str(pdf_path)] if weasy else None
    if command is None:
        uv = shutil.which("uv")
        if not uv: raise RuntimeError("Install weasyprint or uv to render the atlas.")
        command = [uv, "run", "--with", "weasyprint", "weasyprint", str(html_path), str(pdf_path)]
    subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-runtime-audit", action="store_true", help="Do not launch Neovim for the runtime cross-check.")
    parser.add_argument("--non-interactive", action="store_true", help="Put unmapped categories in the temporary appendix instead of prompting.")
    parser.add_argument("--desktop-artifacts", action="store_true", help="Also write HTML and PDF preview artifacts to ~/Desktop.")
    args = parser.parse_args()
    source_entries = extract_mappings()
    runtime_entries, runtime_note = ([], "Runtime audit skipped") if args.skip_runtime_audit else runtime_audit()
    # Source rows provide curated categories; runtime-only rows make every active typed key discoverable.
    source_keys = {(item.mode, item.key, item.context) for item in source_entries}
    source_entries.extend(item for item in runtime_entries if (item.mode, item.key, item.context) not in source_keys)
    entries = apply_saved_categories(source_entries, interactive=not args.non_interactive)
    tools = extract_tools()
    commands = extract_commands()
    if not entries: raise RuntimeError(f"No mappings found under {LUA}")
    if not tools: raise RuntimeError(f"No configured tools found under {LUA}")
    if not commands: raise RuntimeError(f"No user-facing commands found under {LUA}")
    REPO_PDF.parent.mkdir(parents=True, exist_ok=True)
    document = build_html(entries, tools, commands, len(runtime_entries), runtime_note)
    desktop_lines: list[str] = []
    if args.desktop_artifacts:
        DESKTOP.mkdir(parents=True, exist_ok=True)
        HTML_OUT.write_text(document, encoding="utf-8")
        render(HTML_OUT, PDF_OUT)
        shutil.copy2(PDF_OUT, REPO_PDF)
        desktop_lines = [f"HTML: {HTML_OUT}", f"Desktop PDF: {PDF_OUT}"]
    else:
        with tempfile.TemporaryDirectory(prefix="nvim-atlas-render-") as temp:
            temp_root = Path(temp); temp_html = temp_root / "atlas.html"; temp_pdf = temp_root / "atlas.pdf"
            temp_html.write_text(document, encoding="utf-8")
            render(temp_html, temp_pdf)
            shutil.copy2(temp_pdf, REPO_PDF)
    print("\n".join([f"Mappings: {len(entries)} (source {len(source_keys)}, runtime-only {len(entries) - len(source_keys)})", f"Tooling entries: {len(tools)}", f"Commands: {len(commands)}", f"{runtime_note}: {len(runtime_entries)} active runtime mappings", *desktop_lines, f"Repository PDF: {REPO_PDF}"]))
    return 0

if __name__ == "__main__": raise SystemExit(main())
