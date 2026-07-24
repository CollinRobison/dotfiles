return {
  "nvim-telescope/telescope.nvim",
  cmd = "Telescope",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    "nvim-telescope/telescope-project.nvim",
  },
  keys = {
    { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
    { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Find text" },
    { "<leader>fw", "<cmd>Telescope grep_string<CR>", desc = "Find word under cursor" },
    { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find buffers" },
    { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "Find recent files" },
    { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Find help" },
    { "<leader>fk", "<cmd>Telescope keymaps<CR>", desc = "Find keymaps" },
    { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Find diagnostics" },
    { "<leader>f/", "<cmd>Telescope current_buffer_fuzzy_find<CR>", desc = "Find in buffer" },
    { "<leader>fR", "<cmd>Telescope resume<CR>", desc = "Resume last picker" },
    { "<leader>fp", "<cmd>Telescope project project<CR>", desc = "Find project" },
    { "<leader>gc", "<cmd>Telescope git_commits<CR>", desc = "Git commits" },
    { "<leader>gb", "<cmd>Telescope git_branches<CR>", desc = "Git branches" },
    { "<leader>gs", "<cmd>Telescope git_status<CR>", desc = "Git status" },
  },
  opts = {
    defaults = {
      file_ignore_patterns = {},
      vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
        "--hidden",
      },
    },
    pickers = {
      find_files = {
        hidden = true,
      },
    },
    extensions = {
      project = {
        base_dirs = {
          { path = vim.fn.expand("~/Repos"), max_depth = 4 },
        },
        ignore_missing_dirs = true,
        search_by = { "title", "path" },
        on_project_selected = function(prompt_bufnr)
          local project_actions = require("telescope._extensions.project.actions")
          local project_path = project_actions.get_selected_path(prompt_bufnr)

          require("telescope.actions").close(prompt_bufnr)
          vim.cmd("tcd " .. vim.fn.fnameescape(project_path))

          vim.schedule(function()
            local tree = require("nvim-tree.api").tree
            tree.change_root(project_path)
            tree.open()
            tree.focus()
          end)
        end,
      },
    },
  },
  config = function(_, opts)
    local telescope = require("telescope")
    telescope.setup(opts)
    pcall(telescope.load_extension, "fzf")
    pcall(telescope.load_extension, "project")
  end,
}
