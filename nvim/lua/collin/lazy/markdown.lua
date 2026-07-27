local function cspell_words(settings_path)
  local content = table.concat(vim.fn.readfile(settings_path), "\n")
  local word_list = content:match('"cSpell%.words"%s*:%s*(%b[])')
  local words = {}

  if not word_list then
    return words
  end

  for word in word_list:gmatch('"([^"\\]+)"') do
    table.insert(words, word)
  end

  return words
end

local function cspell_settings(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local directory = vim.fs.dirname(path)

  while directory do
    local settings = directory .. "/.vscode/settings.json"
    if vim.uv.fs_stat(settings) then
      return settings
    end

    local parent = vim.fs.dirname(directory)
    if parent == directory then
      return nil
    end
    directory = parent
  end
end

local function configure_spell(buf)
  local personal_spellfile = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"
  local spellfiles = { personal_spellfile }
  local settings = cspell_settings(buf)

  vim.fn.mkdir(vim.fs.dirname(personal_spellfile), "p")

  if settings then
    local words = cspell_words(settings)
    if #words > 0 then
      local cache_dir = vim.fn.stdpath("cache") .. "/cspell"
      local project_spellfile = cache_dir .. "/" .. vim.fn.sha256(settings) .. ".utf-8.add"

      vim.fn.mkdir(cache_dir, "p")
      vim.fn.writefile(words, project_spellfile)
      table.insert(spellfiles, project_spellfile)
    end
  end

  vim.opt_local.spell = true
  vim.opt_local.spelllang = { "en_us" }
  vim.opt_local.spellfile = spellfiles
end

local function toggle_format_on_save(buf)
  vim.b[buf].markdown_format_on_save = not vim.b[buf].markdown_format_on_save
  vim.notify(
    "Markdown format on save " .. (vim.b[buf].markdown_format_on_save and "enabled" or "disabled"),
    vim.log.levels.INFO
  )
end

local function add_all_spelling_words(buf)
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local wrapscan = vim.o.wrapscan
  local added = {}

  vim.o.wrapscan = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  while true do
    vim.cmd("silent! normal! ]s")

    local word = vim.fn.spellbadword()[1]
    if word == "" then
      break
    end

    vim.cmd("normal! zg")
    added[word] = true
  end

  vim.o.wrapscan = wrapscan
  vim.api.nvim_win_set_cursor(win, cursor)
  vim.notify("Added " .. vim.tbl_count(added) .. " words to the personal dictionary", vim.log.levels.INFO)
end

local function configure_markdown_buffer(buf)
  configure_spell(buf)
  vim.opt_local.wrap = true
  vim.opt_local.linebreak = true
  vim.opt_local.breakindent = true

  if vim.b[buf].markdown_format_on_save == nil then
    vim.b[buf].markdown_format_on_save = false
  end

  local opts = { buffer = buf }
  vim.keymap.set("n", "<leader>mp", "<cmd>Markview toggle<CR>", vim.tbl_extend("force", opts, { desc = "Toggle preview" }))
  vim.keymap.set("n", "<leader>mh", "<cmd>Markview hybridToggle<CR>", vim.tbl_extend("force", opts, { desc = "Toggle hybrid preview" }))
  vim.keymap.set("n", "<leader>ms", "<cmd>Markview splitToggle<CR>", vim.tbl_extend("force", opts, { desc = "Toggle preview split" }))
  vim.keymap.set("n", "<leader>ml", "<cmd>MkdnFollowLink<CR>", vim.tbl_extend("force", opts, { desc = "Follow link" }))
  vim.keymap.set("n", "<leader>mn", "<cmd>MkdnNextLink<CR>", vim.tbl_extend("force", opts, { desc = "Next link" }))
  vim.keymap.set("n", "<leader>mN", "<cmd>MkdnPrevLink<CR>", vim.tbl_extend("force", opts, { desc = "Previous link" }))
  vim.keymap.set("n", "<leader>mt", "<cmd>MkdnTableFormat<CR>", vim.tbl_extend("force", opts, { desc = "Format table" }))
  vim.keymap.set({ "n", "v" }, "<leader>mc", "<cmd>MkdnToggleToDo<CR>", vim.tbl_extend("force", opts, { desc = "Toggle task" }))
  vim.keymap.set("n", "<leader>mf", "<cmd>MkdnFoldSection<CR>", vim.tbl_extend("force", opts, { desc = "Fold section" }))
  vim.keymap.set("n", "<leader>mF", "<cmd>MkdnUnfoldSection<CR>", vim.tbl_extend("force", opts, { desc = "Unfold section" }))
  vim.keymap.set("n", "<leader>mw", "zg", vim.tbl_extend("force", opts, { desc = "Add spelling word" }))
  vim.keymap.set("n", "<leader>mW", function()
    add_all_spelling_words(buf)
  end, vim.tbl_extend("force", opts, { desc = "Add all spelling words" }))
  vim.keymap.set("n", "<leader>ma", function()
    toggle_format_on_save(buf)
  end, vim.tbl_extend("force", opts, { desc = "Toggle format on save" }))
  vim.keymap.set("n", "<leader>md", function()
    require("lint").try_lint()
  end, vim.tbl_extend("force", opts, { desc = "Lint Markdown" }))
end

return {
  {
    "OXY2DEV/markview.nvim",
    lazy = false,
    opts = {
      preview = {
        icon_provider = "devicons",
        modes = { "n", "no", "v", "i", "c" },
        hybrid_modes = { "n", "no", "v", "i" },
      },
    },
  },
  {
    "jakewvincent/mkdnflow.nvim",
    ft = { "markdown", "rmd" },
    opts = {
      links = {
        style = "wiki",
      },
      path_resolution = {
        primary = "current",
        fallback = "current",
        sync_cwd = false,
      },
      tables = {
        format_on_move = true,
        auto_extend_rows = true,
        auto_extend_cols = true,
      },
      mappings = {
        MkdnEnter = { { "n", "i", "v" }, "<CR>" },
        MkdnGoBack = false,
        MkdnGoForward = false,
        MkdnMoveSource = false,
        MkdnDestroyLink = false,
        MkdnTagSpan = false,
        MkdnYankAnchorLink = false,
        MkdnYankFileAnchorLink = false,
        MkdnIncreaseHeading = false,
        MkdnDecreaseHeading = false,
        MkdnIncreaseHeadingOp = false,
        MkdnDecreaseHeadingOp = false,
        MkdnToggleToDo = false,
        MkdnUpdateNumbering = false,
        MkdnTableNewRowBelow = false,
        MkdnTableNewRowAbove = false,
        MkdnTableNewColAfter = false,
        MkdnTableNewColBefore = false,
        MkdnTableDeleteRow = false,
        MkdnTableDeleteCol = false,
        MkdnTableAlignLeft = false,
        MkdnTableAlignRight = false,
        MkdnTableAlignCenter = false,
        MkdnTableAlignDefault = false,
        MkdnFoldSection = false,
        MkdnUnfoldSection = false,
        MkdnCreateLinkFromClipboard = false,
      },
      on_attach = function(buf)
        configure_markdown_buffer(buf)
      end,
    },
  },
  {
    "stevearc/conform.nvim",
    ft = { "markdown", "rmd" },
    opts = {
      formatters_by_ft = {
        markdown = { "prettier" },
        rmd = { "prettier" },
      },
      format_on_save = function(buf)
        if vim.b[buf].markdown_format_on_save then
          return { lsp_format = "never", timeout_ms = 1000 }
        end
      end,
    },
  },
  {
    "mfussenegger/nvim-lint",
    ft = { "markdown", "rmd" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft.markdown = { "markdownlint-cli2" }
      lint.linters_by_ft.rmd = { "markdownlint-cli2" }

      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("collin-markdown-lint", { clear = true }),
        callback = function(args)
          if vim.bo[args.buf].filetype == "markdown" or vim.bo[args.buf].filetype == "rmd" then
            lint.try_lint()
          end
        end,
      })
    end,
  },
}
