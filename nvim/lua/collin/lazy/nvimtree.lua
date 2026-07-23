return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    {
      "<leader>nt",
      function()
        require("nvim-tree.api").tree.toggle()
      end,
      desc = "Toggle nvim-tree",
      silent = true,
    },
    {
      "<leader>nn",
      function()
        require("nvim-tree.api").tree.focus()
      end,
      desc = "Focus nvim-tree",
      silent = true,
    },
    {
      "<leader>nf",
      function()
        require("nvim-tree.api").tree.find_file({ open = true, focus = true })
      end,
      desc = "Reveal current file",
      silent = true,
    },
    {
      "<leader>nr",
      function()
        require("nvim-tree.api").tree.reload()
      end,
      desc = "Refresh nvim-tree",
      silent = true,
    },
    {
      "<leader>nc",
      function()
        require("nvim-tree.api").tree.collapse_all()
      end,
      desc = "Collapse nvim-tree",
      silent = true,
    },
    {
      "<leader>ne",
      function()
        require("nvim-tree.api").tree.expand_all()
      end,
      desc = "Expand nvim-tree",
      silent = true,
    },
  },
  config = function()
    require("nvim-tree").setup(
      {
        filters = {
          dotfiles = false,
          git_ignored = false
        }
      }
    )
  end
}
