"""Editable teaching content reconstructed from the original Neovim field guide.

Keep this human-written material concise, practical, and independent of a plugin's
current key names. The generator inserts current configuration mappings separately.
"""

CORE_SECTIONS = [
    ("Move precisely, then act", "Normal mode • motions work after d / c / y / v", [
        ("Character, line & screen", [("h j k l", "Left, down, up, right."), ("0 / ^ / $", "Line start / first nonblank / line end."), ("H M L", "Top / middle / bottom visible screen line."), ("Ctrl-u / Ctrl-d", "Half-page up / down."), ("zt zz zb", "Place cursor line at top / center / bottom.")]),
        ("Words, paragraphs & file", [("w b e", "Next word start / previous word start / word end."), ("W B E", "Same by whitespace-separated WORD."), ("{ }", "Previous / next paragraph."), ("gg / G", "First / last line of the file."), (":42 / 42G", "Go to line 42."), ("%", "Jump between matching delimiters."), ("Ctrl-o / Ctrl-i", "Older / newer jump location.")]),
        ("Find on one line", [("f x / F x", "Find character x forward / backward; land on it."), ("t x / T x", "Move until just before x, forward / backward."), ("; / ,", "Repeat the latest find in the same / opposite direction."), ("* / #", "Search word under cursor forward / backward.")]),
    ], "Counts repeat the next command: 3w moves three words; 5dd deletes five lines; d2j deletes the current plus next two lines; 2ci( changes inside the next two parenthesized areas."),
    ("Edit with operators, text objects & registers", "Normal / Visual / Insert modes", [
        ("Operators: the verbs", [("d", "Delete (also copies to a register)."), ("c", "Change: delete, then enter Insert mode."), ("y", "Yank: copy to a register."), ("> / <", "Indent right / left; add = to auto-indent."), ("g~ / gu / gU", "Toggle case / lower / upper."), ("=", "Auto-format indentation using filetype rules.")]),
        ("Text objects: the nouns", [("iw / aw", "Inner word / word including surrounding space."), ("i\" / a\"", "Inside quotes / quotes plus contents."), ("i( i[ i{", "Inside parentheses / brackets / braces."), ("a( a[ a{", "Object including delimiters."), ("ip / ap", "Inner paragraph / paragraph plus blank space.")]),
        ("Insert, paste & repeat", [("i I / a A", "Insert at cursor / first text; append / line end."), ("o / O", "Open a line below / above and insert."), ("p / P", "Paste after / before cursor or line."), ("u / Ctrl-r", "Undo / redo."), (".", "Repeat the last change.")]),
    ], "Read keys as a sentence: dw deletes to the next word; ci\" changes inside quotes; ya( copies parentheses and contents. Fast line forms: dd, cc, yy, >>."),
    ("Search, replace, save & get unstuck", "Search is local • Telescope searches projects", [
        ("Search within this file", [("/text Enter / ?text Enter", "Search forward / backward."), ("n / N", "Next / previous match."), (":noh", "Clear highlighting, not the search pattern."), ("/\\cword / /\\Cword", "Force case-insensitive / case-sensitive search."), ("/\\Vliteral", "Search punctuation literally."), ("q/", "Open editable search history.")]),
        ("Substitute", [(":s/old/new/", "Replace first match on this line."), (":s/old/new/g", "Replace every match on this line."), (":%s/old/new/gc", "Whole file: replace all and confirm each."), (":'<,'>s/old/new/g", "Replace only the current visual selection."), ("& / :%&", "Repeat the latest substitute on this line / whole file.")]),
        ("Help & recovery", [(":help {topic}", "Open built-in documentation."), (":map / :nmap / :imap", "Inspect mappings by mode."), (":checkhealth", "Diagnose Neovim, providers, and plugins."), (":messages", "Show recent notifications and errors."), (":w :q :wq :q!", "Save / quit / save+quit / force quit.")]),
    ], "Your setup uses ignorecase + smartcase: lowercase searches ignore case; adding any capital makes the search case-sensitive."),
    ("Buffers, windows, tabs & lists", "Think: buffer = file in memory • window = view", [
        ("Buffers", [(":ls / :buffers", "List open buffers."), (":b name", "Switch by partial buffer name."), (":bnext / :bprev", "Next / previous buffer."), (":bdelete", "Close buffer without necessarily closing its window.")]),
        ("Windows", [(":split / :vsplit", "Horizontal / vertical split."), ("Ctrl-w h/j/k/l", "Move focus between splits."), ("Ctrl-w c / Ctrl-w o", "Close current / keep only current window."), ("Ctrl-w =", "Equalize split sizes.")]),
        ("Tabs, folds & lists", [(":tabnew / gt / gT", "New tab page / next / previous tab."), ("za / zR / zM", "Toggle fold / open all / close all."), (":copen / :cnext", "Open quickfix / next project-wide result."), (":lopen", "Open location list for this window.")]),
    ], "Use Space f f for file names, Space f g for project text, / for the current file, and Space f / for fuzzy filtering inside the current buffer."),
    ("Git, diagnostics, LSP & completion", "Some keys require the noted context", [
        ("Choose the right Git tool", [("Space h …", "Act on one changed hunk: stage, reset, preview, blame, diff."), ("Space g …", "Find Git information through Telescope."), ("Space l g", "Open the full LazyGit workflow.")]),
        ("Diagnostics & language features", [("[d / ]d", "Previous / next diagnostic; read its message."), ("Space l d", "Show the full diagnostic at the cursor."), ("Space l f", "Format the current LSP buffer; Markdown can use Prettier."), ("Space l i", "Toggle inlay hints when the server supports them.")]),
        ("Completion & snippets", [("Tab / Shift-Tab", "Jump forward / backward through an active snippet; otherwise type a tab."), ("Ctrl-n / Ctrl-p", "Next / previous built-in completion candidate."), ("Ctrl-y / Ctrl-e", "Accept / cancel a built-in completion candidate."), ("Ctrl-x Ctrl-o", "Request omnifunc completion where supported.")]),
    ], "Diagnostic means an editor-reported error, warning, or hint. LSP is the language-aware engine that supplies diagnostics, formatting, completion, navigation, and more."),
    ("Markdown, TODOs & writing tools", "Markdown / R Markdown mappings appear only in those buffers", [
        ("Markdown workflow", [("Preview", "Rendered, hybrid, or split preview helps read while editing."), ("Links", "Follow the current link or move through nearby links."), ("Tables & tasks", "Format a table or toggle a task checkbox."), ("Writing hygiene", "Project spell words, format-on-save, table mode, and linting are configured per project.")]),
        ("TODO discovery", [("TODO / FIX / FIXME / HACK", "Use clear comment markers so they are searchable."), ("Quickfix / location list", "Send discovered TODOs to a navigable list."), ("Autopairs", "Matching delimiters are configurable and intentionally disabled in picker/commit contexts.")]),
    ], "Markdown buffers automatically enable US English spell checking, soft wrapping, line breaks, and break indentation in this setup."),
    ("Registers, visual mode & block edits", "Normal / Visual modes", [
        ("Registers: where copied text lives", [("\"0", "Latest yank; \"0p pastes the last copied text."), ("\"+", "System clipboard in this setup."), ("\"a", "Named register: \"ayy stores a line; \"ap pastes it."), ("\"_", "Black-hole register: delete without replacing the clipboard."), (":reg", "Inspect copied text and registers.")]),
        ("Visual mode", [("v / V", "Select characters / whole lines, then use an operator."), ("Ctrl-v", "Select a rectangle; I inserts on every selected line after Esc."), ("gv", "Reselect the previous visual selection."), ("~", "Swap selected text’s case."), ("J / gJ", "Join lines with / without adding a space.")]),
    ], "Your configuration uses unnamedplus, so ordinary yank, delete, and paste already share the system clipboard."),
    ("Sessions, dashboard & personal display", "Dashboard-only keys work on the Alpha start screen", [
        ("Sessions", [("Find session", "Restore a saved workspace."), ("Save session", "Persist the current layout and buffers."), ("What is saved", "Buffers, layout, current directory, terminals, folds, tab pages, and local options.")]),
        ("Dashboard", [("New file", "Start an empty editing buffer."), ("File / recent / text / projects", "Start common Telescope workflows from the dashboard."), ("Explorer / sessions / LazyGit", "Open a workspace tool before entering an editing buffer."), ("Plugin manager / quit", "Maintain plugins or exit Neovim.")]),
        ("Personal display", [("F2 / F3", "Toggle absolute / relative line numbers."), ("Clear highlighting", "Remove the visual highlight of the last search."), ("Indent guides", "Toggle indentation and its scope highlight."), ("Autopairs", "Toggle automatic bracket and quote pairing.")]),
    ], "Dashboard shortcuts are intentionally context-labeled in the generated appendix: use them from the Alpha start screen, not from an editing buffer."),
    ("Testing, debugging & code navigation", "Use context-aware tools to inspect and change behavior safely", [
        ("Testing loop", [("Run nearest test", "Start with the test closest to the cursor."), ("Run file / suite", "Widen scope after the nearest test is useful."), ("Test output", "Open output when a result needs diagnosis."), ("Toggle summary", "Keep test state visible while editing.")]),
        ("Debugging loop", [("Toggle breakpoint", "Mark the next place execution should pause."), ("Continue", "Run to the next breakpoint."), ("Step over / into / out", "Move through execution without losing the current state."), ("Inspect UI", "Open debugger panels for variables, stack, and console.")]),
        ("Code navigation", [("Definition / references", "Jump to where a symbol is defined or used."), ("Rename", "Apply a language-aware rename through the LSP."), ("Code action", "See available fixes and refactors."), ("Diagnostics", "Move through editor-reported problems before changing code.")]),
    ], "The complete appendix has the exact current keys. This page teaches the workflow first so it remains useful even when those keys evolve."),
]

INDEX_PROMPTS = [
    ("Files & project navigation", "find files, project text, recent files, buffers, help, keymaps, explorer"),
    ("Editing", "change, delete, copy, paste, repeat, register, text object, visual block"),
    ("Code help", "diagnostic, format, completion, inlay hint, LSP, snippet"),
    ("Git", "hunk, stage, reset, blame, diff, branch, commit, LazyGit"),
    ("Writing", "Markdown, link, preview, table, spell, TODO, lint"),
]
