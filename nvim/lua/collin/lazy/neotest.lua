return {
  "nvim-neotest/neotest",
  event = "VeryLazy",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-neotest/neotest-python",
    "akinsho/neotest-go",
    "rouge8/neotest-rust",
    "marilari88/neotest-vitest",
    "haydenmeade/neotest-jest",
    "orjangj/neotest-ctest",
    "nvim-neotest/neotest-vim-test",
    "vim-test/vim-test",
    "CollinRobison/neotest-dotnet",
  },
  config = function()
    local neotest_adapters = {}

    local function package_has_dependency(path, dependency)
      local stat = vim.uv.fs_stat(path)
      local search_path = stat and stat.type == "directory" and path or vim.fs.dirname(path)
      local package_path = vim.fs.find("package.json", {
        path = search_path,
        upward = true,
        type = "file",
      })[1]
      if not package_path then
        return false
      end

      local ok, package_json = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(package_path), "\n"))
      end)
      if not ok or type(package_json) ~= "table" then
        return false
      end

      for _, dependency_type in ipairs({ "dependencies", "devDependencies", "peerDependencies" }) do
        if package_json[dependency_type] and package_json[dependency_type][dependency] then
          return true
        end
      end
      return false
    end

    local function add_adapter(name, setup)
      local ok, adapter = pcall(setup)
      if ok then
        table.insert(neotest_adapters, adapter)
      else
        vim.notify(("Neotest adapter %s is unavailable: %s"):format(name, adapter), vim.log.levels.WARN)
      end
    end

    add_adapter("Python", function()
      return require("neotest-python")({
        runner = "pytest",
        python = function(root)
          if vim.fn.executable(root .. "/.venv/bin/python") == 1 then
            return root .. "/.venv/bin/python"
          end
          if vim.uv.fs_stat(root .. "/uv.lock") and vim.fn.executable("uv") == 1 then
            return { "uv", "run", "python" }
          end
          return vim.fn.exepath("python3") ~= "" and vim.fn.exepath("python3") or "python"
        end,
      })
    end)

    add_adapter("Go", function()
      return require("neotest-go")({
        recursive_run = true,
      })
    end)

    add_adapter("Rust", function()
      return require("neotest-rust")({
        dap_adapter = "codelldb",
      })
    end)

    add_adapter("Vitest", function()
      return require("neotest-vitest")
    end)

    add_adapter("Jest", function()
      local jest = require("neotest-jest")({
        -- Avoid the adapter's synchronous glob lookup inside Neotest's fast event.
        -- Jest uses its default configuration when no project config is present.
        jestConfigFile = function()
          return nil
        end,
        isTestFile = function(path)
          return not package_has_dependency(path, "vitest")
            and require("neotest-jest.jest-util").defaultIsTestFile(path)
        end,
      })
      local default_root = jest.root
      jest.root = function(path)
        if package_has_dependency(path, "vitest") then
          return nil
        end
        return default_root(path)
      end
      return jest
    end)

    add_adapter("CTest", function()
      return require("neotest-ctest").setup({
        dap_adapter = "codelldb",
      })
    end)

    add_adapter("vim-test fallback", function()
      return require("neotest-vim-test")({
        ignore_filetypes = {
          "python",
          "go",
          "rust",
          "javascript",
          "javascriptreact",
          "typescript",
          "typescriptreact",
          "svelte",
          "cs",
          "csharp",
          "c",
          "cpp",
        },
      })
    end)

    add_adapter(".NET", function()
      return require("neotest-dotnet")({
        discovery_root = "project",
        dap = {
          adapter_name = "netcoredbg",
        },
      })
    end)

    local neotest = require("neotest")
    neotest.setup({
      adapters = neotest_adapters,
      summary = {
        enabled = true,
        follow = true,
        expand_errors = true,
      },
      output = {
        enabled = true,
        open_on_run = false,
      },
      status = {
        enabled = true,
        signs = true,
        virtual_text = true,
      },
    })

    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { desc = desc })
    end

    map("<leader>tn", neotest.run.run, "Run nearest test")
    map("<leader>tf", function()
      neotest.run.run(vim.fn.expand("%"))
    end, "Run current file")
    map("<leader>ta", function()
      neotest.run.run(vim.fn.getcwd())
    end, "Run test suite")
    map("<leader>td", function()
      neotest.run.run({ strategy = "dap" })
    end, "Debug nearest test")
    map("<leader>ts", neotest.summary.toggle, "Toggle test summary")
    map("<leader>to", neotest.output.open, "Show test output")
    map("<leader>tx", neotest.run.stop, "Stop test")
    map("<leader>tv", "<cmd>TestNearest<CR>", "Fallback: run nearest test")
    map("<leader>tV", "<cmd>TestFile<CR>", "Fallback: run current file")
    map("<leader>tA", "<cmd>TestSuite<CR>", "Fallback: run test suite")
  end,
}
