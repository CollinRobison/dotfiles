# Neovim Field Guide Generator

`regenerate-keymap-atlas.py` rebuilds the searchable **Neovim Complete Field Guide** from the current configuration in this checkout.

It keeps the dark landscape field-guide look and the beginner-friendly quick start, but it does **not** copy or append to a frozen PDF. That means an updated mapping replaces its old entry and newly declared mappings/tooling are added to the appropriate section the next time the guide is generated.

## Run it

From the dotfiles repository root:

```bash
python3 nvim/scripts/regenerate-keymap-atlas.py
```

Or from this directory:

```bash
python3 regenerate-keymap-atlas.py
```

The generator uses paths relative to its own location, so either command works from any current working directory.

## What it produces

- Desktop HTML preview: `~/Desktop/Nvim-Dark-Complete-Atlas.html`
- Desktop PDF: `~/Desktop/Nvim-Dark-Complete-Atlas.pdf`
- Versioned repository PDF: `nvim/docs/Nvim-Dark-Complete-Atlas.pdf`

The first page includes the **Last regenerated** date in the top-right corner.

## What is generated from configuration

On every normal run, the script scans every Lua file under `nvim/lua/` for user-facing mappings declared through:

- Lazy plugin `keys = { ... }` tables
- `which_key.add({ ... })`
- `vim.keymap.set(...)`, including buffer-local mappings
- local `map(lhs, rhs, desc)` helpers used by debugger/test configuration
- configured Dashboard launcher and Mkdnflow data mappings that do not use a `desc` option
- plugins, LSP servers, DAP adapters, declared executables, Markdown formatters, and Markdown linters

Rows are grouped by the source feature (for example: Find & Navigate, Git, Debugging, Testing, Markdown, NvimTree, and LSP/Completion). Each row carries its mode and context, so mappings that only work in a Markdown, NvimTree, dashboard, or LSP-attached buffer are labeled clearly.

The guide also includes a small stable Vim quick-start/reference section. Those are language fundamentals, not guessed plugin mappings.

## Runtime audit

A normal run starts this checkout headlessly and separately counts described global, Markdown-buffer, and NvimTree-buffer mappings. It also reports whether an LSP client attached; LSP-specific rows remain labeled from their source configuration if no server is available in the isolated check. The **published mapping inventory remains the Lua source scan**, which prevents unrelated plugin defaults from becoming misleading entries.

If you only need a fast source-only rebuild:

```bash
python3 nvim/scripts/regenerate-keymap-atlas.py --skip-runtime-audit
```

## Requirements

- Python 3
- Neovim for the normal runtime cross-check (optional when using `--skip-runtime-audit`)
- Either `weasyprint` available on `PATH`, or `uv` available on `PATH`

When `weasyprint` is absent, the script uses:

```bash
uv run --with weasyprint weasyprint ...
```

`uv` caches WeasyPrint after its first use.

## After changing mappings or tooling

1. Make the Lua configuration change.
2. Run the generator.
3. Open the Desktop PDF and use `Ctrl+F` for a literal key or plain-English action.
4. Confirm the changed/new command appears in its feature section and has the correct mode/context.
5. Review and commit the updated PDF and generator changes together.
