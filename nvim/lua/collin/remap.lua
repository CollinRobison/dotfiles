local which_key = require("which-key")

which_key.add({
 {
    "<leader>nt",
    function()
      require("nvim-tree.api").tree.toggle()
    end,
    desc = "Toggle nvim-tree",
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
  {
    "<leader>nh",
    ":nohl<CR>",
    mode = "n",
    desc = "Clear search highlights",
  },
})
