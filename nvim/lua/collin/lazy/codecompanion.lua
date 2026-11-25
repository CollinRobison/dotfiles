return {
  "olimorris/codecompanion.nvim",
  -- v20.3.0: the mapped edit uses this release's ACP inline/range APIs.
  commit = "0ba3b39a9c21ae1d6e93bb3e1c39aeaad3fadf12",
  lazy = true,
  dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
  opts = {
    adapters = {
      acp = {
        opts = { show_presets = false, subagents = false },
        codex = function()
          local cli = require("collin.ai.companion.cli")
          local route, err = cli.acp_route("codex", nil, "chat")
          if not route then
            vim.notify(err, vim.log.levels.ERROR, { title = "CodeCompanion" })
            return nil
          end
          return cli.acp_adapter(route)
        end,
      },
      http = { opts = { show_presets = false, show_model_choices = false } },
    },
    interactions = {
      chat = { adapter = "codex", tools = { opts = { approval_mode = "ask", default_tools = {} } } },
      inline = { adapter = "codex" },
      background = {
        chat = { opts = { enabled = false } },
        gates = { judge = { enabled = false } },
      },
    },
    display = { diff = { enabled = true } },
    opts = { log_level = "OFF", per_project_config = { enabled = false } },
  },
  config = function(_, opts)
    -- Direct :CodeCompanionChat adapter=... can resolve built-in HTTP adapters
    -- even when presets are hidden. Block this at the pinned HTTP resolver too.
    -- Revisit only after auditing a newer release's header ownership/cleanup on
    -- success, failure and cancellation, without raw auth headers in logs/argv.
    require("codecompanion.adapters.http").resolve = function()
      error("CodeCompanion HTTP adapters are disabled: v20.3.0 can retain raw auth headers on disk.", 0)
    end
    -- v20.3.0 creates raw RPC transcript files even with log_level=OFF.
    require("codecompanion.utils.log").new_response_file = function()
      return { path = "[disabled]", write = function() end, discard = function() end }
    end
    -- ACP fs writes are not inherently approval-gated. For our adapters, allow
    -- only Inline's own active, copy-scoped write handler; Chat uses the agent's
    -- native approval requests instead of exposing a Neovim-backed write RPC.
    local connection = require("codecompanion.acp")
    local new = connection.new
    connection.new = function(args)
      local self = new(args)
      local env = self.adapter and self.adapter.dotfiles_env
      if env then
        local job = self.methods.job
        self.methods.job = function(command, process_opts, callback)
          process_opts.env = env
          process_opts.clear_env = true
          return job(command, process_opts, callback)
        end
      end
      return self
    end
    local authenticate = connection._authenticate
    connection._authenticate = function(self)
      if
        self.adapter
        and self.adapter.dotfiles_codex_mode
        and not vim.iter(self._agent_info.authMethods or {}):any(function(method)
          return method.id == "chat-gpt"
        end)
      then
        vim.notify(
          "Codex ACP did not advertise ChatGPT authentication; no API login was attempted.",
          vim.log.levels.ERROR,
          { title = "CodeCompanion" }
        )
        return false
      end
      return authenticate(self)
    end
    local write = connection.handle_fs_write_file_request
    connection.handle_fs_write_file_request = function(self, id, params)
      local action = self.adapter and self.adapter.dotfiles_action
      local handlers = self._active_prompt and self._active_prompt.handlers
      if action and (action ~= "edit" or not (handlers and handlers.write_text_file_request)) then
        return self:send_error(id, "This AI workflow does not expose editor filesystem writes")
      end
      return write(self, id, params)
    end
    -- Verify launch choices before any Codex prompt. Upstream's ACP defaults
    -- merely warn when the agent silently picks a different model or mode.
    local establish = connection._establish_session
    connection._establish_session = function(self)
      local ok = establish(self)
      local adapter = self.adapter
      if not (ok and adapter and adapter.dotfiles_codex_mode) then
        return ok
      end
      local mode, model
      for _, option in ipairs(self:get_config_options()) do
        if option.category == "mode" then
          mode = option.currentValue
        elseif option.category == "model" and type(option.currentValue) == "string" then
          model = option.currentValue:match("^[^%[]+") -- codex-acp model[effort]
        end
      end
      if mode ~= adapter.dotfiles_codex_mode or (adapter.dotfiles_model and model ~= adapter.dotfiles_model) then
        self:use_session(nil)
        vim.notify(
          "Codex ACP did not honor the requested model or read-only mode. Check the model and codex-acp version.",
          vim.log.levels.ERROR,
          { title = "CodeCompanion" }
        )
        return false
      end
      return true
    end
    require("codecompanion").setup(opts)
  end,
}
