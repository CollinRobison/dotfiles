local common = require("collin.ai.backends.common")
local credentials = require("collin.ai.backends.credentials")
local M = {}

local function text_blocks(blocks, text_type)
  if not vim.islist(blocks) then
    return nil
  end
  local parts = {}
  for _, block in ipairs(blocks) do
    if type(block) ~= "table" or block.type ~= text_type or type(block.text) ~= "string" then
      return nil
    end
    parts[#parts + 1] = block.text
  end
  if #parts > 0 then
    return table.concat(parts)
  end
end

local providers = {
  openrouter = {
    endpoint = "https://openrouter.ai/api/v1/chat/completions",
    body = function(model, input)
      return {
        model = model,
        messages = {
          { role = "system", content = common.instructions },
          { role = "user", content = input },
        },
        max_tokens = 512,
        provider = { allow_fallbacks = false },
      }
    end,
    text = function(response)
      local choice = type(response.choices) == "table" and response.choices[1]
      local msg = type(choice) == "table" and choice.message
      if
        type(msg) == "table"
        and msg.role == "assistant"
        and choice.finish_reason == "stop"
        and (not msg.tool_calls or msg.tool_calls == vim.NIL)
        and (not msg.function_call or msg.function_call == vim.NIL)
        and (not msg.refusal or msg.refusal == vim.NIL)
      then
        return msg.content
      end
    end,
  },
  openai = {
    endpoint = "https://api.openai.com/v1/responses",
    body = function(model, input)
      return {
        model = model,
        instructions = common.instructions,
        input = input,
        max_output_tokens = 768,
        store = false,
        tool_choice = "none",
      }
    end,
    text = function(response)
      if response.status ~= "completed" or not vim.islist(response.output) then
        return nil
      end
      local msg
      for _, item in ipairs(response.output) do
        if type(item) ~= "table" then
          return nil
        elseif item.type == "message" and item.role == "assistant" and item.status == "completed" and not msg then
          msg = item
        elseif item.type ~= "reasoning" then
          return nil
        end
      end
      return msg and text_blocks(msg.content, "output_text")
    end,
  },
  anthropic = {
    endpoint = "https://api.anthropic.com/v1/messages",
    body = function(model, input)
      return {
        model = model,
        system = common.instructions,
        messages = { { role = "user", content = input } },
        max_tokens = 512,
      }
    end,
    text = function(response)
      if response.type == "message" and response.role == "assistant" and response.stop_reason == "end_turn" then
        return text_blocks(response.content, "text")
      end
    end,
  },
}

-- curl's stdin config keeps both the auth header and the prompt out of argv.
local function config_value(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"\n'
end

function M.request(profile, context, job)
  if not profile.model then
    return job.finish("An API completion model is required")
  end
  local curl = common.executable("curl")
  if not curl then
    return job.finish("curl is required for API completions")
  end
  local provider = providers[profile.backend]
  credentials.read(profile.key_ref, job, function(key)
    local headers = 'header = "Content-Type: application/json"\n'
    if profile.backend == "anthropic" then
      headers = headers .. 'header = "anthropic-version: 2023-06-01"\nheader = ' .. config_value("x-api-key: " .. key)
    else
      headers = headers .. "header = " .. config_value("Authorization: Bearer " .. key)
    end
    local body = vim.json.encode(provider.body(profile.model, common.input(context)))
    job.run(
      {
        curl,
        "--disable",
        "--silent",
        "--fail",
        "--connect-timeout",
        "5",
        "--max-time",
        "20",
        "--proto",
        "=https",
        "--max-filesize",
        "262144",
        "--noproxy",
        "*",
        "--request",
        "POST",
        "--url",
        provider.endpoint,
        "--config",
        "-",
      },
      {
        stdin = headers .. "data-binary = " .. config_value(body),
      },
      function(result)
        if result.code ~= 0 then
          return job.finish("Completion API request failed")
        end
        local response = common.decode(result.stdout)
        if not response or (response.error and response.error ~= vim.NIL) then
          return job.finish("Invalid completion API response")
        end
        common.extract(provider.text(response), job)
      end
    )
  end)
end

return M
