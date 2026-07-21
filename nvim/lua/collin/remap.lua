local which_key = require("which-key")

which_key.add({
  {
    "<leader>e",
    vim.cmd.Ex,
    desc = "Open file explorer",
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
