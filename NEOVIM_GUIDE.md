# Neovim Guide

This is a practical guide to the Neovim setup in this repository. It starts with the few Vim ideas that make everyday editing comfortable, then introduces the project, search, code, and Git workflows configured here.

You do not need to memorize this document. Learn the first-hour section, use `<leader>?` and `<leader>fk` when you forget something, and add the rest as it becomes useful.

## Read The Notation

`<leader>` is the Space key in this setup. For example, `<leader>ff` means press Space, then `f`, then `f` in Normal mode.

| Notation | Meaning |
| --- | --- |
| `Normal` | Press `Esc` first. This is the mode for navigation and commands. |
| `Insert` | The mode where typing adds text. Enter it with `i`. |
| `Visual` | The mode for selecting text. Enter it with `v`, `V`, or `<C-v>`. |
| `<CR>` | Enter or Return. |
| `<Esc>` | Escape. Return to Normal mode or dismiss many prompts. |
| `<C-x>` | Hold Control and press `x`. |
| `<S-h>` | Hold Shift and press `h`; this is usually uppercase `H`. |
| `<M-e>` | Meta/Alt plus `e`. On a Mac keyboard this is usually Option+E. Your terminal must send Option as Meta for it to work. |
| `[d` and `]d` | Two-key mappings. The bracket is pressed first; `[` usually means previous and `]` usually means next. |
| `:command` | A command-line command. Press `:` from Normal mode, type the command, then press Enter. |
| `g`, `z`, `d`, `c`, `y` | Prefixes that combine with a following motion or text object. |

Lowercase and uppercase are different. `<leader>hS` is not the same mapping as `<leader>hs`.

## Setup At A Glance

This configuration uses the `vague` color scheme, a Space leader key, system clipboard integration, visible absolute line numbers, no line wrapping, and automatic session restoration. It has native LSP completion and diagnostics, not `nvim-cmp`.

Projects are centered around the current tab's working directory. Choosing a project with `<leader>fp` changes that directory, updates nvim-tree, and opens the file explorer. Telescope searches hidden files, while still respecting normal ripgrep ignore rules.

The main plugin groups are:

| Need | Tool |
| --- | --- |
| Find files, text, help, projects | Telescope |
| Browse files | nvim-tree |
| Switch open files | Bufferline |
| Code diagnostics, completion, formatting | Native Neovim LSP and Mason |
| Git line changes | Gitsigns |
| Full Git interface | LazyGit |
| TODO/FIX comments | Todo Comments |
| Write Markdown, notes, and docs | Markview, Mkdnflow, Conform, nvim-lint, spell checking |
| Render inline document images | image.nvim with Kitty and ImageMagick |
| Restore working layouts | AutoSession |
| Discover mappings | Which-key and Telescope |

## First Hour

### 1. Start And Stop Safely

Open a project from your shell with `nvim .`, or open a file with `nvim path/to/file`.

The Alpha dashboard appears when Neovim starts without a file. Its buttons use single keys only while the dashboard is focused.

| Key | Dashboard action |
| --- | --- |
| `e` | Create an empty buffer for a new file. |
| `ff` | Find a file. |
| `fr` | Find a recent file. |
| `fs` | Search text. |
| `fp` | Pick a project. |
| `nt` | Toggle the file explorer. |
| `ss` | Find a saved session. |
| `lg` | Open LazyGit. |
| `fk` | Find keymaps. |
| `l` | Open Lazy's plugin manager. |
| `q` | Quit all Neovim windows. |

These are the first commands to know:

| Command | Action |
| --- | --- |
| `:w` | Write the current file. |
| `:q` | Close the current window if nothing is unsaved. |
| `:wq` | Write, then close the current window. |
| `:x` | Write only if changes exist, then close. |
| `:q!` | Close the current window and discard its unsaved changes. |
| `:qa` | Quit all windows if nothing is unsaved. |
| `:qa!` | Quit all windows and discard all unsaved changes. Use carefully. |
| `:e path/to/file` | Open a file by path. |
| `:enew` | Create an empty unnamed buffer. |
| `:help topic` | Open built-in Neovim documentation, for example `:help motion`. |

If anything feels wrong, press `<Esc>` once or twice. It is safe and returns you to Normal mode.

### 2. Learn The Three Editing Modes

Normal mode is for movement and editing commands. Insert mode is for entering text. Visual mode is for selecting text.

| Goal | Key |
| --- | --- |
| Enter Insert mode at cursor | `i` |
| Insert after cursor | `a` |
| Start a new line below | `o` |
| Start a new line above | `O` |
| Return to Normal mode | `<Esc>` |
| Select character-wise | `v` |
| Select line-wise | `V` |
| Select block-wise | `<C-v>` |

Do not stay in Insert mode just because you are used to a normal editor. Return to Normal mode when you want to move, search, delete, copy, or issue a command.

### 3. Move Without Reaching For The Mouse

Start with these motions. Counts work before most motions: `5j` moves down five lines and `3w` moves forward three words.

| Goal | Key |
| --- | --- |
| Left, down, up, right | `h`, `j`, `k`, `l` |
| Next word, previous word, end of word | `w`, `b`, `e` |
| Start or end of line | `0`, `$` |
| First non-space character | `^` |
| Top or bottom of file | `gg`, `G` |
| Go to line 42 | `42G` or `:42` |
| Match bracket, parenthesis, or brace | `%` |
| Scroll half a screen down or up | `<C-d>`, `<C-u>` |
| Center current line on screen | `zz` |

For now, use `j` and `k` for nearby lines, then use `/search`, `gg`, `G`, and Telescope for larger jumps.

### 4. Edit With Operator + Motion

Vim becomes efficient when you combine an operator with a movement. Think of the first key as the action and the rest as the target.

| Pattern | Meaning | Useful examples |
| --- | --- | --- |
| `d{motion}` | Delete | `dw` delete word, `d$` delete to end of line, `dd` delete line. |
| `c{motion}` | Change, then enter Insert mode | `cw` change word, `cc` change line. |
| `y{motion}` | Yank or copy | `yw` copy word, `yy` copy line. |
| `>{motion}` / `<{motion}` | Indent or outdent | `>>` indent line, `<<` outdent line. |
| `x` | Delete character under cursor | Use for a single character. |
| `p` / `P` | Paste after / before cursor | Your default register uses the system clipboard. |
| `u` / `<C-r>` | Undo / redo | Use these constantly and without fear. |
| `.` | Repeat last change | Great after a simple edit. |

Text objects make the same commands more precise. `i` means inside and `a` means around, including surrounding whitespace or punctuation when appropriate.

| Goal | Example |
| --- | --- |
| Change a word | `ciw` |
| Delete inside quotes | `di"` |
| Change inside parentheses | `ci(` |
| Delete around a function argument block | `da(` |
| Select a paragraph | `vap` |

These are optional for day one, but `ciw`, `ci"`, and `ci(` are worth practicing early.

### 5. Search And Replace

| Goal | Key or command |
| --- | --- |
| Search forward | `/text<CR>` |
| Search backward | `?text<CR>` |
| Next / previous search match | `n` / `N` |
| Clear highlighted search matches | `<leader>nh` |
| Replace first match on current line | `:s/old/new/` |
| Replace all matches on current line | `:s/old/new/g` |
| Replace all matches in the file | `:%s/old/new/g` |
| Replace all matches and ask each time | `:%s/old/new/gc` |

Your search is case-insensitive by default. Including an uppercase letter makes that one search case-sensitive. For example, `/todo` matches `TODO`, while `/Todo` does not.

### 6. Work With Files, Buffers, Windows, And Tabs

A file you open becomes a buffer. A window displays a buffer. A tab page can hold a layout of windows. Bufferline at the top shows open buffers.

| Goal | Key or command |
| --- | --- |
| Previous / next buffer | `<S-h>` / `<S-l>` |
| Pick an open buffer visually | `<leader>bp` |
| Close current buffer | `<leader>bd` |
| Split window horizontally / vertically | `:split` / `:vsplit` |
| Move between split windows | `<C-w>h`, `<C-w>j`, `<C-w>k`, `<C-w>l` |
| Close current split | `<C-w>q` |
| Create a new tab page | `:tabnew` |
| Next / previous tab page | `gt` / `gT` |

Use buffers for files you are actively editing. Use splits only when comparing or referring to two things at once. Use project sessions when you want to come back to a multi-window workspace later.

## Daily Project Workflow

This is a good default loop for a coding session:

1. Start Neovim with `nvim .` from the project directory, or press `<leader>fp` and select a project from `~/Repos`.
2. Use `<leader>ff` to open a file or `<leader>fg` to search project text.
3. Use `<leader>nf` when you need the file explorer to reveal the current file.
4. Address diagnostics with `[d`, `]d`, `<leader>ld`, and LSP actions.
5. Save with `:w`; format manually with `<leader>lf` when the file's LSP supports formatting.
6. Review edits with Gitsigns or open `<leader>lg` for full Git work.
7. AutoSession restores the project layout later. Save deliberately with `<leader>ws` when needed.

## Finding And Opening Things

Telescope is the fastest way to locate files, text, buffers, help, diagnostics, projects, and Git metadata. In a Telescope picker, type to filter, use `<C-j>` and `<C-k>` or arrow keys to move, press Enter to open the selection, and press `<Esc>` to close it.

| Mapping | Action |
| --- | --- |
| `<leader>ff` | Find files. Includes hidden files. |
| `<leader>fg` | Search text in the project. |
| `<leader>fw` | Search the word under the cursor in the project. |
| `<leader>fb` | Find open buffers. |
| `<leader>fr` | Find recently opened files. |
| `<leader>fh` | Search Neovim help tags. |
| `<leader>fk` | Search all registered keymaps. |
| `<leader>fd` | Find diagnostics. |
| `<leader>f/` | Fuzzy-search only the current buffer. |
| `<leader>fR` | Resume the previous Telescope picker. |
| `<leader>fp` | Pick a project beneath `~/Repos`; updates the tab working directory and nvim-tree root. |
| `<leader>gc` | Browse Git commits. |
| `<leader>gb` | Browse Git branches. |
| `<leader>gs` | Browse Git status entries. |

When you do not know a mapping, use `<leader>fk`. When you do not know a Neovim feature, use `<leader>fh` and search help.

## File Explorer

nvim-tree is the left-side file explorer. It tracks the active project root and follows the current file.

| Mapping | Action |
| --- | --- |
| `<leader>nt` | Toggle the explorer. |
| `<leader>nn` | Focus the explorer. |
| `<leader>nf` | Reveal and focus the current file in the explorer. |
| `<leader>nr` | Refresh the explorer. |
| `<leader>nc` | Collapse all folders. |
| `<leader>ne` | Expand all folders. |

Inside the explorer, these useful keys are nvim-tree defaults, not custom mappings: Enter opens a file, `a` creates, `r` renames, `d` deletes, `x` cuts, `c` copies, `p` pastes, and `g?` opens its in-tree help. Check the prompt carefully before deleting or renaming files.

## Code Intelligence

Mason installs and manages language servers. This configuration enables LSP support for Bash, C/C++, C#, CSS, Docker, Go, GraphQL, HTML, JSON, Lua, Markdown, Prisma, Python, Rust, SQL, Svelte, TOML, TypeScript/JavaScript, Vimscript, XML, and YAML.

Completion appears automatically when a language server supports it. In the completion menu, use `<C-n>` and `<C-p>` to choose an item, `<C-y>` to accept it, and `<C-e>` to dismiss it.

The following built-in LSP mappings are available only after a language server attaches to the current file.

| Mapping | Action |
| --- | --- |
| `K` | Show hover documentation for the symbol under the cursor. |
| `grn` | Rename the symbol under the cursor. |
| `gra` | Show available code actions. |
| `grr` | Find references to the symbol. |
| `gri` | Find implementations. |
| `gO` | List document symbols. |
| `<leader>lf` | Format the current buffer through its LSP. |
| `<leader>li` | Toggle inlay hints when the server supports them. |

Diagnostics are available globally:

| Mapping | Action |
| --- | --- |
| `[d` | Previous diagnostic and its floating explanation. |
| `]d` | Next diagnostic and its floating explanation. |
| `<leader>ld` | Show the diagnostic under the cursor. |
| `<leader>fd` | Search all diagnostics with Telescope. |

Use `:Mason` to inspect installed language servers, `:LspInfo` to see which clients are attached to the current file, and `:checkhealth` when something appears broken.

Python uses strict BasedPyright type checking plus Ruff diagnostics. C# Roslyn analyzes the full solution and shows references and test Code Lens where supported. Formatting is manual by design; saving does not reformat your files automatically.

## Sessions And Workspace State

AutoSession restores buffers, tab layouts, working directories, and local options. It deliberately avoids saving the dashboard or file-tree-only state.

| Mapping | Action |
| --- | --- |
| `<leader>wr` | Search and restore a saved session. |
| `<leader>ws` | Save the current session. |

If the explorer is open when a session saves, this setup closes it first so restored sessions do not become a tree-only view.

## Git Workflow

There are two Git tools with different jobs:

| Tool | Best for |
| --- | --- |
| Gitsigns | Reviewing line-level changes, staging small hunks, and inspecting blame without leaving code. |
| LazyGit | Status, branch management, commits, stashes, rebases, and broader Git operations. |

### Gitsigns

The sign column shows changed lines. Bars and counts identify added or changed sections, while deletion markers show removed lines. Changes in untracked files are included.

| Mapping | Action |
| --- | --- |
| `[h` / `]h` | Previous / next Git hunk. |
| `<leader>hp` | Preview the current hunk in a floating window. |
| `<leader>hi` | Preview the current hunk inline, including removed lines. |
| `<leader>hs` | Stage the current hunk. In Visual mode, stage the selected lines. |
| `<leader>hr` | Reset the current hunk. In Visual mode, reset the selected lines. |
| `<leader>hS` | Stage every unstaged change in the current file. |
| `<leader>hR` | Discard every unstaged change in the current file. Destructive. Preview first. |
| `<leader>hU` | Unstage the entire current file without discarding its contents. |
| `<leader>hb` | Show detailed blame for the current line. |
| `<leader>hB` | Toggle compact blame text at the end of the current line. |
| `<leader>uw` | Toggle word-level Git diff highlighting. |
| `<leader>hd` | Diff the current file against the staging index; useful for unstaged changes. |
| `<leader>hD` | Diff the current file against `HEAD`; useful for all changes since the last commit. |
| `<leader>hq` | Put current-file hunks in Quickfix. |
| `<leader>hQ` | Put repository hunks in Quickfix. |
| `<leader>hl` | Put current-file hunks in the location list. |
| `ih` | Select the current hunk as a text object in Visual or operator-pending mode. `vih` selects it. |

Quickfix is a project-wide navigable results list. The location list is similar but belongs to the current window. Use `:copen` to show Quickfix, `:cnext` and `:cprev` to move through it, and `:cclose` to close it. Use `:lopen`, `:lnext`, `:lprev`, and `:lclose` for a location list.

Gitsigns exposes additional commands through `:Gitsigns`. Type `:Gitsigns` and press Tab to inspect them. Useful examples are `:Gitsigns blame`, `:Gitsigns change_base HEAD~1`, and `:Gitsigns reset_base`.

### LazyGit

LazyGit opens as a large rounded terminal floating window. It uses the active tab's project working directory, so select a project with `<leader>fp` before opening it when necessary.

| Mapping | Action |
| --- | --- |
| `<leader>lg` | Open the LazyGit dashboard. |
| `<leader>lG` | Open LazyGit at the Git root for the current file. |
| `<leader>lL` | Open a repository commit-history view. |
| `<leader>ll` | Open a commit-history view filtered to the current file. |

Press `q` inside LazyGit to close the dashboard and return to Neovim. Press `<Esc>` to leave a focused LazyGit panel or cancel its current action.

When LazyGit needs a commit message or rebase editor, it opens a split in this same Neovim session through `nvr`. Write the message, then close that buffer, usually with `:wq`, so Git and LazyGit can continue. This behavior is enabled only when `nvr` is installed, and the Brewfile installs it as a `uv` tool.

Useful direct commands are `:LazyGit`, `:LazyGitCurrentFile`, `:LazyGitFilter`, `:LazyGitFilterCurrentFile`, and `:LazyGitConfig`.

## TODO Comments

Todo Comments highlights actionable comments only, not matching text in strings or identifiers. Write a colon after the keyword so it is recognized.

```lua
-- TODO: add caching before this becomes a bottleneck
-- FIX: handle an empty response
-- NOTE: the API intentionally returns a partial result
-- WARN: this mutates the shared configuration
```

Recognized primary keywords are `TODO`, `FIX`, `HACK`, `WARN`, `PERF`, `NOTE`, and `TEST`. Common aliases include `FIXME`, `BUG`, `WARNING`, and `INFO`.

| Mapping | Action |
| --- | --- |
| `[t` / `]t` | Previous / next todo comment. |
| `<leader>ft` | Search todo comments with Telescope. |
| `<leader>fT` | Send project todo comments to Quickfix. |
| `<leader>fL` | Send project todo comments to the location list. |

The direct commands are `:TodoTelescope`, `:TodoQuickFix`, and `:TodoLocList`.

## Markdown, Notes, And Images

Markdown and R Markdown buffers have a dedicated authoring workflow. These mappings are buffer-local: they appear only in Markdown or R Markdown files, so use `<leader>?` after opening one to review them.

Markdown prose wraps visually without changing the global no-wrap behavior. Spell checking is enabled locally with United States English, and the buffer keeps normal code-editor behavior outside Markdown files.

### Preview, Links, Tables, And Tasks

| Mapping | Action |
| --- | --- |
| `<leader>mp` | Toggle Markview's rendered preview and raw Markdown source. |
| `<leader>mh` | Toggle Markview hybrid editing preview. |
| `<leader>ms` | Toggle a synchronized side-by-side preview. |
| `<leader>ml` | Follow the Markdown or wiki link under the cursor. |
| `<leader>mn` / `<leader>mN` | Move to next / previous link. |
| `<leader>mt` | Format the table under the cursor. |
| `<leader>mc` | Toggle a Markdown task checkbox in Normal or Visual mode. |
| `<leader>mf` / `<leader>mF` | Fold / unfold the current Markdown section. |
| `<leader>mw` | Add the word under the cursor to the project spell dictionary. |
| `<leader>mW` | Add every currently misspelled word in the document to the project spell dictionary. |
| `<leader>ma` | Toggle Markdown format-on-save for this buffer. |
| `<leader>mT` | Toggle table mode: disable or restore prose wrapping in the current window. |
| `<leader>md` | Run Markdown linting now. |
| `<CR>` | Use Mkdnflow's smart Enter in Normal, Insert, or Visual mode. |

Markview renders headings, lists, task boxes, links, code blocks, and other Markdown elements inside Neovim. Start with `<leader>mh` for a useful editing view: source remains editable while rendered information is visible. Use `<leader>mp` when you want a cleaner reading view, and `<leader>ms` when comparing source and preview side by side.

Markview already uses rounded table borders. Wide tables can still render only partially while prose wrapping is enabled, because rendering a full grid into wrapped lines would break its layout. Use `<leader>mt` to align a table's source, then use `<leader>mT` to enter table mode. Table mode disables wrapping, line breaking, and break indentation in the current Markdown window and refreshes Markview so wide tables render as complete grids. Press `<leader>mT` again to restore comfortable wrapped prose.

Mkdnflow recognizes both standard Markdown links such as `[Guide](guide.md)` and wiki links such as `[[Guide]]`. Links resolve relative to the current file, so a note collection can remain portable inside a repository. Use `<leader>ml` to follow one rather than manually resolving paths.

In Markdown, Mkdnflow also keeps useful defaults:

| Context | Built-in behavior |
| --- | --- |
| Heading navigation | `]]` and `[[` move to next and previous headings. `][` and `[]` move among headings at the same level. |
| Lists | `o` and `O` create a suitable list item below or above when used on a list. |
| Tables in Insert mode | `<Tab>` and `<S-Tab>` move through cells; rows and columns extend automatically when needed. |
| List indentation in Insert mode | `<C-t>` and `<C-d>` indent or dedent a list item. |
| Spelling | `]s` and `[s` move to next and previous misspelling; `z=` shows replacement suggestions. |

The configuration disables Mkdnflow defaults that would conflict with existing setup mappings, including its `<F2>` and `<leader>nn` mappings. Use the explicit `<leader>m...` mappings above instead.

### Spell Dictionaries

`<leader>mw` writes approved words to `<project-root>/.nvim/spell/en.utf-8.add`. Commit that file when the spelling is project terminology the whole team should share.

If a project contains `.vscode/settings.json` with a `cSpell.words` list, the setup imports those words into a generated Neovim cache dictionary. It reads the existing VS Code vocabulary without modifying the VS Code file.

Use the standard `z=` suggestion menu before adding a word. Add a word only when it is genuinely correct; otherwise, fix the spelling. `<leader>mW` is intentionally powerful, so inspect the document first and use it only when its unknown words are all valid project terms.

### Formatting And Linting

Markdown uses Prettier through Conform and markdownlint-cli2 through nvim-lint.

| Behavior | What happens |
| --- | --- |
| Default save | Saves normally, then runs markdownlint-cli2 and publishes diagnostics. It does not format. |
| `<leader>ma`, then save | Enables buffer-local Prettier formatting on each save until toggled off or the buffer closes. |
| `<leader>md` | Runs markdownlint-cli2 immediately without saving. |
| `<leader>lf` | Remains the general LSP-format mapping. It is not the Markdown Prettier shortcut. |

Use `:ConformInfo` to see whether Prettier is available and what Conform would run. Use `[d`, `]d`, `<leader>ld`, or `<leader>fd` to inspect markdownlint diagnostics. A project `.markdownlint-cli2.*` configuration controls linting rules when present.

### Inline Images

`image.nvim` renders actual images inline instead of only showing a link or icon. It uses Kitty's graphics protocol and ImageMagick's `magick` command-line processor.

Use normal Markdown image syntax:

```markdown
![A local diagram](./images/architecture.png)
![A remote diagram](https://example.com/diagram.png)
```

Images render automatically in Markdown, R Markdown, and Quarto files. The same image support is enabled for Asciidoc, Typst, Neorg, HTML, and CSS buffers. Images remain visible in Insert mode, and the setup renders all supported images in the buffer rather than only the image under the cursor.

Remote image downloads are enabled. Open documents from trusted repositories when they contain remote image URLs, because viewing the document can request those URLs. Large or unreachable images can also delay rendering.

For inline images to appear, launch Neovim in Kitty or another terminal compatible with the configured Kitty backend, and ensure ImageMagick is installed. The current tool names are `kitty` and `magick`. Image rendering cannot be meaningfully tested in a headless Neovim process.

| Command | When to use it |
| --- | --- |
| `:Markview toggle` | Toggle rendered Markdown preview. |
| `:Markview hybridToggle` | Toggle hybrid Markdown preview. |
| `:Markview splitToggle` | Toggle synchronized split preview. |
| `:MkdnFollowLink` | Follow the link under the cursor. |
| `:MkdnTableFormat` | Format the table under the cursor. |
| `:MkdnToggleToDo` | Toggle a task checkbox. |
| `:MkdnFoldSection` / `:MkdnUnfoldSection` | Fold or unfold a section. |
| `:ConformInfo` | Inspect Markdown formatter availability and configuration. |

## UI And Editing Helpers

| Mapping | Action |
| --- | --- |
| `<F2>` | Toggle absolute line numbers in the current window. |
| `<F3>` | Toggle relative line numbers in the current window. Relative numbers make counted motions easier. |
| `<leader>ui` | Toggle indent guides. |
| `<leader>us` | Toggle indent scope highlighting. |
| `<leader>ua` | Toggle automatic pairs for brackets and quotes. |
| `<M-e>` in Insert mode | Use nvim-autopairs FastWrap to wrap nearby text. |
| `<leader>uw` | Toggle Gitsigns word-level diff highlighting. |
| `<leader>?` | Show buffer-local mappings through Which-key. |
| `<leader>fk` | Search all mappings through Telescope. |

Autopairs inserts matching brackets, quotes, backticks, and markup angle brackets. Backspace and Enter behave intelligently inside pairs. It is disabled in Git commit messages and Telescope prompts so it does not interfere with those interfaces.

Indent guides use subtle bars, and the active code scope uses a purple bar. They are visual aids only and do not change file contents.

## Complete Custom Mapping Reference

This section contains every mapping configured in this Neovim setup. Mappings listed as conditional require a matching LSP feature or an open dashboard.

| Group | Mapping | Action |
| --- | --- | --- |
| Dashboard | `e` | New file buffer, only on Alpha dashboard. |
| Dashboard | `ff` | Find file, only on Alpha dashboard. |
| Dashboard | `fr` | Find recent files, only on Alpha dashboard. |
| Dashboard | `fs` | Find text, only on Alpha dashboard. |
| Dashboard | `fp` | Find project, only on Alpha dashboard. |
| Dashboard | `nt` | Toggle nvim-tree, only on Alpha dashboard. |
| Dashboard | `ss` | Find session, only on Alpha dashboard. |
| Dashboard | `lg` | Open LazyGit, only on Alpha dashboard. |
| Dashboard | `fk` | Find keymaps, only on Alpha dashboard. |
| Dashboard | `l` | Open Lazy's plugin manager, only on Alpha dashboard. |
| Dashboard | `q` | Quit Neovim, only on Alpha dashboard. |
| General | `<F2>` | Toggle line numbers. |
| General | `<F3>` | Toggle relative line numbers. |
| General | `<leader>nh` | Clear search highlights. |
| Buffers | `<S-h>` / `<S-l>` | Previous / next buffer. |
| Buffers | `<leader>bp` | Pick a buffer. |
| Buffers | `<leader>bd` | Close current buffer. |
| Explorer | `<leader>nt` | Toggle nvim-tree. |
| Explorer | `<leader>nn` | Focus nvim-tree. |
| Explorer | `<leader>nf` | Reveal current file in nvim-tree. |
| Explorer | `<leader>nr` | Refresh nvim-tree. |
| Explorer | `<leader>nc` | Collapse all nvim-tree folders. |
| Explorer | `<leader>ne` | Expand all nvim-tree folders. |
| Find | `<leader>ff` | Find files. |
| Find | `<leader>fg` | Search project text. |
| Find | `<leader>fw` | Search word under cursor. |
| Find | `<leader>fb` | Find buffers. |
| Find | `<leader>fr` | Find recent files. |
| Find | `<leader>fh` | Find help. |
| Find | `<leader>fk` | Find keymaps. |
| Find | `<leader>fd` | Find diagnostics. |
| Find | `<leader>f/` | Search current buffer. |
| Find | `<leader>fR` | Resume Telescope picker. |
| Find | `<leader>fp` | Find project. |
| Sessions | `<leader>wr` | Find session. |
| Sessions | `<leader>ws` | Save session. |
| Diagnostics | `[d` / `]d` | Previous / next diagnostic. |
| Diagnostics | `<leader>ld` | Explain current diagnostic. |
| LSP | `<leader>lf` | Format buffer, conditional on an attached LSP. |
| LSP | `<leader>li` | Toggle inlay hints, conditional on LSP support. |
| Git pickers | `<leader>gc` | Browse commits. |
| Git pickers | `<leader>gb` | Browse branches. |
| Git pickers | `<leader>gs` | Browse Git status. |
| Gitsigns | `[h` / `]h` | Previous / next hunk. |
| Gitsigns | `<leader>hs` | Stage hunk or Visual selection. |
| Gitsigns | `<leader>hr` | Reset hunk or Visual selection. |
| Gitsigns | `<leader>hS` | Stage buffer. |
| Gitsigns | `<leader>hR` | Reset buffer. |
| Gitsigns | `<leader>hU` | Unstage buffer. |
| Gitsigns | `<leader>hp` | Preview hunk. |
| Gitsigns | `<leader>hi` | Inline hunk preview. |
| Gitsigns | `<leader>hb` | Blame line. |
| Gitsigns | `<leader>hB` | Toggle line blame. |
| Gitsigns | `<leader>hd` | Diff against index. |
| Gitsigns | `<leader>hD` | Diff against HEAD. |
| Gitsigns | `<leader>hq` | Current-file hunks to Quickfix. |
| Gitsigns | `<leader>hQ` | Repository hunks to Quickfix. |
| Gitsigns | `<leader>hl` | Current-file hunks to location list. |
| Gitsigns | `ih` | Hunk text object in Visual or operator-pending mode. |
| LazyGit | `<leader>lg` | Open dashboard. |
| LazyGit | `<leader>lG` | Open for current file. |
| LazyGit | `<leader>lL` | Open repository log. |
| LazyGit | `<leader>ll` | Open current-file log. |
| Todo | `[t` / `]t` | Previous / next todo. |
| Todo | `<leader>ft` | Search todos with Telescope. |
| Todo | `<leader>fT` | Todos to Quickfix. |
| Todo | `<leader>fL` | Todos to location list. |
| Markdown | `<leader>mp` | Toggle rendered preview. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mh` | Toggle hybrid preview. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>ms` | Toggle split preview. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>ml` | Follow link. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mn` / `<leader>mN` | Next / previous link. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mt` | Format table. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mc` | Toggle task in Normal or Visual mode. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mf` / `<leader>mF` | Fold / unfold section. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mw` / `<leader>mW` | Add current / all misspelled words to project dictionary. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>ma` | Toggle format on save. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>mT` | Toggle no-wrap table mode. Buffer-local to Markdown or R Markdown. |
| Markdown | `<leader>md` | Lint Markdown now. Buffer-local to Markdown or R Markdown. |
| Markdown | `<CR>` | Smart Enter in Normal, Insert, and Visual mode. Buffer-local to Markdown or R Markdown. |
| UI | `<leader>ui` | Toggle indent guides. |
| UI | `<leader>us` | Toggle indent scope. |
| UI | `<leader>ua` | Toggle autopairs. |
| UI | `<leader>uw` | Toggle Git word diff. |
| Autopairs | `<M-e>` | FastWrap in Insert mode. |
| Discovery | `<leader>?` | Show buffer-local mappings. |

## Plugin Labs

These labs teach the configured plugins through small, purposeful tasks. Do one at a time in a small project or a throwaway Git repository. The goal is to recognize when a tool helps, not to memorize every command.

### Lazy.nvim: Plugin Manager

**Goal:** know where plugins come from and how to inspect their health.

1. Open `:Lazy` from any buffer, or press `l` on the Alpha dashboard.
2. Find a plugin such as `gitsigns.nvim` and inspect its load state, dependencies, and log.
3. Press `?` inside Lazy to see its own controls.
4. Close the window with `q`.

| Command | When to use it |
| --- | --- |
| `:Lazy` | Open the plugin manager and inspect plugin state. |
| `:Lazy check` | Check whether configured plugins have updates. |
| `:Lazy sync` | Install missing plugins, clean removed ones, and update plugins. Run deliberately because it can change locked versions. |
| `:Lazy restore` | Return plugins to versions recorded in `lazy-lock.json`. |
| `:Lazy profile` | Investigate slow startup or plugin load time. |

The lockfile at `nvim/lazy-lock.json` records exact plugin revisions. Change it through Lazy commands rather than editing it by hand.

### Alpha: Start Dashboard

**Goal:** make the dashboard a useful launch point rather than a screen to skip.

1. Start `nvim` without a file.
2. Press `ff` to find a known file, then close that buffer with `<leader>bd`.
3. Restart `nvim` and press `fp` to choose a project.
4. Restart once more and press `l` to inspect plugins or `lg` to open LazyGit.

The dashboard is intentionally a short set of launch actions. Its keys apply only while the Alpha dashboard is focused; the same letters in a normal file have their usual Vim meaning.

### Telescope: Search And Project Switching

**Goal:** replace manual folder browsing with search-driven navigation.

1. Use `<leader>fp` to choose a project. Notice that the file explorer opens and the working directory in Lualine changes.
2. Use `<leader>ff`, type part of a filename, and press Enter to open it.
3. Use `<leader>fg`, search for a phrase that occurs in several files, and open a result.
4. With the cursor on a useful word, use `<leader>fw` to find all project occurrences.
5. Use `<leader>fR` after closing a picker to reopen the last search.

| Command | When to use it |
| --- | --- |
| `:Telescope` | List Telescope pickers and extensions. |
| `:Telescope find_files` | Find a file when you prefer commands over mappings. |
| `:Telescope live_grep` | Search project text. |
| `:Telescope diagnostics` | Browse diagnostics across the project. |
| `:Telescope project project` | Open the configured project picker. |

In any Telescope picker, type to narrow results, use `<C-j>` and `<C-k>` to move, press Enter to open, and press `<Esc>` to cancel. Use `<leader>fk` whenever you cannot remember a mapping.

### nvim-tree: File Explorer

**Goal:** learn the small set of explorer operations that are safer than improvising file commands.

1. Open the explorer with `<leader>nt` and focus it with `<leader>nn`.
2. Create a disposable file with `a`, name it, open it with Enter, then return to the tree with `<leader>nn`.
3. Rename the file with `r` and delete it with `d`. Read confirmation prompts before accepting.
4. Open a source file in the editor, then use `<leader>nf` to reveal it in the tree.
5. Press `g?` in the tree to view its built-in help.

| Command | When to use it |
| --- | --- |
| `:NvimTreeToggle` | Open or close the file explorer. |
| `:NvimTreeFocus` | Move focus to the explorer. |
| `:NvimTreeFindFile` | Reveal the current file. |
| `:NvimTreeRefresh` | Refresh files and Git state after external changes. |
| `:NvimTreeCollapse` / `:NvimTreeExpand` | Fold or unfold the tree. |

### Bufferline: Open Files

**Goal:** distinguish buffers from windows and move through active files quickly.

1. Open three files with `<leader>ff`.
2. Move among them with `<S-h>` and `<S-l>`.
3. Use `<leader>bp` and type the displayed label to jump directly to one buffer.
4. Close an unneeded buffer with `<leader>bd`; this closes the file buffer without necessarily closing the split that displayed it.

| Command | When to use it |
| --- | --- |
| `:BufferLineCyclePrev` / `:BufferLineCycleNext` | Move through buffers from command mode. |
| `:BufferLinePick` | Choose a visible buffer by its label. |
| `:bdelete` | Close the current buffer. |
| `:buffers` or `:ls` | List buffers when debugging a busy workspace. |

### AutoSession: Restore Workspaces

**Goal:** trust sessions without treating them as a substitute for saving files.

1. In a project, open two files and create a split with `:vsplit`.
2. Change to another tab with `:tabnew`, open a different file, then run `<leader>ws`.
3. Quit Neovim with `:qa` after writing your files.
4. Start Neovim again, use `<leader>wr`, and choose the project session.
5. Confirm that buffers, tabs, and layout return. If the layout is not useful, change it and save again.

| Command | When to use it |
| --- | --- |
| `:AutoSession search` | Find and restore a session. |
| `:AutoSession save` | Save the current layout explicitly. |
| `:AutoSession delete` | Remove an old session you no longer want. |

Sessions restore editor state, not unsaved file contents. Write files before relying on a session.

### Lualine, Vague, And Icons: Read The Interface

**Goal:** learn which UI details contain useful state.

1. Open a tracked file in a Git repository. Look at Lualine's branch, diff counts, diagnostics, path, current working directory, and cursor location.
2. Make one line change and notice the diff count in Lualine and the Gitsigns marker in the gutter.
3. Open nvim-tree and Telescope. Notice file-type icons supplied by `nvim-web-devicons` and `mini.icons`.
4. Use `i`, `v`, `R`, and `:` to enter Insert, Visual, Replace, and Command modes. Notice the statusline mode color change.

`vague.nvim` is the active color scheme. `tokyonight.nvim` is installed as an alternate theme but is not active by default.

| Command | When to use it |
| --- | --- |
| `:colorscheme vague` | Return to the configured theme. |
| `:colorscheme tokyonight-night` | Temporarily preview TokyoNight for the current Neovim session. |
| `:hi Normal` | Inspect the active highlight for normal text. |
| `:messages` | Read recent status and plugin messages. |

The icon plugins are dependencies rather than interactive tools. If icons look like squares or missing glyphs, verify that your terminal is using a Nerd Font such as the configured Maple Mono NF.

### Treesitter And Autotag: Structural Editing

**Goal:** see how syntax-aware behavior improves highlighting, indentation, pairs, and markup editing.

1. Open a file in a configured language such as Lua, Python, TypeScript, JSON, HTML, CSS, Markdown, or YAML.
2. Add nested code and observe indentation. Treesitter supplies the indentation expression when a parser is available.
3. In an HTML, JSX, TSX, Svelte, or XML file, type an opening tag such as `<section>`. Autotag should insert the closing tag.
4. Rename the opening tag and confirm that the paired closing tag follows.
5. Open `:InspectTree` in a source file to see the parsed syntax tree, then close the inspection window when finished.

| Command | When to use it |
| --- | --- |
| `:TSInstallInfo` | See installed Treesitter parsers and supported languages. |
| `:TSUpdate` | Update installed parsers after updating the plugin. |
| `:Inspect` | Inspect the syntax highlight and Treesitter capture at the cursor. |
| `:InspectTree` | Explore the parsed syntax tree for the current buffer. |

If a language has no parser or an out-of-date parser, syntax-aware features can be reduced even when a language server still works.

### Markdown, Markview, Mkdnflow, Linting, And Images

**Goal:** author a small Markdown document, preview it, navigate it, maintain its vocabulary, and validate it before sharing.

1. In a scratch project, create `notes/demo.md` and add two headings, a short list, a task such as `- [ ] Review this guide`, a small table, and both a standard and wiki-style link.
2. Open the file with Neovim. Confirm prose wraps naturally and misspelled words are highlighted.
3. Use `<leader>mh` to enter hybrid preview. Compare the editable source with the rendered heading, task, table, and links.
4. Use `<leader>mp` to see the full rendered mode, then use `<leader>ms` to try the synchronized side-by-side preview. Return to the mode that best fits the current task.
5. Put the cursor on a link, use `<leader>ml`, then return with normal buffer navigation. Use `<leader>mn` and `<leader>mN` to practice link traversal.
6. Place the cursor in the table and use `<leader>mt`. Enter Insert mode in its last cell, press `<Tab>`, and observe automatic table expansion.
7. If the table is wider than the window, use `<leader>mT` to disable wrapping and render the complete grid. Press it again after reviewing the table to restore wrapped prose.
8. Use `<leader>mc` on the task item. Repeat in Visual mode after selecting multiple task lines with `V`.
9. Intentionally add a valid project-specific word that spell checking does not know. Press `z=` first; if it is correct terminology, use `<leader>mw`. Confirm the word was added to `.nvim/spell/en.utf-8.add` at the project root.
10. Run `<leader>md` to lint immediately. Inspect any diagnostics with `<leader>ld`, correct one, and run linting again.
11. Toggle `<leader>ma`, save the file, and observe Prettier formatting on save. Toggle it off when you want to retain manual formatting control.
12. Add a local image with `![Description](./image.png)` in a project that contains an image. In Kitty, confirm that it renders inline. Use a remote image only from a trusted source.

| Command | What to practice |
| --- | --- |
| `:Markview hybridToggle` | Switch between source-first and rendered editing. |
| `:Markview splitToggle` | Compare source and preview in a synchronized layout. |
| `:MkdnFollowLink` | Follow the current link without using its mapping. |
| `:MkdnTableFormat` | Repair table alignment after manual edits. |
| `:MkdnToggleToDo` | Mark a task complete or incomplete. |
| `:ConformInfo` | Confirm that Prettier is found before enabling format on save. |

Use `<leader>mW` only as a cleanup pass on a reviewed document. It accepts every current misspelling as project vocabulary, which is convenient for a glossary but harmful if the document still contains real typos.

### Indent Blankline And Autopairs: Editing Feedback

**Goal:** make automatic editing help visible and controllable.

1. In an indented source file, use `<leader>ui` to hide and restore indentation guides.
2. Move through nested blocks and use `<leader>us` to compare normal guides with highlighted scope guides.
3. In Insert mode, type `(`, `[`, `{`, `"`, and backticks. Notice that matching pairs are created.
4. Type inside a pair and press Backspace or Enter to observe pair-aware behavior.
5. Toggle pairs off with `<leader>ua`, repeat one example, then toggle them back on.
6. In a markup file, select or position text near a tag and try `<M-e>` to practice FastWrap.

| Command | When to use it |
| --- | --- |
| `:IBLToggle` | Toggle indentation guides. |
| `:IBLToggleScope` | Toggle scope guides. |

Autopairs has no separate command palette in this configuration. Its important controls are `<leader>ua` and `<M-e>`.

### Mason And Native LSP: Code Intelligence

**Goal:** verify that the right language server is attached and practice the difference between navigation, diagnostics, actions, and formatting.

1. Open a source file that belongs to a configured language.
2. Run `:LspInfo` and identify the attached client or clients.
3. Put the cursor on a symbol and try `K`, `grr`, `gri`, and `gO` where the language server supports them.
4. Create a harmless type or syntax error, save, then use `]d`, `[d`, and `<leader>ld` to inspect it.
5. Try `gra` on a diagnostic to look for a code action.
6. Copy an identifier, use `grn` to rename it, inspect the proposed edits, and confirm only if they are correct.
7. Use `<leader>lf` on a file that supports LSP formatting.

| Command | When to use it |
| --- | --- |
| `:Mason` | Inspect, install, or update language servers. |
| `:MasonLog` | Diagnose a failed Mason installation. |
| `:LspInfo` | See attached language servers and their capabilities. |
| `:checkhealth vim.lsp` | Run Neovim's LSP health checks. |
| `:checkhealth mason` | Run Mason health checks. |

Completion is native Neovim completion. When the menu opens, use `<C-n>`, `<C-p>`, `<C-y>`, and `<C-e>` rather than expecting a completion-plugin-specific mapping.

### Todo Comments: Keep Follow-Up Work Visible

**Goal:** turn comment markers into a navigable work list.

1. Add three comments in a disposable source file: `TODO:`, `FIX:`, and `NOTE:`.
2. Use `]t` and `[t` to move among them.
3. Use `<leader>ft` to search all project todo comments in Telescope.
4. Use `<leader>fT`, then `:copen`, `:cnext`, and `:cprev` to explore the Quickfix list. Press Enter on an entry to jump to it.
5. Replace a completed `TODO:` with a normal comment and confirm it leaves the picker on the next search.

| Command | When to use it |
| --- | --- |
| `:TodoTelescope` | Open the project todo picker. |
| `:TodoQuickFix` | Put project todos in Quickfix. |
| `:TodoLocList` | Put project todos in the location list. |

Use a colon after a keyword. `TODO: explain this` is recognized; plain text mentioning the word TODO is intentionally not highlighted unless it is a matching comment marker.

### Gitsigns: Review And Stage Line Changes

**Goal:** practice a safe hunk-level Git workflow before using it on important work.

1. In a disposable Git repository, edit two separate areas of a tracked file and save it.
2. Use `]h` and `[h` to move between changed hunks.
3. Preview each with `<leader>hp`, then use `<leader>hi` to compare the inline view.
4. Stage only one hunk with `<leader>hs`.
5. Use `<leader>hd` to inspect remaining unstaged changes against the index.
6. Use `<leader>hD` to inspect all changes against `HEAD`.
7. Use `<leader>hq` and `:copen` to see the file's hunks as a navigable list.
8. Make a disposable third hunk and reset only that hunk with `<leader>hr`.

| Command | When to use it |
| --- | --- |
| `:Gitsigns` | Discover every Gitsigns action through command completion. |
| `:Gitsigns blame` | Open full-file blame in a scroll-bound split. |
| `:Gitsigns diffthis HEAD` | Diff the current file against a revision. |
| `:Gitsigns change_base HEAD~1` | Temporarily compare signs against an earlier revision. |
| `:Gitsigns reset_base` | Restore the normal index comparison. |
| `:Gitsigns refresh` | Force Gitsigns to refresh after unusual external Git changes. |

Do not use `<leader>hR` in this lab until you have intentionally created throwaway changes. It discards all unstaged changes in the current file.

### LazyGit: Repository Workflow

**Goal:** build confidence with the full Git interface while keeping code visible in Neovim.

1. Open `<leader>lg` inside a small Git repository and inspect the status panel.
2. Use LazyGit's on-screen key hints to open files, inspect a diff, stage one file, and unstage it again.
3. Press `q` to return to Neovim, then confirm Gitsigns updated its gutter markers.
4. Reopen LazyGit with `<leader>lG` from a file inside a nested repository or submodule to see the current-file-root behavior.
5. Use `<leader>lL` for repository history and `<leader>ll` for the current file's history.
6. In a disposable repository, create a commit. When LazyGit opens a commit-message split in Neovim, write the message and close the buffer with `:wq` to let LazyGit continue.

| Command | When to use it |
| --- | --- |
| `:LazyGit` | Open LazyGit in the active project working directory. |
| `:LazyGitCurrentFile` | Open LazyGit at the current file's Git root. |
| `:LazyGitFilter` | Open project commit history. |
| `:LazyGitFilterCurrentFile` | Open current-file history. |
| `:LazyGitConfig` | Open LazyGit's own configuration file. |

Inside the dashboard, `q` closes LazyGit. Follow LazyGit's visible key hints for actions such as stage, commit, branch, stash, rebase, and remote operations; those are LazyGit defaults and can change independently of this Neovim configuration.

### Which-key: Discover Before Memorizing

**Goal:** use discovery tools instead of breaking flow to search configuration files.

1. In a regular source file, press Space and pause briefly. Which-key displays available leader continuations.
2. Press `<leader>?` to show buffer-local mappings, especially after opening a file with LSP support.
3. Press `<leader>fk`, search for `hunk`, `diagnostic`, or `LazyGit`, and inspect the mapping descriptions.
4. When you find a useful mapping, use it once immediately instead of trying to memorize the whole list.

Which-key has a one-second delay in this setup. It is a reminder system, not a required menu for every command.

## First Week Practice Plan

### Day 1: Modes And Safety

Practice `i`, `<Esc>`, `:w`, `:q`, `u`, `<C-r>`, `h`, `j`, `k`, and `l`. Open a harmless file, make a few edits, undo them, redo them, write the file, and close it.

### Day 2: Motions And Operators

Practice `w`, `b`, `e`, `0`, `$`, `gg`, `G`, `dw`, `cw`, `dd`, `yy`, `p`, and `ciw`. Do not aim for speed. Aim to recognize that an operator and motion form a sentence.

### Day 3: Finding Things

Use `<leader>ff`, `<leader>fg`, `<leader>fw`, `<leader>fb`, and `<leader>fp` instead of browsing manually. Use `<leader>fR` once to learn that pickers can be resumed.

### Day 4: Code Navigation

In a file with LSP support, use `K`, `grr`, `gra`, `[d`, `]d`, `<leader>ld`, and `<leader>lf`. Use `:LspInfo` if a mapping does not appear to work.

### Day 5: Buffers And Sessions

Open several files, move with `<S-h>` and `<S-l>`, select one with `<leader>bp`, close one with `<leader>bd`, make a split, and move with `<C-w>h/j/k/l`. Save a session with `<leader>ws`.

### Day 6: Git Review

Make a small change in a Git repository. Use `]h`, `<leader>hp`, `<leader>hs`, and `<leader>hd`. Open `<leader>lg`, inspect status, then close it with `q`. Do not use `<leader>hR` until you deliberately want to discard work.

### Day 7: Personal Routine

Start a real project with `<leader>fp`. Use Telescope to work, add a `TODO:` comment, navigate it with `]t`, review your Git changes, and restore the session later. Notice which keys you used repeatedly, then keep this guide open with `nvim NEOVIM_GUIDE.md` until they become natural.

## Optional Next Steps

These are useful later, not required now:

| Topic | Why it helps |
| --- | --- |
| Registers | Choose exactly where copied or deleted text goes. Start with `"0p` to paste the most recent yank. |
| Marks | Jump back to important locations. Start with `ma` to mark and `'a` to return. |
| Macros | Record repeated edits with `qa`, perform actions, `q`, then replay with `@a`. |
| Command ranges | Apply commands to selected lines, for example `:10,20s/old/new/g`. |
| Folds | Hide large code sections with `zc`, reopen with `zo`, and toggle with `za`. |

Learn one of these only when a real task makes it useful. The goal is not to become a walking Vim reference; it is to make editing and navigation feel calmer and faster.
