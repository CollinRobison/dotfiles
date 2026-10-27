return {
  "folke/tokyonight.nvim",
  priority = 1000,
  config = function()
    require("tokyonight").setup({
      style = "moon",
      on_colors = function(colors)
        -- Keep comments readable during long sessions.
        colors.comment = "#828bb8"
      end,
    })
  end,
}
