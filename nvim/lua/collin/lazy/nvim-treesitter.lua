return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  build = ":TSUpdate",
  dependencies = {
    "windwp/nvim-ts-autotag",
  },
  config = function()
    local treesitter = require("nvim-treesitter")
    local parsers = {
      "bash",
      "c",
      "c_sharp",
      "cpp",
      "css",
      "dockerfile",
      "go",
      "graphql",
      "html",
      "javascript",
      "json",
      "gitignore",
      "lua",
      "markdown",
      "markdown_inline",
      "prisma",
      "python",
      "query",
      "razor",
      "rust",
      "sql",
      "svelte",
      "toml",
      "tsx",
      "typescript",
      "vim",
      "vimdoc",
      "xml",
      "yaml",
    }

    treesitter.setup()
    vim.treesitter.language.register("json", { "jsonc" })
    treesitter.install(parsers)
    require("nvim-ts-autotag").setup()

    vim.api.nvim_create_autocmd("FileType", {
      callback = function(event)
        if pcall(vim.treesitter.start, event.buf) then
          vim.bo[event.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
