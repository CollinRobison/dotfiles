#!/usr/bin/env python3
"""Build a source-driven, searchable Neovim field guide.

Run from the dotfiles root:
    python3 nvim/scripts/regenerate-keymap-atlas.py

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

NVIM = Path(__file__).resolve().parents[1]
LUA = NVIM / "lua"
DESKTOP = Path.home() / "Desktop"
HTML_OUT = DESKTOP / "Nvim-Dark-Complete-Atlas.html"
PDF_OUT = DESKTOP / "Nvim-Dark-Complete-Atlas.pdf"
REPO_PDF = NVIM / "docs" / "Nvim-Dark-Complete-Atlas.pdf"

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
            if not values or not description: continue
            mode_match = re.search(r'mode\s*=\s*({[^}]+}|"[^"]+")', entry)
            context = file_context(path) if "buffer" in entry else "Global"
            for mode in modes(mode_match.group(1) if mode_match else '"n"'):
                out.append(Mapping(mode, display_key(values[0]), description.group(1), category(path), path.name, context))
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
        if not desc: continue
        args = split_top_level(call)
        if len(args) < 2: continue
        key_values = quoted_values(args[1])
        if not key_values: continue
        context = file_context(path) if "buffer" in call else "Global"
        for mode in modes(args[0]):
            out.append(Mapping(mode, display_key(key_values[0]), desc.group(1), category(path), path.name, context))
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
            for key, command in re.findall(r'(\w+)\s*=\s*"([^"]+)"', found[0]):
                action = command.removeprefix("<cmd>").removesuffix("<CR>")
                out.append(Mapping("Normal", display_key(key), f"Dashboard: {action}", "Dashboard", path.name, "Dashboard buffer"))
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


def runtime_audit() -> tuple[int, str]:
    """Cross-check global and special-buffer maps; source remains documentation truth."""
    with tempfile.TemporaryDirectory(prefix="nvim-atlas-") as temp:
        root = Path(temp); cfg = root / "config"; cfg.mkdir(); (cfg / "nvim").symlink_to(NVIM)
        output = root / "maps.json"; probe = root / "probe.md"; probe.write_text("# Atlas probe\n")
        lua = '''local modes={"n","v","x","o","i","s","c","t"}; local o={global=0,markdown=0,nvimtree=0,lsp_clients=0}; local function count(buf) local n=0; for _,m in ipairs(modes) do for _,k in ipairs(vim.api.nvim_buf_get_keymap(buf,m)) do if k.desc and not k.lhs:match("<Plug>") then n=n+1 end end end; return n end; for _,m in ipairs(modes) do for _,k in ipairs(vim.api.nvim_get_keymap(m)) do if k.desc and not k.lhs:match("<Plug>") then o.global=o.global+1 end end end; vim.cmd("edit " .. vim.fn.fnameescape(os.getenv("ATLAS_MARKDOWN_PROBE"))); vim.bo.filetype="markdown"; vim.api.nvim_exec_autocmds("FileType",{buffer=0,modeline=false}); o.markdown=count(0); local ok=pcall(vim.cmd,"NvimTreeOpen"); if ok then for _,b in ipairs(vim.api.nvim_list_bufs()) do if vim.bo[b].filetype=="NvimTree" then o.nvimtree=count(b) end end end; o.lsp_clients=#vim.lsp.get_clients(); vim.fn.writefile({vim.json.encode(o)}, os.getenv("ATLAS_RUNTIME_JSON"))'''
        env = dict(**__import__("os").environ, XDG_CONFIG_HOME=str(cfg), ATLAS_RUNTIME_JSON=str(output), ATLAS_MARKDOWN_PROBE=str(probe))
        try:
            subprocess.run(["nvim", "--headless", "+lua " + lua, "+qa"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90, check=True)
            counts = json.loads(output.read_text())
            total = sum(counts[key] for key in ("global", "markdown", "nvimtree"))
            detail = f"Runtime cross-check: global {counts['global']}, Markdown buffer {counts['markdown']}, NvimTree buffer {counts['nvimtree']}; LSP clients attached {counts['lsp_clients']}"
            return total, detail
        except Exception as exc:
            return 0, f"Runtime cross-check unavailable ({type(exc).__name__}); source inventory remains authoritative"


def keycaps(value: str) -> str:
    return " ".join(f"<kbd>{html.escape(part)}</kbd>" for part in value.split(" / "))


def mapping_rows(items: list[Mapping]) -> str:
    return "".join(f"<tr><td>{html.escape(item.mode)}</td><td>{keycaps(item.key)}</td><td>{html.escape(item.description)}</td><td>{html.escape(item.context)}</td></tr>" for item in items)


def tool_rows(items: list[tuple[str, str]]) -> str:
    return "".join(f"<tr><td><code>{html.escape(tool)}</code></td><td>Configured integration</td><td><code>{html.escape(source)}</code></td></tr>" for tool, source in items)


def reference_rows(items: list[tuple[str, str, str]]) -> str:
    return "".join(f"<tr><td>{html.escape(mode)}</td><td>{keycaps(key)}</td><td>{html.escape(desc)}</td></tr>" for mode,key,desc in items)


def quick_card(number: str, title: str, detail: str) -> str:
    return f"<div class='quick'><span>{number}</span><div><b>{html.escape(title)}</b><p>{html.escape(detail)}</p></div></div>"


def page_header(title: str, eyebrow: str, count: int) -> str:
    title_class = " compact" if len(title) > 30 else ""
    return f"<header><div><p class='eyebrow'>{html.escape(eyebrow)}</p><h1 class='{title_class.strip()}'>{html.escape(title)}</h1></div><div class='meta'>Collin’s setup • Leader = Space<br><b>Last regenerated: {date.today().isoformat()}</b><br>{count} configured mappings</div></header><div class='rule'></div>"


def build_html(entries: list[Mapping], tools: list[tuple[str, str]], runtime_count: int, runtime_note: str) -> str:
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
    for title, rows in ESSENTIALS.items():
        pages.append(f"<section>{page_header(title,'BUILT-IN VIM LANGUAGE',len(entries))}<table><thead><tr><th>Mode</th><th>Key</th><th>Definition / action</th></tr></thead><tbody>{reference_rows(rows)}</tbody></table></section>")
    tool_parts = (len(tools) + 17) // 18
    tool_chunk_size = (len(tools) + tool_parts - 1) // tool_parts
    for start in range(0, len(tools), tool_chunk_size):
        chunk = tools[start:start + tool_chunk_size]
        suffix = "" if start == 0 else f" · part {start // tool_chunk_size + 1} of {tool_parts}"
        pages.append(f"<section>{page_header('Configured Tooling' + suffix,'YOUR CURRENT CONFIGURATION',len(entries))}<p class='section-note'>Declared integrations are listed even when they do not expose a direct user mapping.</p><table><thead><tr><th>Tool / plugin</th><th>Status</th><th>Configuration source</th></tr></thead><tbody>{tool_rows(chunk)}</tbody></table></section>")
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
            pages.append(f"<section>{page_header(title + suffix,'YOUR CURRENT CONFIGURATION',len(entries))}<p class='section-note'>Extracted from <code>{sources}</code>.</p><table><thead><tr><th>Mode</th><th>Key</th><th>Action</th><th>Context</th></tr></thead><tbody>{mapping_rows(chunk)}</tbody></table></section>")
    return f"""<!doctype html><html><head><meta charset='utf-8'><title>Neovim Complete Field Guide</title><style>
@page{{size:letter landscape;margin:.42in;background:#090f17}}*{{box-sizing:border-box}}body{{margin:0;background:#090f17;color:#e7edf5;font:11pt/1.3 Arial,sans-serif}}section{{min-height:7.4in;position:relative;page-break-after:always;padding-bottom:.28in}}header{{display:flex;justify-content:space-between;align-items:flex-start}}.eyebrow{{color:#46e3d8;font-size:9pt;font-weight:bold;letter-spacing:1.8px;margin:0 0 5px}}h1{{white-space:pre-line;color:#f5f8fc;font-size:31pt;line-height:.97;margin:0}}h1.compact{{font-size:24pt;line-height:1.05}}.meta{{color:#b7c8d6;text-align:right;font-size:9pt;line-height:1.55}}.meta b{{color:#d5f5f3}}.rule{{height:3px;background:#35d4d1;margin:16px 0}}.lede{{font-size:14pt;max-width:8.5in;color:#d5e1ed;margin:0 0 17px}}.quick-grid{{display:grid;grid-template-columns:1fr 1fr;gap:12px}}.quick{{display:flex;gap:12px;background:#102331;border:1px solid #285e76;border-radius:8px;padding:13px;min-height:92px}}.quick span{{color:#49ddd6;font-size:25pt;font-weight:bold;line-height:1}}.quick b{{color:#eaf5ff;font-size:13pt}}.quick p{{margin:4px 0 0;color:#c4d1dd}}.callout{{margin-top:15px;padding:13px;background:#123d43;border-left:5px solid #20d5ae;color:#d8f6ef}}.audit{{position:absolute;bottom:0;color:#aabccc;font-size:8.5pt}}h2{{color:#55e3d7;letter-spacing:1px}}.section-note{{color:#b9cad8;margin:0 0 10px}}code{{color:#c9f3f4}}table{{width:100%;border-collapse:collapse;font-size:9.3pt}}th{{background:#14394d;color:#dffaff;text-align:left;padding:7px}}td{{border:1px solid #28556a;padding:7px;vertical-align:top}}tr:nth-child(even){{background:#0d1d2b}}kbd{{background:#183c50;border:1px solid #4183a1;border-radius:4px;color:#c9f7fb;font:bold 9pt monospace;padding:3px 5px;white-space:nowrap}}footer{{position:fixed;bottom:.12in;right:.42in;color:#aabccc;font-size:8pt}}</style></head><body>{''.join(pages)}<footer>Neovim Field Guide • Ctrl-F searchable • source-driven regeneration</footer></body></html>"""


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
    args = parser.parse_args()
    entries = extract_mappings()
    tools = extract_tools()
    if not entries: raise RuntimeError(f"No described mappings found under {LUA}")
    if not tools: raise RuntimeError(f"No configured tools found under {LUA}")
    runtime_count, runtime_note = (0, "Runtime audit skipped") if args.skip_runtime_audit else runtime_audit()
    DESKTOP.mkdir(parents=True, exist_ok=True); REPO_PDF.parent.mkdir(parents=True, exist_ok=True)
    HTML_OUT.write_text(build_html(entries, tools, runtime_count, runtime_note), encoding="utf-8")
    render(HTML_OUT, PDF_OUT); shutil.copy2(PDF_OUT, REPO_PDF)
    print(f"Mappings: {len(entries)}\nTooling entries: {len(tools)}\n{runtime_note}: {runtime_count}\nHTML: {HTML_OUT}\nPDF: {PDF_OUT}\nRepository PDF: {REPO_PDF}")
    return 0

if __name__ == "__main__": raise SystemExit(main())
