return {
  "lukas-reineke/indent-blankline.nvim",
  main = "ibl",
  event = { "BufReadPre", "BufNewFile" },
  keys = {
    { "<leader>ui", "<cmd>IBLToggle<CR>", desc = "Toggle indent guides" },
    { "<leader>us", "<cmd>IBLToggleScope<CR>", desc = "Toggle indent scope" },
  },
  config = function()
    local hooks = require("ibl.hooks")

    hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
      local colors = require("vague").get_palette()
      vim.api.nvim_set_hl(0, "IblIndentMuted", { fg = colors.line })
      vim.api.nvim_set_hl(0, "IblScopePurple", { fg = colors.parameter })
    end)

    require("ibl").setup({
      indent = {
        char = "▏",
        highlight = "IblIndentMuted",
      },
      whitespace = {
        remove_blankline_trail = true,
      },
      scope = {
        char = "▎",
        highlight = "IblScopePurple",
        show_start = true,
        show_end = true,
      },
    })
  end,
}
