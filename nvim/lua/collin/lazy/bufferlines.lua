return {
  "akinsho/bufferline.nvim",
  version = "*",
  event = "VeryLazy",
  dependencies = "nvim-tree/nvim-web-devicons",
  keys = {
    { "<S-h>", "<cmd>BufferLineCyclePrev<CR>", desc = "Previous buffer" },
    { "<S-l>", "<cmd>BufferLineCycleNext<CR>", desc = "Next buffer" },
    { "<leader>bp", "<cmd>BufferLinePick<CR>", desc = "Pick buffer" },
    { "<leader>bd", "<cmd>bdelete<CR>", desc = "Close buffer" },
  },
  opts = {
    options = {
      mode = "buffers",
      separator_style = "slant",
      always_show_bufferline = false,
      offsets = {
        {
          filetype = "NvimTree",
          text = "File Explorer",
          text_align = "left",
          separator = true,
        },
      },
    },
  },
}
