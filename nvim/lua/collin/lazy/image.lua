return {
  "3rd/image.nvim",
  event = { "BufReadPre", "BufNewFile" },
  build = false,
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {
    backend = "kitty",
    processor = "magick_cli",
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        filetypes = { "markdown", "rmd", "quarto" },
      },
      asciidoc = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
      },
      typst = { enabled = true },
      neorg = { enabled = true },
      html = { enabled = true },
      css = { enabled = true },
    },
  },
}
