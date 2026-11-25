local common = require("collin.ai.backends.common")
local M = {}

local subscriptions = { pro = true, max = true, team = true, enterprise = true }

function M.request(profile, context, job)
  local claude = common.executable("claude")
  if not claude then
    return job.finish("The Claude Code CLI is not installed")
  end
  local scratch = common.scratch(job)
  if not scratch then
    return
  end

  -- Keep official saved login/keychain access. --bare disables subscription auth.
  -- Require a CLI with safe mode; never retry with weaker flags.
  local base = { claude, "--safe-mode", "--setting-sources", "", "--settings", '{"disableAllHooks":true}' }
  local env = common.env({
    CLAUDE_CODE_SAFE_MODE = "1",
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1",
  })
  local auth = vim.list_extend(vim.list_slice(base), { "auth", "status", "--json" })
  job.run(auth, { cwd = scratch, env = env, stdin = "" }, function(result)
    local status = result.code == 0 and common.decode(result.stdout)
    if
      not status
      or status.loggedIn ~= true
      or status.authMethod ~= "claude.ai"
      or status.apiProvider ~= "firstParty"
      or not subscriptions[status.subscriptionType]
      or (status.apiKeySource and status.apiKeySource ~= vim.NIL)
    then
      return job.finish("Claude Code subscription sign-in could not be verified")
    end
    local argv = vim.list_extend(base, {
      "--print",
      "--output-format",
      "json",
      "--no-session-persistence",
      "--tools",
      "",
      "--strict-mcp-config",
      "--mcp-config",
      '{"mcpServers":{}}',
      "--no-chrome",
      "--disable-slash-commands",
      "--system-prompt",
      common.instructions,
    })
    if profile.model then
      vim.list_extend(argv, { "--model", profile.model })
    end
    job.run(argv, { cwd = scratch, env = env, stdin = common.input(context) }, function(reply)
      if reply.code ~= 0 then
        return job.finish("Claude Code completion failed")
      end
      local response = common.decode(reply.stdout)
      if not response or response.type ~= "result" or response.subtype ~= "success" or response.is_error ~= false then
        return job.finish("Invalid Claude Code completion response")
      end
      common.extract(response.result, job)
    end)
  end)
end

return M
