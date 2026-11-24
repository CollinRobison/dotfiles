# Neovim Keymaps

Browse and edit your Neovim shortcuts from a local browser tab. The app uses Python's standard library and your installed Neovim. It needs no browser extension, package manager, or hosted service.

## Launch

Use Neovim 0.11 or later and Python 3.9 or later. This directory belongs inside the Neovim configuration shipped in this checkout. When installing the dotfiles, link, junction, or copy the entire `nvim` directory into the location reported by `:echo stdpath('config')`.

| Where | Browse and edit | Regenerate the PDF |
| --- | --- | --- |
| Neovim | `:Keymaps` | `:KeymapAtlas` regenerates and opens the PDF |
| macOS / Linux | `nvim/scripts/keymap-browser/nvim-keymaps` | Add `--atlas`, or `--atlas --open` |
| Windows | `.\nvim\scripts\keymap-browser\nvim-keymaps.cmd` | Add `--atlas`, or `--atlas --open` |

Run the shell examples from the dotfiles checkout. To launch from anywhere on macOS or Linux, symlink the executable into a directory on your `PATH`:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/nvim/scripts/keymap-browser/nvim-keymaps" ~/.local/bin/nvim-keymaps
```

On Windows, you can add the keymap-browser directory to your `PATH` and run `nvim-keymaps.cmd`. Use `NVIM_KEYMAPS_PYTHON` to point the launchers at a specific Python executable. Use `--no-open` to print the address and keep the local service in the current terminal.

## Browse and edit

- Search by action, key sequence, plugin, mode, or source file. Press `/` to focus the search field.
- Select an item to see its mode, context, and source. For supported Lua declarations, **Edit shortcut** previews the new keys and shows exact, overlapping, or intercepted shortcuts. Confirm the change to update the original Lua declaration. Restart Neovim to load the new keys.
- **Regenerate Atlas PDF** updates `nvim/docs/Nvim-Dark-Complete-Atlas.pdf` and downloads it. The PDF uses the existing [Atlas renderer](../keymap-atlas/README.md) and its WeasyPrint dependencies. The shell and Neovim PDF commands work without opening the browser app.

The inventory combines the installed Neovim help index, supported literal Lua declarations, and mappings discovered in a headless instance. The runtime audit probes Markdown, Mermaid, quickfix, help, NvimTree, and Telescope. Opening with `:Keymaps` also includes a snapshot of your current session, including attached LSP and buffer-local maps. Reopen from Neovim to capture a new live snapshot.

The app resolves Kitty's configured mappings and defaults using Kitty on your `PATH`. On macOS it reads symbolic shortcuts, App Shortcuts, and active Loop preferences. Linux discovery reads GNOME or KDE Plasma settings. Windows discovery covers standard OS shortcuts. Each platform can have additional privately registered shortcuts. Dynamic plugin mappings appear when they are exposed in a probed or live session.

The browser session uses a temporary loopback address. It exits after 20 minutes without requests. The app makes source edits only after rechecking the original file and the reviewed conflicts.

## Smart search

Choose **Smart search**, describe what you want to do, and select **Search with Pi**. For example, “How do I delete inside double quotes?” can show `di"` built from the delete operator and the inner-quote text object, plus a Visual-mode method. Smart search also lists relevant configured, runtime, and built-in keys. Select a match to see its mode, context, and source. Source and mode filters narrow the match list. The instructions can still show supporting keys from other modes or sources.

The first answer shows the full sequence, its starting mode, and what each part does. Expand **Other solutions** for alternatives. If a panel such as NvimTree overrides a built-in, the answer shows the sequence for a text-editing buffer and identifies the panel mapping.

Pick a **Model** from the chat models available through your Pi login and a **Reasoning** level supported by that model. The browser remembers these choices within its tab. To include the current buffer filetype and its mappings, open the browser using `:Keymaps` from that buffer. Reopen it when you want to capture a different buffer.

Smart search uses your configured model through the [Pi SDK](https://docs.pi.dev/latest/sdk) and requires Node.js 22.19 or newer. It can use the SDK from an existing Pi installation, including Homebrew or npm. If your Pi install does not include an importable SDK, install it with `npm install -g --ignore-scripts @earendil-works/pi-coding-agent`. Set `NVIM_KEYMAPS_PI_SDK` to the package directory for a custom installation or `NVIM_KEYMAPS_PI_MODEL` to `provider/model` to set the initial selection in new browser sessions.

The Pi session is temporary and runs with tools and extensions disabled. It sends your submitted question and shortcut metadata to the model. Source files and mapping implementations stay local. **Keyword search** works immediately and offline.
