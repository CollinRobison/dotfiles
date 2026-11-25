-- Run with: nvim --clean --headless -i NONE -l nvim/tests/ai/controller.lua
vim.opt.rtp:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h"))
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p", 448)
local original_mode = vim.api.nvim_get_mode
local original_select = vim.ui.select

local function test()
  vim.env.XDG_CONFIG_HOME = temp
  vim.env.NVIM_AI_PROFILE_FILE = vim.fs.joinpath(temp, "profiles.json")
  vim.fn.writefile(
    {
      vim.json.encode({
        { id = "copilot", backend = "copilot", completion = true, companion = true },
        { id = "claude", backend = "claude", completion = true, companion = true },
        { id = "invalid-http", backend = "openai", completion = true, model = "a-model", api_key = "dummy" },
        {
          id = "router",
          label = "OpenRouter test model",
          backend = "openrouter",
          model = "test/model",
          completion = true,
          companion = true,
          key_ref = { type = "env", name = "OPENROUTER_API_KEY", value = "not-retained" },
        },
      }),
    },
    vim.env.NVIM_AI_PROFILE_FILE
  )
  local profiles = require("collin.ai.profiles")
  assert(#profiles.for_workflow("completion") == 4)
  assert(#profiles.for_workflow("companion") == 4)
  assert(profiles.current("completion").id == "codex-chatgpt")
  assert(profiles.has_backend("copilot", "completion"))
  assert(not profiles.has_backend("openai", "completion"))
  local function select(id, expected_label)
    vim.ui.select = function(items, opts, done)
      for _, profile in ipairs(items) do
        if profile.id == id then
          assert(profile.key_ref == nil or profile.key_ref.value == nil)
          if expected_label then
            assert(opts.format_item(profile) == expected_label)
          end
          return done(profile)
        end
      end
      error("missing fixture profile")
    end
  end
  select("router", "OpenRouter test model [metered API] [Ask only]")
  profiles.choose("companion")
  assert(not profiles.current("companion").inline_edit)
  select("claude", "claude [Ask and Chat]")
  profiles.choose("companion")
  assert(not profiles.current("companion").inline_edit)
  assert(profiles.current("completion").backend == "codex")
  package.loaded["collin.ai.profiles"] = nil
  profiles = require("collin.ai.profiles")
  assert(profiles.current("companion").id == "claude", "selection must survive restart")
  assert(profiles.current("completion").id == "codex-chatgpt")
  local selection_path = vim.fs.joinpath(vim.fn.stdpath("config"), "ai-workflows", "selection.json")
  local saved = vim.json.decode(table.concat(vim.fn.readfile(selection_path), "\n"))
  assert(vim.deep_equal(saved, { completion = "codex-chatgpt", companion = "claude" }))

  local requests = {}
  package.loaded["collin.ai.backends"] = {
    request = function(profile, context, done)
      local request = { profile = profile, context = context, done = done, cancelled = false }
      table.insert(requests, request)
      return function()
        request.cancelled = true
      end
    end,
  }
  -- Keep buffer/event APIs real. Stub the mode for deterministic headless callbacks.
  vim.api.nvim_get_mode = function()
    return { mode = "i", blocking = false }
  end
  local completion = require("collin.ai.completion")
  completion.setup()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "return ;", "after" })
  vim.api.nvim_win_set_cursor(0, { 2, 7 })
  local ns = vim.api.nvim_get_namespaces()["collin.ai.completion"]
  local function marks()
    return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  end
  local function await(callback)
    assert(vim.wait(700, callback, 5), "async state did not settle")
  end
  local function unchanged()
    assert(vim.api.nvim_buf_get_lines(buf, 1, 2, true)[1] == "return ;")
  end

  completion.accept()
  unchanged()
  completion.request()
  assert(#requests == 1 and marks()[1][4].virt_text_pos == "eol", "request has a pending mark")
  assert(requests[1].context.prefix == "before\nreturn ")
  assert(requests[1].context.suffix == ";\nafter")
  requests[1].done(nil, "x * x")
  await(function()
    return #marks() == 1 and marks()[1][4].virt_text_pos == "inline"
  end)
  unchanged()
  completion.accept()
  assert(vim.api.nvim_buf_get_lines(buf, 1, 2, true)[1] == "return x * x;")
  assert(#marks() == 0)

  vim.api.nvim_buf_set_lines(buf, 1, 2, true, { "return ;" })
  vim.api.nvim_win_set_cursor(0, { 2, 7 })
  completion.request()
  vim.api.nvim_win_set_cursor(0, { 2, 6 })
  vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = buf })
  vim.api.nvim_win_set_cursor(0, { 2, 7 })
  assert(requests[2].cancelled)
  requests[2].done(nil, "late")
  vim.wait(20, function()
    return false
  end, 5)
  assert(#marks() == 0, "stale suggestion rendered after cursor returned")
  unchanged()

  completion.request()
  select("copilot")
  profiles.choose("completion", completion.clear)
  assert(requests[3].cancelled and profiles.current("companion").id == "claude")
  completion.request()
  assert(requests[4].profile.backend == "copilot")
  requests[3].done(nil, "old provider")
  requests[4].done(nil, "fenced\nresponse")
  await(function()
    return #marks() == 0
  end)
  unchanged()

  completion.request()
  vim.api.nvim_buf_set_text(buf, 1, 7, 1, 7, { "new " })
  requests[5].done(nil, "stale after edit")
  await(function()
    return #marks() == 0
  end)
  assert(vim.api.nvim_buf_get_lines(buf, 1, 2, true)[1] == "return new ;")

  vim.api.nvim_buf_set_name(buf, vim.fs.joinpath(temp, ".env.local"))
  completion.request()
  assert(#requests == 5, "credential buffer must never be sent")
  vim.api.nvim_buf_set_name(buf, "")
  completion.request()
  assert(#requests == 6, "ordinary unnamed buffers may request a suggestion")
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
  assert(requests[6].cancelled and #marks() == 0)
end

local ok, err = xpcall(test, debug.traceback)
vim.api.nvim_get_mode = original_mode
vim.ui.select = original_select
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
print("AI profiles and completion controller: passed")
