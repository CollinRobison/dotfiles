local common = require("collin.ai.backends.common")
local M = {}

local function key(value)
  if type(value) == "string" and #value <= 4096 and value:match("^[!-~]+$") then
    return value
  end
end

local function valid_arg(value)
  return type(value) == "string" and #value > 0 and #value <= 1024 and not value:find("^%-") and not value:find("%c")
end

function M.read(ref, job, use)
  local function deliver(value)
    if value then
      use(value)
    else
      job.finish("Completion credential unavailable")
    end
  end

  if type(ref) ~= "table" then
    return job.finish("A completion credential reference is required")
  end
  if ref.type == "env" and type(ref.name) == "string" and ref.name:match("^[%a_][%w_]*$") then
    return deliver(key(vim.env[ref.name]))
  end

  local exe, argv, env
  if ref.type == "keychain" and valid_arg(ref.service) then
    exe = common.executable("security")
    argv = { "find-generic-password", "-s", ref.service, "-w" }
  elseif ref.type == "onepassword" and valid_arg(ref.reference) and ref.reference:match("^op://.+") then
    exe = common.executable("op")
    argv = { "read", "--no-newline", ref.reference }
    env = common.env({
      OP_ACCOUNT = vim.env.OP_ACCOUNT,
      OP_SERVICE_ACCOUNT_TOKEN = vim.env.OP_SERVICE_ACCOUNT_TOKEN,
      OP_BIOMETRIC_UNLOCK_ENABLED = vim.env.OP_BIOMETRIC_UNLOCK_ENABLED,
    })
  else
    return job.finish("Invalid completion credential reference")
  end
  if not exe then
    return job.finish("Completion credential helper is not installed")
  end
  table.insert(argv, 1, exe)
  job.run(argv, { env = env, stdin = "" }, function(result)
    deliver(result.code == 0 and key((result.stdout or ""):gsub("\r?\n$", "")) or nil)
  end)
end

return M
