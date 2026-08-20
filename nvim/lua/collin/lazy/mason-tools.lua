return {
  "mason-org/mason.nvim",
  lazy = false,
  dependencies = {
    "mason-org/mason-lspconfig.nvim",
    "jay-babu/mason-nvim-dap.nvim",
  },
  config = function()
    require("mason").setup()
    require("mason-nvim-dap").setup({
      -- Adapter installation is opt-in. Mason should not silently replace a
      -- project's own toolchain or Python environment.
      ensure_installed = {},
      automatic_installation = false,
    })

    vim.api.nvim_create_user_command("MasonInstallDebugAdapters", function()
      vim.cmd("MasonInstall debugpy js-debug-adapter delve codelldb netcoredbg")
    end, {
      desc = "Install optional DAP adapters through Mason",
    })
  end,
}
