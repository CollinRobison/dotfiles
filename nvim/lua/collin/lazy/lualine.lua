return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    local colors = require("vague").get_palette()
    local lazy_status = require("lazy.status")
    local session = require("auto-session.lib")

    local function session_name()
      return session.current_session_name(true)
    end

    require("lualine").setup({
      options = {
        theme = {
          normal = {
            a = { bg = colors.parameter, fg = colors.bg, gui = "bold" },
            b = { bg = colors.inactiveBg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
          },
          insert = {
            a = { bg = colors.plus, fg = colors.bg, gui = "bold" },
            b = { bg = colors.inactiveBg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
          },
          visual = {
            a = { bg = colors.constant, fg = colors.bg, gui = "bold" },
            b = { bg = colors.inactiveBg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
          },
          command = {
            a = { bg = colors.warning, fg = colors.bg, gui = "bold" },
            b = { bg = colors.inactiveBg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
          },
          replace = {
            a = { bg = colors.error, fg = colors.bg, gui = "bold" },
            b = { bg = colors.inactiveBg, fg = colors.fg },
            c = { bg = colors.bg, fg = colors.fg },
          },
          inactive = {
            a = { bg = colors.inactiveBg, fg = colors.comment, gui = "bold" },
            b = { bg = colors.inactiveBg, fg = colors.comment },
            c = { bg = colors.bg, fg = colors.comment },
          },
        },
        globalstatus = true,
        section_separators = { left = "", right = "" },
        component_separators = { left = "", right = "" },
        disabled_filetypes = {
          statusline = { "alpha" },
          winbar = { "alpha", "NvimTree" },
        },
        extensions = { "nvim-tree", "lazy" },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = {
          { "filename", path = 1 },
        },
        lualine_x = {
          {
            function()
              return vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
            end,
            icon = "󰉋",
          },
          {
            session_name,
            cond = function()
              local name = session_name()
              return name ~= nil and name ~= ""
            end,
            icon = "󱂬",
          },
          {
            lazy_status.updates,
            cond = lazy_status.has_updates,
            color = { fg = colors.warning },
          },
          "encoding",
          "fileformat",
          "filetype",
        },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
      winbar = {
        lualine_c = {
          { "filename", path = 1 },
        },
      },
      inactive_winbar = {
        lualine_c = {
          { "filename", path = 1 },
        },
      },
    })
  end,
}
