#!/usr/bin/env python3
"""Build a searchable HTML/PDF keymap atlas from this Neovim config.

Run from any directory:
  python3 nvim/scripts/regenerate-keymap-atlas.py

The script reads the checked-out Lua configuration (rather than a user's live
config), writes Desktop previews, and copies the PDF into nvim/docs/.
"""
from __future__ import annotations

import html
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

NVIM = Path(__file__).resolve().parents[1]
REPO = NVIM.parent
DESKTOP = Path.home() / "Desktop"
HTML_OUT = DESKTOP / "Nvim-Dark-Complete-Atlas.html"
PDF_OUT = DESKTOP / "Nvim-Dark-Complete-Atlas.pdf"
REPO_PDF = NVIM / "docs" / "Nvim-Dark-Complete-Atlas.pdf"

# Core Vim motions are intentional fixed reference material; config-specific
# mappings are extracted below from the current checkout.
ESSENTIALS = [
    ("Normal", "h j k l", "Move left / down / up / right"),
    ("Normal", "w b e", "Next word / previous word / end of word"),
    ("Normal", "0 ^ $", "Line start / first nonblank / line end"),
    ("Normal", "gg G", "First line / last line"),
    ("Normal", "f{char} ; ,", "Find character / repeat forward / repeat backward"),
    ("Normal", "d c y", "Delete / change / yank; combine with a motion or text object"),
    ("Normal", "ciw daw yi\"", "Change inner word / delete a word / yank inside quotes"),
    ("Visual", "v V Ctrl-v", "Character / line / block selection"),
    ("Normal", "u Ctrl-r", "Undo / redo"),
    ("Normal", "/ ? n N", "Search forward/backward; next/previous result"),
    ("Command", ":s/old/new/g", "Substitute in the current line; add % for file-wide"),
    ("Normal", ":w :q :wq", "Write / quit / write and quit"),
    ("Normal", ":e {file} :b {buf}", "Edit file / switch buffer"),
    ("Normal", "Ctrl-w h j k l", "Move between split windows"),
    ("Normal", "za zc zo", "Toggle / close / open fold"),
    ("Normal", "m{a} '{a}", "Set mark / jump to mark line"),
    ("Normal", "q{a} q @a @@", "Record macro / stop / run / repeat"),
    ("Normal", "]s [s z=", "Next misspelling / previous / suggestions"),
    ("Insert", "Ctrl-n Ctrl-p", "Built-in next / previous completion candidate"),
    ("Insert", "Ctrl-y Ctrl-e", "Accept / cancel built-in completion"),
]

# Exact known plugin mappings that should remain prominent even if source
# formatting changes enough to defeat the lightweight extractor.
FOCUS = [
    ("Normal", "Space f f", "Find files", "Telescope"),
    ("Normal", "Space f g", "Find text (live grep)", "Telescope"),
    ("Normal", "Space n t", "Toggle NvimTree", "NvimTree"),
    ("Normal, Markdown buffer", "Space m p", "Toggle Markdown preview", "Markview"),
    ("Normal", "Space g c", "Search Git commits", "Telescope"),
    ("Normal", "Space d b", "Toggle breakpoint", "nvim-dap"),
    ("Normal", "Space d B", "Set conditional breakpoint", "nvim-dap"),
    ("Normal", "Space d c", "Continue / start debugger", "nvim-dap"),
    ("Normal", "Space d p", "Pause debug session", "nvim-dap"),
    ("Normal", "Space d i / d o / d O", "Step into / over / out", "nvim-dap"),
    ("Normal", "Space d r / d q", "Restart / terminate debug session", "nvim-dap"),
    ("Normal", "Space d u / d v", "Toggle DAP UI / virtual text", "nvim-dap"),
    ("Normal", "Space d e", "Evaluate expression", "nvim-dap"),
    ("Normal", "Space t n", "Run nearest test", "Neotest"),
    ("Normal", "Space t f", "Run tests in current file", "Neotest"),
    ("Normal", "Space t a", "Run test suite", "Neotest"),
    ("Normal", "Space t d", "Debug nearest test through DAP", "Neotest"),
    ("Normal", "Space t s / t o / t x", "Toggle summary / show output / stop test", "Neotest"),
    ("Normal", "Space t v / t V / t A", "vim-test fallback: nearest / file / suite", "vim-test"),
    ("Normal, LSP buffer", "Space l c", "Toggle automatic LSP completion", "LSP"),
    ("Insert, LSP buffer", "Ctrl-Space", "Trigger LSP completion manually", "LSP"),
    ("Normal, LSP buffer", "Space l f", "Format buffer", "LSP"),
    ("Normal", "[ d / ] d", "Previous / next diagnostic", "LSP diagnostics"),
    ("Normal", "Space l d", "Show diagnostic in a floating window", "LSP diagnostics"),
]

def key_display(key: str) -> str:
    key = key.replace("<leader>", "Space ").replace("<C-Space>", "Ctrl-Space")
    key = key.replace("<CR>", "Enter").replace("<S-", "Shift-")
    return re.sub(r"<([^>]+)>", r"\1", key)

def extract_maps() -> list[tuple[str, str, str, str]]:
    rows: list[tuple[str, str, str, str]] = []
    for path in sorted((NVIM / "lua").rglob("*.lua")):
        text = path.read_text(errors="replace")
        context = path.stem
        # `keys = { { "<leader>ff", ..., desc = "Find files" } }` plugin maps.
        for m in re.finditer(r'\{\s*"([^"]+)"\s*,[\s\S]{0,240}?desc\s*=\s*"([^"]+)"', text):
            key, desc = m.groups()
            rows.append(("Normal", key_display(key), desc, context))
        # Explicit simple map calls.
        for m in re.finditer(r'(?:vim\.keymap\.set|map)\(\s*"([nvisxot])"\s*,\s*"([^"]+)"[\s\S]{0,180}?"([^"]+)"\s*\)', text):
            mode, key, desc = m.groups()
            rows.append(({"n":"Normal","v":"Visual","i":"Insert","s":"Select","x":"Visual","o":"Operator-pending","t":"Terminal"}.get(mode, mode), key_display(key), desc, context))
    # Deduplicate while retaining source order.
    seen=set(); out=[]
    for row in rows:
        sig=row[:3]
        if sig not in seen:
            seen.add(sig); out.append(row)
    return out

def table(rows: list[tuple[str, str, str, str]], title: str) -> str:
    body=''.join(f"<tr><td>{html.escape(mode)}</td><td><kbd>{html.escape(key)}</kbd></td><td>{html.escape(desc)}</td><td>{html.escape(src)}</td></tr>" for mode,key,desc,src in rows)
    return f"<section><h2>{html.escape(title)}</h2><table><thead><tr><th>Mode / context</th><th>Key</th><th>Action</th><th>Source</th></tr></thead><tbody>{body}</tbody></table></section>"

def build_html(rows: list[tuple[str,str,str,str]]) -> str:
    essentials=[(*r,"Built-in") for r in ESSENTIALS]
    # Keep the mandatory focus rows first; source extraction follows.
    all_custom=FOCUS + rows
    flow=''.join(f'<div class="step"><b>{a}</b><span>{b}</span></div>' for a,b in [("Move","motions: w, b, f, /"),("Select","v, V, Ctrl-v or text objects"),("Act","d, c, y, >, ="),("Repeat / Undo",". repeats; u undoes; Ctrl-r redoes")])
    generated=date.today().isoformat()
    return f'''<!doctype html><html><head><meta charset="utf-8"><title>Neovim Dark Complete Atlas</title>
<style>
@page {{ size: Letter; margin: .45in; }} *{{box-sizing:border-box}} body{{font-family:Arial,sans-serif;background:#07111f;color:#e6f0ff;line-height:1.35}} h1{{font-size:30px;color:#67e8f9;margin:0}} h2{{color:#5eead4;border-bottom:1px solid #1f5265;padding-bottom:5px;margin-top:26px}} .sub{{color:#9fb4c9}} .callout{{background:#102238;border-left:4px solid #38bdf8;padding:12px;margin:15px 0}} .flow{{display:flex;gap:8px;flex-wrap:wrap}} .step{{background:#0e2b42;border:1px solid #236078;border-radius:6px;padding:9px;min-width:130px}} .step b{{color:#a5f3fc;display:block}} table{{width:100%;border-collapse:collapse;font-size:9.3pt;margin:10px 0 20px}} th{{background:#11344d;color:#d9fbff;text-align:left}} td,th{{border:1px solid #245269;padding:6px;vertical-align:top}} tr:nth-child(even){{background:#0b1b2b}} kbd{{background:#b9f4ff;color:#06131c;border:1px solid #4cc8db;border-radius:4px;padding:2px 5px;font-family:monospace;font-weight:bold;white-space:nowrap}} code{{color:#a7f3d0}} footer{{color:#9fb4c9;font-size:8pt;margin-top:20px}} .pagebreak{{break-before:page}}</style></head><body>
<h1>Neovim Dark Complete Atlas</h1><p class="sub">Generated from <code>{html.escape(str(NVIM))}</code> on {generated}. Leader key is shown as <kbd>Space</kbd>. Search this PDF/HTML with Ctrl-F.</p>
<div class="callout"><b>Context matters.</b> “LSP buffer” maps exist only after a compatible language server attaches; Markdown/NvimTree maps require those buffers/plugins. Debug keys require configured adapters (debugpy, js-debug-adapter, delve, codelldb, or netcoredbg).</div>
<h2>Beginner flow</h2><div class="flow">{flow}</div>
{table(essentials,'Vim / Neovim Essentials')}
<div class="pagebreak"></div>{table(FOCUS,'Debugging, Testing, LSP Completion, and Diagnostics')}
<div class="pagebreak"></div>{table(rows,'Current Custom Mapping Inventory (source extracted)')}
<section><h2>Test and Debug Management</h2><p><b>Tests:</b> Neotest supplies nearest/file/suite execution, summary, output, stop, and a DAP strategy. It configures Python, Go, Rust, Vitest, Jest, CTest, .NET, and a vim-test fallback. <b>Debug:</b> nvim-dap auto-opens DAP UI on initialization and closes it when a session ends; breakpoints, stepping, evaluation, and virtual text are mapped above.</p><p><b>Completion:</b> <kbd>Space l c</kbd> changes the current LSP buffer’s autotrigger setting. <kbd>Ctrl-Space</kbd> requests completion when it is enabled. Built-in completion controls remain available independently.</p></section>
<footer>Generated by <code>nvim/scripts/regenerate-keymap-atlas.py</code>. Regenerate after changing mappings; commit both this script and <code>nvim/docs/Nvim-Dark-Complete-Atlas.pdf</code> when publishing.</footer></body></html>'''

def main() -> int:
    DESKTOP.mkdir(parents=True, exist_ok=True); REPO_PDF.parent.mkdir(parents=True, exist_ok=True)
    HTML_OUT.write_text(build_html(extract_maps()), encoding="utf-8")
    weasy = shutil.which("weasyprint")
    if not weasy:
        print("weasyprint not found. Install it, then re-run this script.", file=sys.stderr); return 2
    subprocess.run([weasy, str(HTML_OUT), str(PDF_OUT)], check=True)
    shutil.copy2(PDF_OUT, REPO_PDF)
    print(f"HTML: {HTML_OUT}\nPDF: {PDF_OUT}\nRepository PDF: {REPO_PDF}")
    return 0

if __name__ == "__main__": raise SystemExit(main())
