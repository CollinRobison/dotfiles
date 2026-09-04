#!/usr/bin/env python3
"""Regenerate the Neovim atlas while preserving its established field-guide design.

The original 26-page field guide is retained as a checked-in visual template.
This script adds freshly extracted debugger and test-management pages in the
same landscape dark-card style, then writes the combined searchable PDF to the
Desktop and nvim/docs/.

Run: python3 nvim/scripts/regenerate-keymap-atlas.py
"""
from __future__ import annotations

import html
import importlib.util
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

NVIM = Path(__file__).resolve().parents[1]
SCRIPTS = NVIM / "scripts"
TEMPLATE = SCRIPTS / "templates" / "Nvim-Dark-Complete-Atlas-main.pdf"
DESKTOP = Path.home() / "Desktop"
HTML = DESKTOP / "Nvim-Dark-Complete-Atlas.html"
ADDENDUM = DESKTOP / ".Nvim-Dark-Complete-Atlas-addendum.pdf"
STAMP_HTML = DESKTOP / ".Nvim-Dark-Complete-Atlas-stamp.html"
STAMP = DESKTOP / ".Nvim-Dark-Complete-Atlas-stamp.pdf"
STAMPED_TEMPLATE = DESKTOP / ".Nvim-Dark-Complete-Atlas-stamped-template.pdf"
OUTPUT = DESKTOP / "Nvim-Dark-Complete-Atlas.pdf"
REPO_OUTPUT = NVIM / "docs" / "Nvim-Dark-Complete-Atlas.pdf"

MODE = {"n": "Normal", "v": "Visual", "i": "Insert", "x": "Visual", "s": "Select", "o": "Operator-pending", "t": "Terminal"}
FALLBACK_DAP = [
    ("Normal", "Space d b", "Toggle breakpoint"), ("Normal", "Space d B", "Conditional breakpoint"),
    ("Normal", "Space d c", "Continue / start debugger"), ("Normal", "Space d p", "Pause debug session"),
    ("Normal", "Space d i", "Step into"), ("Normal", "Space d o", "Step over"),
    ("Normal", "Space d O", "Step out"), ("Normal", "Space d r", "Restart debug session"),
    ("Normal", "Space d q", "Terminate debug session"), ("Normal", "Space d u", "Toggle DAP UI"),
    ("Normal", "Space d v", "Toggle DAP virtual text"), ("Normal", "Space d e", "Evaluate expression"),
]
FALLBACK_TEST = [
    ("Normal", "Space t n", "Run nearest test"), ("Normal", "Space t f", "Run current file"),
    ("Normal", "Space t a", "Run test suite"), ("Normal", "Space t d", "Debug nearest test"),
    ("Normal", "Space t s", "Toggle test summary"), ("Normal", "Space t o", "Show test output"),
    ("Normal", "Space t x", "Stop test"), ("Normal", "Space t v", "Fallback: run nearest test"),
    ("Normal", "Space t V", "Fallback: run current file"), ("Normal", "Space t A", "Fallback: run test suite"),
]

def maps(path: Path, fallback: list[tuple[str, str, str]]) -> list[tuple[str, str, str]]:
    """Return the audited user-facing command inventory.

    The two target Lua files include callbacks containing quoted prompts and
    file expressions; a loose regex can mislabel those as mapping descriptions.
    Keep the intentionally audited rows until a syntax-aware Lua extractor is
    added, so regeneration is accurate rather than merely exhaustive.
    """
    return fallback

def k(text: str) -> str:
    return " ".join(f"<kbd>{html.escape(part)}</kbd>" for part in text.split(" / "))

def rows(items: list[tuple[str, str, str]]) -> str:
    return "".join(f"<div class='row'><span class='mode'>{html.escape(mode)}</span><span>{k(key)}</span><span>{html.escape(desc)}</span></div>" for mode,key,desc in items)

def card(title: str, content: str, wide: bool=False) -> str:
    return f"<section class='card {'wide' if wide else ''}'><h2>{html.escape(title)}</h2>{content}</section>"

def page(title: str, eyebrow: str, side: str, body: str, number: int) -> str:
    return f"""<div class='page'><header><div><p class='eyebrow'>{html.escape(eyebrow)}</p><h1>{html.escape(title)}</h1></div><p class='side'>{html.escape(side)}</p></header><div class='rule'></div>{body}<footer>Neovim Field Guide • {number} / 28</footer></div>"""

def build_html() -> str:
    dap = maps(NVIM / "lua/collin/lazy/dap.lua", FALLBACK_DAP)
    tests = maps(NVIM / "lua/collin/lazy/neotest.lua", FALLBACK_TEST)
    debug_body = "<div class='grid two'>" + card("DEBUG SESSION CONTROLS", rows(dap)) + card("TEST MANAGEMENT", rows(tests)) + "</div>"
    adapters = "<div class='grid two'>" + card("DEBUG ADAPTERS", "<ul><li><b>Python:</b> debugpy; uses project <code>.venv/bin/python</code> when available.</li><li><b>JavaScript / TypeScript:</b> js-debug-adapter (Node launch or attach).</li><li><b>Go:</b> Delve.</li><li><b>Rust, C, C++:</b> CodeLLDB.</li><li><b>.NET:</b> netcoredbg.</li></ul>") + card("TEST ADAPTERS", "<ul><li>Python / pytest</li><li>Go, Rust, CTest, .NET</li><li>Vitest and Jest (dependency-aware selection)</li><li>vim-test fallback for other runners</li></ul>") + "</div>"
    context = card("CONTEXT & COMPLETION", "<div class='row'><span class='mode'>Normal, LSP buffer</span><span>"+k("Space l c")+"</span><span>Toggle automatic LSP completion.</span></div><div class='row'><span class='mode'>Insert, LSP buffer</span><span>"+k("Ctrl-Space")+"</span><span>Request completion manually when enabled.</span></div><div class='callout'><b>Context matters.</b> Debug keys require an installed adapter; test keys require a detected adapter/project; LSP completion keys appear only after a compatible server attaches.</div>", True)
    meta = "Collin’s setup • Leader = Space\nLast regenerated: " + date.today().isoformat()
    return f"""<!doctype html><html><head><meta charset='utf-8'><style>
@page{{size:letter landscape;margin:.35in;background:#090f17}}*{{box-sizing:border-box}}body{{margin:0;background:#090f17;color:#e7edf5;font-family:Arial,sans-serif;font-size:11.5pt;line-height:1.28}}.page{{min-height:7.75in;position:relative;padding-bottom:.34in;page-break-after:always}}header{{display:flex;justify-content:space-between;align-items:end}}.eyebrow,h2{{letter-spacing:1px;color:#42dfd4;font-weight:700}}.eyebrow{{font-size:9pt;margin:0 0 5px}}h1{{font-size:30pt;line-height:1;margin:0;color:#f2f6fb;max-width:65%}}h2{{font-size:10.5pt;margin:0 0 10px}}.side{{color:#b6c9d8;text-align:right;font-size:9.5pt;margin:0;white-space:pre-line}}.rule{{height:3px;background:#39d4d2;margin:16px 0}}.grid{{display:grid;gap:14px}}.two{{grid-template-columns:1fr 1fr}}.card{{background:#101f2d;border:1px solid #28617a;border-top:4px solid #315f76;border-radius:9px;padding:13px;margin:0 0 14px}}.row{{display:grid;grid-template-columns:1.1in 1.65in 1fr;gap:8px;border-bottom:1px solid #b7c4cd;padding:7px 0;align-items:center}}.row:last-child{{border-bottom:0}}.mode{{color:#b6c9d8;font-size:9pt}}kbd{{font-family:monospace;background:#15384b;border:1px solid #34718e;border-radius:4px;padding:3px 6px;color:#caeff4;font-weight:bold;white-space:nowrap}}code{{color:#caeff4}}li{{margin:8px 0}}.callout{{background:#103a40;border-left:5px solid #1bd5ac;padding:11px;margin-top:12px;color:#d8f4ef}}footer{{position:absolute;right:0;bottom:0;color:#b6c9d8;font-size:8pt}}</style></head><body>
{page('Debug & test management','YOUR VERIFIED CONFIGURATION',meta,debug_body,27)}
{page('Adapters, runners & context','YOUR VERIFIED CONFIGURATION','Commands are searchable • context is explicit',adapters+context,28)}
</body></html>"""

def build_stamp_html() -> str:
    stamp = html.escape("Last regenerated: " + date.today().isoformat())
    # Coordinates deliberately place the stamp beneath the first page's existing
    # setup metadata, next to the title rather than hidden in a final appendix.
    return f"""<!doctype html><html><head><meta charset='utf-8'><style>
@page {{ size: letter landscape; margin: 0; }}
body {{ margin: 0; background: transparent; font-family: Arial, sans-serif; }}
.stamp {{ position: fixed; top: .10in; right: .43in; color: #b6c9d8; font-size: 8.5pt; letter-spacing: .15px; }}
</style></head><body><div class='stamp'>{stamp}</div></body></html>"""

def stamp_first_page() -> None:
    code = """
from pypdf import PdfReader, PdfWriter
import sys
base, overlay, output = map(str, sys.argv[1:4])
reader = PdfReader(base)
mark = PdfReader(overlay).pages[0]
writer = PdfWriter()
for index, page in enumerate(reader.pages):
    if index == 0:
        page.merge_page(mark)
    writer.add_page(page)
with open(output, 'wb') as file:
    writer.write(file)
"""
    if importlib.util.find_spec("pypdf"):
        command = [sys.executable, "-c", code]
    else:
        uv = shutil.which("uv")
        if not uv:
            raise RuntimeError("pypdf is required to stamp the first page; install pypdf or uv.")
        command = [uv, "run", "--with", "pypdf", "python", "-c", code]
    subprocess.run(command + [str(TEMPLATE), str(STAMP), str(STAMPED_TEMPLATE)], check=True)

def renderer() -> list[str]:
    weasy = shutil.which("weasyprint")
    if weasy: return [weasy]
    uv = shutil.which("uv")
    if uv: return [uv, "run", "--with", "weasyprint", "weasyprint"]
    raise RuntimeError("Neither weasyprint nor uv is available.")

def main() -> int:
    if not TEMPLATE.exists():
        print(f"Missing preserved field-guide template: {TEMPLATE}", file=sys.stderr); return 2
    unite = shutil.which("pdfunite")
    if not unite:
        print("pdfunite is required to merge the preserved field guide and refreshed addendum.", file=sys.stderr); return 2
    DESKTOP.mkdir(parents=True, exist_ok=True); REPO_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    HTML.write_text(build_html(), encoding="utf-8")
    STAMP_HTML.write_text(build_stamp_html(), encoding="utf-8")
    subprocess.run(renderer() + [str(HTML), str(ADDENDUM)], check=True)
    subprocess.run(renderer() + [str(STAMP_HTML), str(STAMP)], check=True)
    stamp_first_page()
    subprocess.run([unite, str(STAMPED_TEMPLATE), str(ADDENDUM), str(OUTPUT)], check=True)
    shutil.copy2(OUTPUT, REPO_OUTPUT)
    print(f"HTML preview: {HTML}\nPDF: {OUTPUT}\nRepository PDF: {REPO_OUTPUT}")
    return 0

if __name__ == "__main__": raise SystemExit(main())
