# Markdown In Neovim Research

## Recommendation

For regular project Markdown, use this combination:

- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim): renders Markdown inside the current buffer. Normal mode is rendered and insert mode is raw by default. `:RenderMarkdown buf_toggle` switches rendering for the current buffer.
- [image.nvim](https://github.com/3rd/image.nvim): renders actual inline Markdown images rather than only an image icon.
- [mkdnflow.nvim](https://github.com/jakewvincent/mkdnflow.nvim): follows standard and wiki-style links, navigates links and headings, keeps back/forward history, and formats, navigates, and extends Markdown tables.

`mkdnflow.nvim` removes the need for a separate table-formatting plugin. It is the strongest fit for project-local Markdown links and tables.

## Caveats

- `render-markdown.nvim` renders an image icon by itself. `image.nvim` supplies the rendered image pixels.
- `image.nvim` requires ImageMagick and a graphics-capable terminal backend. The current Neovim version and the existing `markdown` and `markdown_inline` Treesitter parsers are compatible, but ImageMagick is not installed.
- `mkdnflow.nvim` defaults conflict with the existing `<F2>` mapping and `<leader>nn` NvimTree mapping. Disable or remap those defaults during setup.
- If the Markdown collection is an Obsidian vault, use the maintained [obsidian-nvim/obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) for backlinks, vault search, completion, and link navigation. Keep `render-markdown.nvim`; use `mkdnflow.nvim` only if its table workflow is still wanted.

## Alternative

[markview.nvim](https://github.com/OXY2DEV/markview.nvim) provides hybrid edit/preview mode and a split view. `render-markdown.nvim` is the better fit for a same-buffer workflow because its normal-mode rendered view, insert-mode raw view, and explicit per-buffer toggle directly match the desired behavior.

## Reddit Signal

Recent r/neovim discussion favors in-buffer rendering for an editing workflow. `render-markdown.nvim` is commonly positioned as sufficient Markdown rendering without a browser preview. `markview.nvim` is also well regarded for hybrid mode, though an older discussion reported virtual-text drift on deep scrolling.

Broader Markdown threads consistently pair Treesitter rendering with link/navigation and formatting plugins rather than relying on browser-only preview.

## Sources

- [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
- [image.nvim](https://github.com/3rd/image.nvim)
- [mkdnflow.nvim](https://github.com/jakewvincent/mkdnflow.nvim)
- [markview.nvim](https://github.com/OXY2DEV/markview.nvim)
- [obsidian.nvim maintained fork](https://github.com/obsidian-nvim/obsidian.nvim)
- [Reddit: render-markdown.nvim discussion](https://www.reddit.com/r/neovim/comments/1bkhaxn/markdownnvim_improve_viewing_markdown_files/)
- [Reddit: Markdown plugin discussion](https://www.reddit.com/r/neovim/comments/1cz483z/what_plugins_do_you_use_for_markdown_files/)
- [Reddit: Obsidian with Vim bindings vs obsidian.nvim](https://www.reddit.com/r/neovim/comments/18l2eqg/obsidian_with_vim_bindings_vs_obsidiannvim/)
