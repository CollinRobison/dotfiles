local common = require("collin.ai.backends.common")
local M = {}

local function executable()
  local path = common.executable("codex")
  if not path and vim.fn.has("mac") == 1 then
    local apps = {
      "/Applications/Codex.app/Contents/Resources/codex",
      "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
    }
    for _, prefix in ipairs({ "", vim.env.HOME or "" }) do
      for _, app in ipairs(apps) do
        local candidate = prefix .. app
        if vim.fn.executable(candidate) == 1 then
          return candidate
        end
      end
    end
  end
  return path
end

local function read_events(stdout, job)
  if type(stdout) ~= "string" or #stdout > 262144 then
    return job.finish("Invalid Codex completion response")
  end
  local message, completed
  for line in stdout:gmatch("[^\r\n]+") do
    local event = common.decode(line)
    if not event then
      return job.finish("Invalid Codex completion response")
    elseif event.type == "error" or event.type == "turn.failed" then
      return job.finish("Codex completion failed")
    elseif event.type == "item.completed" then
      if type(event.item) ~= "table" then
        return job.finish("Invalid Codex completion response")
      elseif event.item.type == "agent_message" then
        message = event.item.text
      elseif event.item.type ~= "reasoning" then
        return job.finish("Codex returned a non-completion action")
      end
    elseif event.type == "turn.completed" then
      completed = true
    end
  end
  if not completed then
    return job.finish("Incomplete Codex response")
  end
  common.extract(message, job)
end

function M.request(profile, context, job)
  local codex = executable()
  if not codex then
    return job.finish("The Codex CLI is not installed")
  end
  local scratch = common.scratch(job)
  if not scratch then
    return
  end

  local base = {
    codex,
    "-c",
    'forced_login_method="chatgpt"',
    "-c",
    'model_provider="openai"',
    "-c",
    'cli_auth_credentials_store="auto"',
    "-c",
    'chatgpt_base_url="https://chatgpt.com/backend-api/"',
  }
  local auth = vim.list_extend(vim.list_slice(base), { "login", "status" })
  job.run(auth, { cwd = scratch, stdin = "" }, function(result)
    local logged_in = false
    for line in ((result.stdout or "") .. "\n" .. (result.stderr or "")):gmatch("[^\r\n]+") do
      logged_in = logged_in or line == "Logged in using ChatGPT"
    end
    if result.code ~= 0 or not logged_in then
      return job.finish("Codex ChatGPT sign-in could not be verified")
    end
    local argv = vim.list_extend(base, {
      "-a",
      "never",
      "exec",
      "--ignore-user-config",
      "--ignore-rules",
      "--skip-git-repo-check",
      "--ephemeral",
      "--sandbox",
      "read-only",
      "--color",
      "never",
      "--json",
      "-c",
      'web_search="disabled"',
      "-c",
      "features.shell_tool=false",
      "-c",
      "features.apps=false",
      "-c",
      "features.plugins=false",
      "-c",
      "features.memories=false",
      "-c",
      'history.persistence="none"',
      "-c",
      "project_doc_max_bytes=0",
      "-c",
      "check_for_update_on_startup=false",
      "-c",
      "log_dir=" .. vim.json.encode(scratch),
    })
    if profile.model then
      vim.list_extend(argv, { "--model", profile.model })
    end
    argv[#argv + 1] = "-"
    job.run(argv, { cwd = scratch, stdin = common.instructions .. "\n\n" .. common.input(context) }, function(reply)
      if reply.code ~= 0 then
        return job.finish("Codex completion failed")
      end
      read_events(reply.stdout, job)
    end)
  end)
end

return M
