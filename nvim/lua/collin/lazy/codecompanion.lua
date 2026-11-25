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
    -- Pi extension confirmations go through our one-shot review even if the
    -- regular chat approval mode has been changed to auto or yolo.
    local prompt_builder = require("codecompanion.acp.prompt_builder")
    local permission = prompt_builder.handle_permission_request
    prompt_builder.handle_permission_request = function(self, id, params)
      local adapter = self.connection.adapter
      if adapter and adapter.dotfiles_pi_model and adapter.dotfiles_action == "chat" then
        return require("collin.ai.companion.pi_chat").review(self.connection, id, params)
      end
      return permission(self, id, params)
    end
    local done = prompt_builder.handle_done
    prompt_builder.handle_done = function(self, ...)
      if self.connection.dotfiles_pi_writes then
        require("collin.ai.companion.pi_chat").refresh(self.connection)
      end
      return done(self, ...)
    end
    local read = connection.handle_fs_read_text_file_request
    connection.handle_fs_read_text_file_request = function(self, id, params)
      if self.adapter and self.adapter.dotfiles_pi_model then
        return self:send_error(id, "Pi assistance does not expose the editor filesystem")
      end
      return read(self, id, params)
    end
    -- Use the agent's advertised list. Pi can expose several providers at once,
    -- but only the provider selected by the profile passed our OAuth check.
    local function pi_model_allowed(adapter, model)
      local initial = adapter.dotfiles_pi_model
      return model == initial
        or (
          adapter.dotfiles_action == "chat"
          and type(model) == "string"
          and model:match("^([^/]+)/.+$") == initial:match("^([^/]+)/.+$")
        )
    end
    local get_models = connection.get_models
    connection.get_models = function(self)
      local models = get_models(self)
      local adapter = self.adapter
      if models and adapter and adapter.dotfiles_pi_model then
        models.availableModels = vim.tbl_filter(function(model)
          return pi_model_allowed(adapter, model.modelId)
        end, models.availableModels)
      end
      return models
    end
    local set_config = connection.set_config_option
    connection.set_config_option = function(self, id, value)
      local adapter = self.adapter
      if adapter and adapter.dotfiles_pi_model then
        for _, option in ipairs(self:get_config_options()) do
          if option.id == id and option.category == "model" then
            local models = self:get_models()
            if
              not models
              or not vim.iter(models.availableModels):any(function(model)
                return model.modelId == value
              end)
            then
              vim.notify("Pi model is unavailable for this chat's signed-in provider.", vim.log.levels.WARN)
              return false
            end
            local ok = set_config(self, id, value)
            local updated = self:get_models()
            if not ok or not updated or updated.currentModelId ~= value then
              self:use_session(nil)
              vim.notify("Pi did not confirm the model switch. Reopen the chat to continue.", vim.log.levels.WARN)
              return false
            end
            return true
          end
        end
      end
      return set_config(self, id, value)
    end
    -- Verify launch choices before any prompt. Upstream's ACP defaults
    -- merely warn when the agent silently picks a different model or mode.
    local establish = connection._establish_session
    connection._establish_session = function(self)
      local ok = establish(self)
      local adapter = self.adapter
      if not (ok and adapter) then
        return ok
      end
      if adapter.dotfiles_pi_model then
        local models = self:get_models()
        if not models or models.currentModelId ~= adapter.dotfiles_pi_model then
          self:use_session(nil)
          vim.notify("Pi did not start with the requested profile model.", vim.log.levels.ERROR)
          return false
        end
        return true
      end
      if not adapter.dotfiles_codex_mode then
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
