return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  keys = {
    {
      "]h",
      function()
        require("gitsigns").nav_hunk("next")
      end,
      desc = "Next hunk",
    },
    {
      "[h",
      function()
        require("gitsigns").nav_hunk("prev")
      end,
      desc = "Previous hunk",
    },
    { "<leader>hs", function() require("gitsigns").stage_hunk() end, desc = "Stage hunk" },
    { "<leader>hr", function() require("gitsigns").reset_hunk() end, desc = "Reset hunk" },
    {
      "<leader>hs",
      function()
        require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end,
      mode = "x",
      desc = "Stage selection",
    },
    {
      "<leader>hr",
      function()
        require("gitsigns").reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
      end,
      mode = "x",
      desc = "Reset selection",
    },
    { "<leader>hS", function() require("gitsigns").stage_buffer() end, desc = "Stage buffer" },
    { "<leader>hR", function() require("gitsigns").reset_buffer() end, desc = "Reset buffer" },
    { "<leader>hU", function() require("gitsigns").reset_buffer_index() end, desc = "Unstage buffer" },
    { "<leader>hp", function() require("gitsigns").preview_hunk() end, desc = "Preview hunk" },
    { "<leader>hi", function() require("gitsigns").preview_hunk_inline() end, desc = "Preview hunk inline" },
    {
      "<leader>hb",
      function()
        require("gitsigns").blame_line({ full = true })
      end,
      desc = "Blame line",
    },
    { "<leader>hB", function() require("gitsigns").toggle_current_line_blame() end, desc = "Toggle line blame" },
    { "<leader>uw", function() require("gitsigns").toggle_word_diff() end, desc = "Toggle Git word diff" },
    { "<leader>hd", function() require("gitsigns").diffthis() end, desc = "Diff against index" },
    {
      "<leader>hD",
      function()
        require("gitsigns").diffthis("HEAD")
      end,
      desc = "Diff against HEAD",
    },
    { "<leader>hq", function() require("gitsigns").setqflist() end, desc = "Hunks to quickfix" },
    {
      "<leader>hQ",
      function()
        require("gitsigns").setqflist("all")
      end,
      desc = "Repository hunks to quickfix",
    },
    {
      "<leader>hl",
      function()
        require("gitsigns").setloclist(0)
      end,
      desc = "Hunks to location list",
    },
    { "ih", function() require("gitsigns").select_hunk() end, mode = { "o", "x" }, desc = "Select hunk" },
  },
  opts = {
    attach_to_untracked = true,
    current_line_blame = false,
    current_line_blame_opts = {
      delay = 750,
      virt_text_pos = "eol",
    },
    diff_opts = {
      internal = true,
    },
    preview_config = {
      border = "rounded",
      relative = "cursor",
      row = 1,
      col = 1,
      style = "minimal",
    },
    signs = {
      add = { text = "▎", show_count = true },
      change = { text = "▎", show_count = true },
      delete = { text = "▁", show_count = true },
      topdelete = { text = "▔", show_count = true },
      changedelete = { text = "▎", show_count = true },
      untracked = { text = "┆", show_count = true },
    },
    signs_staged = {
      add = { text = "▎", show_count = true },
      change = { text = "▎", show_count = true },
      delete = { text = "▁", show_count = true },
      topdelete = { text = "▔", show_count = true },
      changedelete = { text = "▎", show_count = true },
    },
  },
}
