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
| UI | `<leader>ui` | Toggle indent guides. |
| UI | `<leader>us` | Toggle indent scope. |
| UI | `<leader>ua` | Toggle autopairs. |
| UI | `<leader>uw` | Toggle Git word diff. |
| Autopairs | `<M-e>` | FastWrap in Insert mode. |
| Discovery | `<leader>?` | Show buffer-local mappings. |

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
