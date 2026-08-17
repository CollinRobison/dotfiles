return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "mason-org/mason.nvim",
    "mason-org/mason-lspconfig.nvim",
    "b0o/SchemaStore.nvim",
  },
  config = function()
    local servers = {
      "bashls",
      "basedpyright",
      "clangd",
      "cssls",
      "dockerls",
      "gopls",
      "graphql",
      "html",
      "jsonls",
      "lemminx",
      "lua_ls",
      "marksman",
      "prismals",
      "roslyn_ls",
      "ruff",
      "rust_analyzer",
      "sqls",
      "svelte",
      "taplo",
      "vimls",
      "vtsls",
      "yamlls",
    }

    require("mason").setup()
    require("mason-lspconfig").setup({
      ensure_installed = servers,
      automatic_enable = false,
    })

    local schemastore = require("schemastore")

    vim.diagnostic.config({
      severity_sort = true,
      signs = true,
      underline = true,
      update_in_insert = false,
      virtual_text = {
        current_line = true,
        prefix = "●",
        source = "if_many",
      },
      float = {
        border = "rounded",
        source = "if_many",
      },
    })

    vim.opt.completeopt = { "menu", "menuone", "noselect" }

    vim.lsp.config("basedpyright", {
      root_markers = {
        "pyproject.toml",
        "pyrightconfig.json",
        "setup.py",
        "setup.cfg",
        "requirements.txt",
        "Pipfile",
        "poetry.lock",
        "uv.lock",
        ".venv",
        ".git",
      },
      settings = {
        basedpyright = {
          analysis = {
            typeCheckingMode = "strict",
          },
        },
      },
    })

    vim.lsp.config("jsonls", {
      settings = {
        json = {
          schemas = schemastore.json.schemas(),
          validate = { enable = true },
        },
      },
    })

    vim.lsp.config("lua_ls", {
      settings = {
        Lua = {
          diagnostics = { globals = { "vim" } },
          runtime = { version = "LuaJIT" },
          telemetry = { enable = false },
          workspace = {
            checkThirdParty = false,
            library = vim.api.nvim_get_runtime_file("", true),
          },
        },
      },
    })

    vim.lsp.config("roslyn_ls", {
      settings = {
        ["csharp|background_analysis"] = {
          dotnet_analyzer_diagnostics_scope = "fullSolution",
          dotnet_compiler_diagnostics_scope = "fullSolution",
        },
        ["csharp|code_lens"] = {
          dotnet_enable_references_code_lens = true,
          dotnet_enable_tests_code_lens = true,
        },
      },
    })

    vim.lsp.config("yamlls", {
      settings = {
        yaml = {
          schemaStore = { enable = false, url = "" },
          schemas = schemastore.yaml.schemas(),
        },
      },
    })

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("collin-lsp-attach", { clear = true }),
      callback = function(event)
        local client = assert(vim.lsp.get_client_by_id(event.data.client_id))

        if client:supports_method("textDocument/completion") then
          vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
        end

        if client:supports_method("textDocument/inlayHint") then
          vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
          vim.keymap.set("n", "<leader>li", function()
            local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf })
            vim.lsp.inlay_hint.enable(not enabled, { bufnr = event.buf })
          end, { buffer = event.buf, desc = "Toggle inlay hints" })
        end

        if client:supports_method("textDocument/codeLens") then
          vim.lsp.codelens.enable(true, { bufnr = event.buf, client_id = client.id })
        end

        vim.keymap.set("n", "<leader>lf", function()
          if vim.bo[event.buf].filetype == "markdown" or vim.bo[event.buf].filetype == "rmd" then
            local ok, conform = pcall(require, "conform")
            if ok then
              conform.format({ async = true, lsp_format = "never" })
              return
            end
          end

          vim.lsp.buf.format({ async = true })
        end, { buffer = event.buf, desc = "Format buffer" })
      end,
    })

    vim.keymap.set("n", "[d", function()
      vim.diagnostic.jump({ count = -1, float = true })
    end, { desc = "Previous diagnostic" })
    vim.keymap.set("n", "]d", function()
      vim.diagnostic.jump({ count = 1, float = true })
    end, { desc = "Next diagnostic" })
    vim.keymap.set("n", "<leader>ld", vim.diagnostic.open_float, { desc = "Show diagnostic" })

    vim.lsp.enable(servers)
  end,
}
