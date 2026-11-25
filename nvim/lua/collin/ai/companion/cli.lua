local M = {}
local subscriptions = { pro = true, max = true, team = true, enterprise = true }

-- Child processes get only what their native sign-in and launcher need. Do not
-- forward API keys, provider/base URL overrides, or auth/permission overrides.
local function login_env(backend)
  local env = {}
  local names = {
    "PATH",
    "HOME",
    "USER",
    "LOGNAME",
    "TMPDIR",
    "TEMP",
    "TMP",
    "LANG",
    "LC_ALL",
    "TERM",
    "XDG_CONFIG_HOME",
    "XDG_DATA_HOME",
    "XDG_STATE_HOME",
    "XDG_CACHE_HOME",
    "XDG_RUNTIME_DIR",
    "SystemRoot",
    "USERPROFILE",
    "APPDATA",
    "LOCALAPPDATA",
    "DBUS_SESSION_BUS_ADDRESS",
  }
  if backend == "codex" then
    table.insert(names, "CODEX_HOME")
  end
  for _, name in ipairs(names) do
    env[name] = vim.env[name]
  end
  return env
end

function M.acp_route(backend, model, action)
  local codex = backend == "codex"
  local executable = codex and "codex-acp" or "copilot"
  local binary = vim.fn.exepath(executable)
  if binary == "" then
    return nil,
      ("%s is not on Neovim's PATH; install the %s CLI first."):format(
        executable,
        codex and "official @agentclientprotocol/codex-acp" or "GitHub Copilot"
      )
  end
  local env = login_env(backend)
  local args = { binary }
  local mode = codex and "read-only" or nil
  if codex then
    -- The ACP package's default model may not be available to ChatGPT sessions.
    model = model or "gpt-6.2-astra"
    -- Inline permits only an approval for editing its temporary buffer copy.
    env.INITIAL_AGENT_MODE = mode
    env.CODEX_CONFIG = vim.json.encode({
      model = model,
      model_provider = "openai",
      forced_login_method = "chatgpt",
      approvals_reviewer = "user",
    })
  end
  if not codex then
    vim.list_extend(args, { "--acp", "--stdio", "--disable-builtin-mcps" })
    if model then
      vim.list_extend(args, { "--model", model })
    end
    if action == "ask" then
      table.insert(args, "--deny-tool=*")
    elseif action == "edit" then
      table.insert(args, "--deny-tool=shell")
    end
  end
  return { args = args, env = env, backend = backend, mode = mode, model = model, action = action }
end

function M.with_pi_route(model, action, ready, fail)
  local bridge = vim.fn.exepath("pi-acp")
  local launcher = vim.api.nvim_get_runtime_file("scripts/ai/pi-acp-launch.sh", false)[1]
  if bridge == "" or not launcher or vim.fn.executable(launcher) ~= 1 then
    return fail("Pi assistance needs pi-acp on PATH and an executable Pi launcher (macOS/Linux).")
  end
  local common = require("collin.ai.backends.common")
  local job = common.job(function(err)
    if err then
      fail(err)
    end
  end)
  job.deadline(10000)
  require("collin.ai.backends.pi").with_oauth(model, job, function(binary, env)
    env.PI_ACP_PI_COMMAND = launcher
    env.NVIM_AI_PI_BINARY = binary
    env.NVIM_AI_PI_MODEL = model
    if action == "chat" then
      local extension = vim.api.nvim_get_runtime_file("scripts/ai/pi-chat-tools.ts", false)[1]
      local root = vim.uv.fs_realpath(vim.fn.getcwd())
      if not extension or not root or root == "/" or root == vim.uv.fs_realpath(vim.fn.expand("~")) then
        return job.finish("Open Pi Chat from a project directory to use workspace tools.")
      end
      env.NVIM_AI_PI_CHAT_EXTENSION = extension
      env.NVIM_AI_PI_ROOT = root
    end
    ready({ backend = "pi", action = action, args = { bridge }, env = env, model = model })
    job.finish()
  end)
end

function M.acp_adapter(route)
  if route.backend == "pi" then
    -- Chat tools use an explicit extension, not ACP filesystem capabilities.
    local adapter = require("codecompanion.adapters.acp").extend("copilot_acp", {
      name = "pi_acp",
      formatted_name = "Pi",
      opts = { vision = route.action == "chat" },
      commands = { default = route.args },
      dotfiles_action = route.action,
      dotfiles_env = route.env,
      dotfiles_pi_model = route.model,
    })
    adapter.parameters.clientCapabilities = vim.empty_dict()
    return adapter
  end
  local codex = route.backend == "codex"
  local preset = codex and "codex" or "copilot_acp"
  local adapter = require("codecompanion.adapters.acp").extend(preset, {
    commands = { default = route.args },
    defaults = {
      auth_method = codex and "chat-gpt" or nil,
      session_config_options = { mode = route.mode },
    },
  })
  -- extend() merges tables, so assigning these afterwards matters.
  adapter.env = nil -- the bundled Codex adapter otherwise reads OPENAI_API_KEY
  adapter.commands = { default = route.args }
  adapter.dotfiles_action = route.action
  adapter.dotfiles_env = route.env
  adapter.dotfiles_codex_mode = route.mode
  adapter.dotfiles_model = route.model
  if route.action == "edit" then
    -- The upstream inline connection is cached by name, not by launch command.
    adapter.name = preset .. ":edit:" .. (route.model or "default")
  elseif route.action == "ask" then
    adapter.parameters.clientCapabilities = vim.empty_dict() -- no fs, terminals, or subagents
  else
    -- Broader Chat relies on agent permissions, not unsolicited editor writes.
    adapter.parameters.clientCapabilities.fs.writeTextFile = false
  end
  return adapter
end

function M.with_claude(cwd, on_ready, fail)
  local binary = vim.fn.exepath("claude")
  if binary == "" then
    return fail("The official Claude Code CLI ('claude') is not on Neovim's PATH.")
  end
  local env = login_env("claude")
  local ok = pcall(
    vim.system,
    { binary, "auth", "status", "--json" },
    { cwd = cwd, env = env, clear_env = true, text = true, timeout = 10000 },
    vim.schedule_wrap(function(result)
      local parsed, status = pcall(vim.json.decode, result.stdout or "")
      if
        result.code ~= 0
        or not parsed
        or type(status) ~= "table"
        or status.loggedIn ~= true
        or status.authMethod ~= "claude.ai"
        or status.apiProvider ~= "firstParty"
        or not subscriptions[status.subscriptionType]
        or (status.apiKeySource and status.apiKeySource ~= vim.NIL)
      then
        return fail(
          "Claude Code requires an existing first-party claude.ai subscription login. Sign in with the official CLI first."
        )
      end
      on_ready(binary, env)
    end)
  )
  if not ok then
    fail("Could not check the Claude Code login.")
  end
end

function M.claude_args(binary, model)
  -- --bare would disable OAuth. Safe mode and no settings sources prevent
  -- per-repo/user hooks, custom providers and tool presets (managed policy may apply).
  local args = { binary, "--safe-mode", "--setting-sources", "", "--strict-mcp-config", "--permission-mode", "default" }
  if model then
    vim.list_extend(args, { "--model", model })
  end
  return args
end

return M
