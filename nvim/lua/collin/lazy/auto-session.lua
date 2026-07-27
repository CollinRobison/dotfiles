return {
  "rmagatti/auto-session",
  lazy = false,
  keys = {
    { "<leader>wr", "<cmd>AutoSession search<CR>", desc = "Find session" },
    { "<leader>ws", "<cmd>AutoSession save<CR>", desc = "Save session" },
  },
  opts = {
    bypass_save_filetypes = { "alpha", "NvimTree" },
    cwd_change_handling = true,
    pre_save_cmds = {
      function()
        local tree = require("nvim-tree.api").tree
        if tree.is_visible() then
          tree.close()
        end
      end,
    },
  },
}
