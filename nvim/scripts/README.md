# Neovim Field Guide Generator

`regenerate-keymap-atlas.py` builds the searchable **Neovim Complete Field Guide** from the configuration in this checkout. It is a source-driven renderer: it does **not** copy, append to, or depend on a frozen PDF.

The guide combines three things:

1. editable teaching material from `atlas_guide_content.py`;
2. current configuration highlights placed in the relevant teaching sections; and
3. generated appendices for mappings, tooling, commands, and active runtime-only mappings.

A later run replaces changed entries and discovers newly supported configuration entries, so the output does not accumulate stale rows.

## Quick start

From the dotfiles repository root:

```bash
python3 nvim/scripts/regenerate-keymap-atlas.py
```

Or from `nvim/scripts/`:

```bash
python3 regenerate-keymap-atlas.py
```

The script resolves repository paths relative to itself, not to the shell’s current directory. Either command can therefore be launched from any working directory.

## Outputs

Every successful run overwrites these generated artifacts:

| Artifact | Location |
|---|---|
| HTML preview | `~/Desktop/Nvim-Dark-Complete-Atlas.html` |
| PDF preview | `~/Desktop/Nvim-Dark-Complete-Atlas.pdf` |
| Versioned PDF | `nvim/docs/Nvim-Dark-Complete-Atlas.pdf` |

The PDF is letter landscape, searchable, and shows **Last regenerated: YYYY-MM-DD** in the page-one top-right metadata.

## CLI options

```text
--non-interactive      Do not prompt for unknown mapping categories.
--skip-runtime-audit   Skip the headless-Neovim runtime cross-check.
```

### Unattended regeneration

Use this in a non-interactive shell, CI, or hook:

```bash
python3 nvim/scripts/regenerate-keymap-atlas.py --non-interactive
```

Unknown source mappings are rendered in **New / uncategorized configuration** rather than blocking the build.

### Fast source-only regeneration

```bash
python3 nvim/scripts/regenerate-keymap-atlas.py --skip-runtime-audit
```

This still parses the Lua source and produces the PDF; it simply omits the headless runtime observation.

## What the generator scans

On each run, the generator recursively reads `nvim/lua/**/*.lua` and extracts user-facing entries from the patterns currently used by this configuration:

### Mappings

- Lazy plugin `keys = { ... }` tables
- `which_key.add({ ... })`
- `vim.keymap.set(...)`, including buffer-local mappings
- local `map(lhs, rhs, desc)` wrappers used by the debugger/test setup
- Dashboard launcher data
- Mkdnflow data mappings that do not use a standard `desc`

Rows preserve mode and context where known, including Normal, Visual, Insert, Select, Markdown buffer, NvimTree, Dashboard, and LSP-attached buffer contexts.

Mappings without a usable Lua `desc` receive a best-effort reader-facing description. Add a real `desc` in the Lua configuration when a more precise explanation is needed.

### Tooling and automatic behavior

The **Configured Tooling** appendix inventories declared:

- plugins and integrations;
- LSP servers;
- DAP adapters;
- configured executables;
- Markdown formatters and linters.

Its **What it enables** column describes the user-facing capability, including features that are automatic or have no direct shortcut (for example, status/UI behavior, pairing, formatting, linting, language features, and integrations).

### Commands

The **Commands & automatic behavior** appendix extracts direct user-facing command entry points from:

- `vim.api.nvim_create_user_command(...)`; and
- configured `<cmd>…<CR>` calls.

It lists the literal `:Command` form, a plain-English explanation, and the source file. This includes custom setup commands such as `:MasonInstallDebugAdapters` as well as configured entry points for the file explorer, Telescope, sessions, Git, Markdown, tests, and UI tools.

## Runtime audit

Unless `--skip-runtime-audit` is given, the script starts this checkout in headless Neovim and records **described** active mappings from:

- global contexts;
- a Markdown buffer; and
- an NvimTree buffer.

Named mappings present at runtime but absent from the source extraction appear in the **Runtime-discovered keymaps** appendix. Internal `<Plug>` indirection and undocumented default Vim mappings are intentionally not treated as ordinary custom configuration rows.

The audit also reports the number of attached LSP clients. It is a cross-check, not proof that every filetype/plugin condition was loaded: an isolated machine may not have a server attach. In that case, source-derived LSP rows remain in the guide with their LSP context label instead of being represented as runtime-verified.

## Editable inputs

| File | Purpose | Edit when… |
|---|---|---|
| `atlas_guide_content.py` | Teaching-first Vim reference, workflows, examples, and Ctrl+F intent index | Improving explanations or educational flow |
| `atlas-categories.json` | Persisted category choices for newly discovered mappings | An interactive run saves a new category choice, or a category needs curation |
| `regenerate-keymap-atlas.py` | Extraction, descriptions, rendering, command/tool inventory, and validation behavior | Adding a new configuration pattern or improving generated descriptions/layout |
| `nvim/lua/**/*.lua` | Actual Neovim configuration | Adding/changing keybindings, commands, plugins, tools, or behavior |

## Requirements

- Python 3
- Neovim for the normal runtime audit; it is optional with `--skip-runtime-audit`
- Either `weasyprint` on `PATH`, or `uv` on `PATH`

When `weasyprint` is unavailable, the generator renders through:

```bash
uv run --with weasyprint weasyprint <html> <pdf>
```

`uv` caches the temporary renderer environment after its first use.

On macOS, install the native libraries used by WeasyPrint:

```bash
brew install pango
```

The generator automatically adds Homebrew's `lib` directory to
`DYLD_FALLBACK_LIBRARY_PATH` when invoking WeasyPrint.

## Recommended workflow after a configuration change

1. Change the relevant Lua configuration.
2. Regenerate the guide:
   ```bash
   python3 nvim/scripts/regenerate-keymap-atlas.py
   ```
3. Confirm the new/changed literal key, command, capability, or tool is searchable in the Desktop PDF.
4. Check that its mode/context and reader-facing description are accurate.
5. Visually inspect the relevant teaching and appendix pages for table/keycap collisions or clipping.
6. Commit the generated PDF, generator changes (when applicable), and README/category updates together.

## Verification commands

```bash
python3 -m py_compile nvim/scripts/regenerate-keymap-atlas.py nvim/scripts/atlas_guide_content.py
python3 nvim/scripts/regenerate-keymap-atlas.py --non-interactive
pdfinfo nvim/docs/Nvim-Dark-Complete-Atlas.pdf
pdftotext -layout nvim/docs/Nvim-Dark-Complete-Atlas.pdf /tmp/nvim-atlas.txt
git diff --check
```

For a visual check, render targeted pages to PNG and inspect them:

```bash
mkdir -p /tmp/nvim-atlas-review
pdftoppm -png -f 1 -l 1 -r 150 nvim/docs/Nvim-Dark-Complete-Atlas.pdf /tmp/nvim-atlas-review/page
```

## Scope and limitations

The generator supports the Lua declaration styles currently present in this repository. Arbitrary dynamically constructed mappings, conditionally loaded features that are neither declared in a supported source pattern nor loaded by the audit, and mappings that require a real attached language server may need explicit extractor support before they appear automatically. Treat the Lua source as the configuration truth; use the runtime appendix as an additional availability check.
