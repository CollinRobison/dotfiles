local common = require("collin.ai.backends.common")
local M = {}

local function complete(binary, env, scratch, provider, model, context, job)
  local process, stage, message, settled
  local pending, bytes = "", 0
  local function send(command)
    stage = command.type
    command.id = stage
    process:write(vim.json.encode(command) .. "\n")
  end
  local function event(record)
    if record.type == "response" then
      if record.id ~= stage or record.command ~= stage or record.success ~= true then
        return job.finish("Pi rejected the completion request or selected model")
      end
      if stage == "set_model" then
        if type(record.data) ~= "table" or record.data.provider ~= provider or record.data.id ~= model then
          return job.finish("Pi did not select the requested model")
        end
        send({ type = "prompt", message = common.input(context) })
      elseif stage == "prompt" then
        stage = "running"
      end
    elseif record.type == "message_end" and type(record.message) == "table" and record.message.role == "assistant" then
      message = record.message
    elseif record.type:match("^tool_execution_") then
      return job.finish("Pi attempted a tool action during completion")
    elseif record.type == "agent_settled" then
      if stage ~= "running" or record.aborted ~= false or not message or message.stopReason ~= "stop" then
        return job.finish("Pi completion failed")
      end
      if not vim.islist(message.content) then
        return job.finish("Invalid Pi completion response")
      end
      local parts = {}
      for _, block in ipairs(message.content) do
        if type(block) ~= "table" then
          return job.finish("Invalid Pi completion response")
        elseif block.type == "text" and type(block.text) == "string" then
          parts[#parts + 1] = block.text
        elseif block.type ~= "thinking" then
          return job.finish("Pi returned a non-completion action")
        end
      end
      settled = true
      common.extract(table.concat(parts), job)
    end
  end
  local function read(err, chunk)
    if err then
      return job.finish("Could not read Pi completion stream")
    end
    if not job.active or not chunk then
      return
    end
    bytes = bytes + #chunk
    if bytes > 262144 then
      return job.finish("Invalid Pi completion stream")
    end
    pending = pending .. chunk
    while job.active do
      local newline = pending:find("\n", 1, true)
      if not newline then
        return
      end
      local record = common.decode(pending:sub(1, newline - 1):gsub("\r$", ""))
      pending = pending:sub(newline + 1)
      if not record or type(record.type) ~= "string" then
        return job.finish("Invalid Pi completion stream")
      end
      event(record)
    end
  end
  process = vim.system(
    {
      binary,
      "--mode",
      "rpc",
      "--offline",
      "--no-session",
      "--no-approve",
      "--no-tools",
      "--no-mcp",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-themes",
      "--no-context-files",
      "--thinking",
      "off",
      "--system-prompt",
      common.instructions,
    },
    {
      cwd = scratch,
      env = env,
      clear_env = true,
      stdin = true,
      stdout = vim.schedule_wrap(job.guard(read)),
      stderr = false,
    },
    vim.schedule_wrap(job.guard(function()
      job.finish("Pi exited before completing; check your Pi installation and sign-in")
    end))
  )
  job.on_stop(function()
    if settled then
      process:write(nil)
    else
      process:kill(9)
    end
  end)
  send({ type = "set_model", provider = provider, modelId = model })
end

function M.with_oauth(model_id, job, ready)
  local provider, model = (model_id or ""):match("^([%w._-]+)/([%w].*)$")
  if not provider then
    return job.finish("Pi requires an exact provider/model ID")
  end
  local binary = common.executable("pi")
  if not binary then
    return job.finish("Pi is not on Neovim's PATH")
  end
  local scratch = common.scratch(job)
  if not scratch then
    return
  end
  local env = common.env({ PI_CODING_AGENT_DIR = vim.env.PI_CODING_AGENT_DIR })
  job.run({ binary, "auth", "check", "--provider", provider, "--model", model_id, "--json", "--no-refresh" }, {
    cwd = scratch,
    env = env,
    stdin = "",
  }, function(result)
    local auth = result.code == 0 and common.decode(result.stdout)
    if not auth or auth.provider ~= provider or auth.status ~= "ready" or auth.authType ~= "oauth" then
      return job.finish("Pi requires a ready saved OAuth login; check Pi sign-in for this provider")
    end
    ready(binary, env, scratch, provider, model)
  end)
end

function M.request(profile, context, job)
  M.with_oauth(profile.model, job, function(binary, env, scratch, provider, model)
    complete(binary, env, scratch, provider, model, context, job)
  end)
end

return M
