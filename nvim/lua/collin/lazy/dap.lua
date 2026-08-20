return {
  "mfussenegger/nvim-dap",
  event = "VeryLazy",
  dependencies = {
    "rcarriga/nvim-dap-ui",
    "nvim-neotest/nvim-nio",
    "theHamsta/nvim-dap-virtual-text",
  },
  config = function()
    local dap = require("dap")
    local dapui = require("dapui")

    local function notify_missing(label, command)
      vim.notify(
        ("%s is not available. Install `%s` or use :MasonInstallDebugAdapters."):format(label, command),
        vim.log.levels.WARN
      )
    end

    local function executable(command)
      local path = vim.fn.exepath(command)
      if path == "" then
        return nil
      end
      return path
    end

    local function executable_adapter(label, command, args)
      return function(callback)
        local path = executable(command)
        if not path then
          notify_missing(label, command)
          return
        end

        callback({
          type = "executable",
          command = path,
          args = args,
        })
      end
    end

    local function server_adapter(label, command, args)
      return function(callback)
        local path = executable(command)
        if not path then
          notify_missing(label, command)
          return
        end

        callback({
          type = "server",
          host = "127.0.0.1",
          port = "${port}",
          executable = {
            command = path,
            args = args,
          },
        })
      end
    end

    local function python_command()
      local root = vim.fs.root(0, {
        "pyproject.toml",
        "uv.lock",
        "poetry.lock",
        "pyrightconfig.json",
        ".git",
      })

      if root then
        local virtualenv = root .. "/.venv/bin/python"
        if vim.fn.executable(virtualenv) == 1 then
          return virtualenv
        end
      end

      return executable("python3") or executable("python")
    end

    dap.adapters.debugpy = function(callback)
      local python = python_command()
      if not python then
        notify_missing("Python", "python3")
        return
      end

      local result = vim.system({ python, "-c", "import debugpy" }, { text = true }):wait()
      if result.code ~= 0 then
        vim.notify(
          ("debugpy is not installed in %s. Install it in the project environment."):format(python),
          vim.log.levels.WARN
        )
        return
      end

      callback({
        type = "executable",
        command = python,
        args = { "-m", "debugpy.adapter" },
      })
    end

    dap.adapters["pwa-node"] = server_adapter("JavaScript debug adapter", "js-debug-adapter", {
      "${port}",
    })
    dap.adapters["pwa-chrome"] = server_adapter("JavaScript debug adapter", "js-debug-adapter", {
      "${port}",
    })
    dap.adapters.delve = function(callback)
      local path = executable("dlv")
      if not path then
        notify_missing("Delve", "dlv")
        return
      end

      callback({
        type = "server",
        host = "127.0.0.1",
        port = "${port}",
        executable = {
          command = path,
          args = { "dap", "-l", "127.0.0.1:${port}" },
        },
      })
    end
    dap.adapters.codelldb = function(callback)
      local path = executable("codelldb")
      if not path then
        notify_missing("CodeLLDB", "codelldb")
        return
      end

      callback({
        type = "server",
        host = "127.0.0.1",
        port = "${port}",
        executable = {
          command = path,
          args = { "--port", "${port}" },
        },
      })
    end
    dap.adapters.netcoredbg = executable_adapter(".NET debugger", "netcoredbg", {
      "--interpreter=vscode",
    })

    dap.configurations.python = {
      {
        type = "debugpy",
        request = "launch",
        name = "Python: launch file",
        program = "${file}",
        python = python_command,
        console = "integratedTerminal",
        justMyCode = true,
      },
    }

    local javascript_configurations = {
      {
        type = "pwa-node",
        request = "launch",
        name = "Node: launch file",
        program = "${file}",
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        resolveSourceMapLocations = { "${workspaceFolder}/**", "!**/node_modules/**" },
      },
      {
        type = "pwa-node",
        request = "attach",
        name = "Node: attach",
        processId = require("dap.utils").pick_process,
        cwd = "${workspaceFolder}",
        sourceMaps = true,
      },
    }
    for _, filetype in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "svelte" }) do
      dap.configurations[filetype] = javascript_configurations
    end

    dap.configurations.go = {
      {
        type = "delve",
        name = "Go: launch file",
        request = "launch",
        program = "${file}",
      },
      {
        type = "delve",
        name = "Go: launch package",
        request = "launch",
        program = "${workspaceFolder}",
      },
    }

    local function executable_prompt(prompt)
      local path = vim.fn.input(prompt, vim.fn.getcwd() .. "/", "file")
      if path == "" then
        vim.notify("A debug executable is required.", vim.log.levels.WARN)
        return dap.ABORT
      end
      return path
    end

    dap.configurations.rust = {
      {
        type = "codelldb",
        request = "launch",
        name = "Rust: launch executable",
        program = function()
          return executable_prompt("Path to Rust executable: ")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }
    dap.configurations.c = {
      {
        type = "codelldb",
        request = "launch",
        name = "C: launch executable",
        program = function()
          return executable_prompt("Path to C executable: ")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }
    dap.configurations.cpp = {
      {
        type = "codelldb",
        request = "launch",
        name = "C++: launch executable",
        program = function()
          return executable_prompt("Path to C++ executable: ")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }
    dap.configurations.cs = {
      {
        type = "netcoredbg",
        request = "launch",
        name = ".NET: launch assembly",
        program = function()
          return executable_prompt("Path to .NET assembly: ")
        end,
        cwd = "${workspaceFolder}",
      },
    }
    dap.configurations.csharp = dap.configurations.cs

    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticSignError", linehl = "", numhl = "" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticSignWarn", linehl = "", numhl = "" })
    vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticSignInfo", linehl = "DapStoppedLine", numhl = "" })

    dapui.setup()
    local virtual_text = require("nvim-dap-virtual-text")
    virtual_text.setup({ enabled = true, commented = true })

    dap.listeners.after.event_initialized["collin-dapui"] = function()
      dapui.open()
    end
    dap.listeners.before.event_terminated["collin-dapui"] = function()
      dapui.close()
    end
    dap.listeners.before.event_exited["collin-dapui"] = function()
      dapui.close()
    end

    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { desc = desc })
    end

    map("<leader>db", dap.toggle_breakpoint, "Toggle breakpoint")
    map("<leader>dB", function()
      dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
    end, "Conditional breakpoint")
    map("<leader>dc", dap.continue, "Continue")
    map("<leader>dp", dap.pause, "Pause debug session")
    map("<leader>di", dap.step_into, "Step into")
    map("<leader>do", dap.step_over, "Step over")
    map("<leader>dO", dap.step_out, "Step out")
    map("<leader>dr", dap.restart, "Restart debug session")
    map("<leader>dq", dap.terminate, "Terminate debug session")
    map("<leader>du", dapui.toggle, "Toggle DAP UI")
    map("<leader>dv", function()
      virtual_text.toggle()
      vim.notify("DAP virtual text " .. (virtual_text.is_enabled() and "enabled" or "disabled"))
    end, "Toggle DAP virtual text")
    map("<leader>de", function()
      dapui.eval(vim.fn.input("Expression: "))
    end, "Evaluate expression")
  end,
}
