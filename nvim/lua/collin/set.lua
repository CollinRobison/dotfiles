local opt = vim.opt

vim.cmd.colorscheme("vague")

-- Enable 24-bit GUI colors for themes and UI plugins.
opt.termguicolors = true

-- Persist buffers, layout, working directory, terminals, and local options in sessions.
opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

-- line numbers
opt.number = true
opt.relativenumber = false

-- clipboard
opt.clipboard = "unnamedplus" -- use system clipboard as default register

-- tabs & indents
opt.autoindent = true -- copy indent from current line when starting new one

-- line wrapping
opt.wrap = false -- disable line wrapping

-- search settings
opt.ignorecase = true -- ignore case when searching
opt.smartcase = true -- if you include mixed case in your search, assumes you want case-sensitive

-- cursor line
opt.cursorline = true -- highlight the current cursor line

-- backspace
opt.backspace = "indent,eol,start" -- allow backspace on indent, end of line or insert mode start position

