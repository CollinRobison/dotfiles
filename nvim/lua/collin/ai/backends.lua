local common = require("collin.ai.backends.common")
local M = {}

local modules = {
  codex = "codex",
  claude = "claude",
  pi = "pi",
  openrouter = "http",
  openai = "http",
  anthropic = "http",
}

---@param done fun(err: string|nil, suffix: string|nil)
---@return function cancel
function M.request(profile, context, done)
  local job = common.job(done)
  vim.schedule(job.guard(function()
    local module = modules[profile.backend]
    if not module then
      return job.finish("Unknown completion backend")
    end
    if
      profile.model ~= nil
      and (type(profile.model) ~= "string" or #profile.model > 120 or not profile.model:match("^[%w][%w._:/@%[%]%-]*$"))
    then
      return job.finish("Invalid completion model")
    end
    if profile.key_ref ~= nil and module ~= "http" then
      return job.finish("This completion backend uses its own sign-in")
    end
    job.deadline(30000)
    require("collin.ai.backends." .. module).request(profile, context, job)
  end))
  return job.cancel
end

return M
