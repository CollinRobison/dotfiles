return {
  "folke/todo-comments.nvim",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = { "nvim-lua/plenary.nvim" },
  keys = {
    {
      "]t",
      function()
        require("todo-comments").jump_next()
      end,
      desc = "Next todo comment",
    },
    {
      "[t",
      function()
        require("todo-comments").jump_prev()
      end,
      desc = "Previous todo comment",
    },
    {
      "<leader>ft",
      function()
        require("lazy").load({ plugins = { "telescope.nvim" } })
        require("telescope").load_extension("todo-comments")
        vim.cmd("TodoTelescope")
      end,
      desc = "Find todo comments",
    },
    { "<leader>fT", "<cmd>TodoQuickFix<CR>", desc = "Todo comments to quickfix" },
    { "<leader>fL", "<cmd>TodoLocList<CR>", desc = "Todo comments to location list" },
  },
  opts = {
    highlight = {
      after = "",
      before = "",
      comments_only = true,
      keyword = "fg",
    },
    search = {
      args = {
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--hidden",
      },
    },
  },
}
