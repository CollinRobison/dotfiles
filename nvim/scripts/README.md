# Neovim Atlas Regeneration

`regenerate-keymap-atlas.py` rebuilds the searchable **Neovim Dark Complete Atlas** while preserving the existing field-guide visual design.

## Run it

From the dotfiles repository root:

```bash
python3 nvim/scripts/regenerate-keymap-atlas.py
```

Or, from this directory:

```bash
python3 regenerate-keymap-atlas.py
```

## What it updates

The script:

1. Retains the checked-in 26-page field-guide template at `templates/Nvim-Dark-Complete-Atlas-main.pdf`.
2. Generates matching dark-mode addendum pages for the audited DAP debugger, Neotest test-management, adapter, and LSP-completion information.
3. Adds a visible **Last regenerated: YYYY-MM-DD** stamp beside the title on the first page and repeats it on the refreshed debugger/test-management page.
4. Writes preview artifacts to:
   - `~/Desktop/Nvim-Dark-Complete-Atlas.html`
   - `~/Desktop/Nvim-Dark-Complete-Atlas.pdf`
5. Updates the version committed with the dotfiles:
   - `nvim/docs/Nvim-Dark-Complete-Atlas.pdf`

## Requirements

- Python 3
- `pdfunite` (Poppler)
- Either:
  - `weasyprint` **and** `pypdf` installed on your `PATH` / Python environment, or
  - `uv` installed on your `PATH`

When `weasyprint` is not installed, the script automatically uses:

```bash
uv run --with weasyprint weasyprint ...
```

`uv` caches these dependencies after its first use. The script uses `pypdf` to stamp the date onto page one while preserving the original PDF artwork.

## After changing mappings

The existing 26-page field guide is the preserved visual baseline. The generated addendum contains the reviewed debugger/test/LSP inventory. If you make new debugger or test keybindings, update the audited command lists in `regenerate-keymap-atlas.py`, run the script, inspect the Desktop PDF, then commit both the script and `nvim/docs/Nvim-Dark-Complete-Atlas.pdf`.
