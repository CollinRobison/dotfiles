# Markdown In Neovim Research

## Implemented Stack

The Neovim setup uses this combination:

- [markview.nvim](https://github.com/OXY2DEV/markview.nvim): provides an in-buffer hybrid preview, a raw-source toggle, and a synchronized side-by-side preview.
- [image.nvim](https://github.com/3rd/image.nvim): renders actual inline Markdown images rather than only an image icon.
- [mkdnflow.nvim](https://github.com/jakewvincent/mkdnflow.nvim): follows standard and wiki-style links, navigates links and headings, keeps back/forward history, and formats, navigates, and extends Markdown tables.
- [conform.nvim](https://github.com/stevearc/conform.nvim) with Prettier: formats Markdown on demand and optionally on save.
- [nvim-lint](https://github.com/mfussenegger/nvim-lint) with markdownlint-cli2: publishes Markdown diagnostics after saving.

`mkdnflow.nvim` removes the need for a separate table-formatting plugin. It is configured for file-relative project links and accepts both standard Markdown and wiki links.

## Controls

| Mapping | Action |
| --- | --- |
| `<leader>mp` | Toggle rendered preview and raw Markdown source. |
| `<leader>mh` | Toggle Markview hybrid editing. |
| `<leader>ms` | Toggle the synchronized side-by-side preview. |
| `<leader>ml` | Follow the link under the cursor. |
| `<leader>mn` / `<leader>mN` | Next / previous Markdown link. |
| `<leader>mt` | Format the table under the cursor. |
| `<leader>mc` | Toggle a Markdown task. |
| `<leader>mf` / `<leader>mF` | Fold / unfold the current section. |
| `<leader>mw` | Add the word under the cursor to the project spell dictionary. |
| `<leader>mW` | Add every currently misspelled word in the document to the project spell dictionary. |
| `<leader>ma` | Toggle Markdown format-on-save for the current buffer. |
| `<leader>md` | Run Markdown linting now. |
| `<leader>lf` | Format the current Markdown buffer with Prettier. |

Markdown buffers also retain Mkdnflow's smart Enter, Tab / Shift-Tab link and table navigation, heading brackets, and smart `o` / `O` list behavior.

## Caveats

- `image.nvim` requires ImageMagick and a graphics-capable terminal backend. The setup uses Kitty's graphics protocol and ImageMagick's CLI processor.
- Images render in Markdown, HTML, CSS, Typst, Asciidoc, and Neorg buffers. Local and remote image URLs are enabled.
- Markdown prose wraps locally without changing the global no-wrap setting.
- Spell checking is enabled locally. Project `.vscode/settings.json` `cSpell.words` entries are imported into a generated cache dictionary, while approved words are stored at `<project-root>/.nvim/spell/en.utf-8.add`.
- Markdownlint's line-length rule (`MD013`) is disabled by default because prose wraps locally. A project `.markdownlint*` configuration takes precedence over this default.
- `mkdnflow.nvim` defaults conflict with the existing `<F2>` mapping and `<leader>nn` NvimTree mapping. Disable or remap those defaults during setup.
- If the Markdown collection is an Obsidian vault, use the maintained [obsidian-nvim/obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) for backlinks, vault search, completion, and link navigation. Keep Markview for rendering; use Mkdnflow only if its table workflow is still wanted.

## Alternative

`render-markdown.nvim` remains a simpler in-buffer alternative. Markview was selected for its hybrid editing and synchronized split view.

## Reddit Signal

Recent r/neovim discussion favors in-buffer rendering for an editing workflow. `render-markdown.nvim` is commonly positioned as sufficient Markdown rendering without a browser preview. `markview.nvim` is also well regarded for hybrid mode, though an older discussion reported virtual-text drift on deep scrolling.

Broader Markdown threads consistently pair Treesitter rendering with link/navigation and formatting plugins rather than relying on browser-only preview.

## Sources

- [image.nvim](https://github.com/3rd/image.nvim)
- [mkdnflow.nvim](https://github.com/jakewvincent/mkdnflow.nvim)
- [markview.nvim](https://github.com/OXY2DEV/markview.nvim)
- [obsidian.nvim maintained fork](https://github.com/obsidian-nvim/obsidian.nvim)
- [Reddit: render-markdown.nvim discussion](https://www.reddit.com/r/neovim/comments/1bkhaxn/markdownnvim_improve_viewing_markdown_files/)
- [Reddit: Markdown plugin discussion](https://www.reddit.com/r/neovim/comments/1cz483z/what_plugins_do_you_use_for_markdown_files/)
- [Reddit: Obsidian with Vim bindings vs obsidian.nvim](https://www.reddit.com/r/neovim/comments/18l2eqg/obsidian_with_vim_bindings_vs_obsidiannvim/)
