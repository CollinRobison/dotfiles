return {
  "kdheepak/lazygit.nvim",
  cmd = {
    "LazyGit",
    "LazyGitConfig",
    "LazyGitCurrentFile",
    "LazyGitFilter",
    "LazyGitFilterCurrentFile",
    "LazyGitLog",
  },
  dependencies = { "nvim-lua/plenary.nvim" },
  init = function()
    vim.g.lazygit_floating_window_border_chars = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" }
    vim.g.lazygit_floating_window_scaling_factor = 0.9
    vim.g.lazygit_floating_window_use_plenary = 0
    vim.g.lazygit_floating_window_winblend = 0
  end,
  keys = {
    { "<leader>lg", "<cmd>LazyGit<CR>", desc = "LazyGit dashboard" },
    { "<leader>lG", "<cmd>LazyGitCurrentFile<CR>", desc = "LazyGit current file" },
    { "<leader>lL", "<cmd>LazyGitFilter<CR>", desc = "LazyGit repository log" },
    { "<leader>ll", "<cmd>LazyGitFilterCurrentFile<CR>", desc = "LazyGit file log" },
  },
}
