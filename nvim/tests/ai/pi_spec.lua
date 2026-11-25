-- Run from the repo root: nvim --clean --headless -i NONE -l nvim/tests/ai/pi_spec.lua
vim.opt.rtp:prepend("nvim")
local common = require("collin.ai.backends.common")
local backend = require("collin.ai.backends")
local profile = { backend = "pi", model = "openai/example" }
local ctx = { prefix = "private fixture", suffix = ";", filetype = "lua" }
local auth_type, selected, hold, sent, kill, closed, spawned
common.executable = function(name)
  assert(name == "pi")
  return "/mock/pi"
end
vim.env.OPENAI_API_KEY = "must-not-be-inherited"
vim.system = function(argv, opts, exit)
  assert(not opts.env.OPENAI_API_KEY and opts.clear_env)
  assert(not table.concat(argv, " "):find(ctx.prefix, 1, true))
  if argv[2] == "auth" then
    assert(vim.deep_equal(argv, {
      "/mock/pi",
      "auth",
      "check",
      "--provider",
      "openai",
      "--model",
      profile.model,
      "--json",
      "--no-refresh",
    }))
    exit({ code = 0, stdout = vim.json.encode({ provider = "openai", status = "ready", authType = auth_type }) })
    return {}
  end
  spawned = true
  for _, flag in ipairs({ "--no-tools", "--no-mcp", "--no-extensions", "--no-session", "--no-context-files" }) do
    assert(vim.tbl_contains(argv, flag))
  end
  local function emit(event)
    local data = vim.json.encode(event) .. "\n"
    opts.stdout(nil, data:sub(1, 7))
    opts.stdout(nil, data:sub(8))
  end
  return {
    kill = function(_, signal)
      kill = signal
    end,
    write = function(_, data)
      if not data then
        closed = true
        return
      end
      local cmd = vim.json.decode(data)
      sent[#sent + 1] = cmd.type
      if cmd.type == "set_model" then
        assert(cmd.provider == "openai" and cmd.modelId == "example")
        emit({
          type = "response",
          id = cmd.id,
          command = cmd.type,
          success = true,
          data = { provider = "openai", id = selected },
        })
      else
        assert(vim.json.decode(cmd.message).prefix == ctx.prefix)
        emit({ type = "response", id = cmd.id, command = cmd.type, success = true })
        if not hold then
          emit({
            type = "message_end",
            message = {
              role = "assistant",
              stopReason = "stop",
              content = { { type = "text", text = '{"suffix":"42"}' } },
            },
          })
          emit({ type = "agent_settled", aborted = false })
        end
      end
    end,
  }
end

local function run(auth, model, cancel_inflight)
  auth_type, selected, hold = auth, model, cancel_inflight
  sent, kill, closed, spawned = {}, nil, false, false
  local done, err, value
  local cancel = backend.request(profile, ctx, function(e, v)
    done, err, value = true, e, v
  end)
  if cancel_inflight then
    assert(vim.wait(1000, function()
      return #sent == 2
    end))
    cancel()
    assert(kill == 9 and not done)
    return
  end
  assert(vim.wait(1000, function()
    return done
  end))
  return err, value
end

local err, result = run("oauth", "example")
assert(not err and result == "42" and closed)
assert(vim.deep_equal(sent, { "set_model", "prompt" }))
assert(run("api_key", "example"):find("OAuth", 1, true) and not spawned)
assert(run("oauth", "different"):find("requested model", 1, true) and #sent == 1)
run("oauth", "example", true)
print("Pi completion RPC: exact model, OAuth, output framing, and cancellation passed")
