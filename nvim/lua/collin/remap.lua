local which_key = require("which-key")

which_key.add({
  {
    "<leader>e",
    function()
      require("nvim-tree.api").tree.toggle()
    end,
    desc = "Open file explorer",
    silent = true,
  },
  {
    "<F2>",
    function()
      vim.wo.number = not vim.wo.number
    end,
    desc = "Toggle line numbers",
  },
  {
    "<F3>",
    function()
      vim.wo.relativenumber = not vim.wo.relativenumber
    end,
    desc = "Toggle relative line numbers",
  },
})
