-- Run from the repository root, with isolated/local copies of the pinned plugins:
-- CODECOMPANION_RTP=/path/to/codecompanion.nvim PLENARY_RTP=/path/to/plenary.nvim \
--   nvim --headless -u NONE -l nvim/tests/ai/companion.lua
local api, fn = vim.api, vim.fn
vim.opt.rtp:prepend(fn.fnamemodify("nvim", ":p"))
vim.opt.rtp:prepend(assert(vim.env.CODECOMPANION_RTP))
vim.opt.rtp:prepend(assert(vim.env.PLENARY_RTP))

local temp = fn.tempname()
assert(fn.mkdir(temp, "p", 448) == 1)
local fixture = fn.fnamemodify("nvim/tests/ai/companion_fixture.py", ":p")
for _, name in ipairs({ "codex-acp", "copilot", "pi", "pi-acp" }) do
  assert(vim.uv.fs_symlink(fixture, vim.fs.joinpath(temp, name)))
end
vim.env.PATH = temp .. ":" .. vim.env.PATH
vim.cmd.cd(temp)

local notifications = {}
vim.notify = function(msg)
  notifications[#notifications + 1] = msg
end
local function last_notice()
  return notifications[#notifications] or ""
end
local function wait_for(condition, label)
  assert(vim.wait(7000, condition), label .. ": " .. table.concat(notifications, " | "))
end
local function lines(buf)
  return api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end
local function keys(seq)
  api.nvim_feedkeys(api.nvim_replace_termcodes(seq, true, false, true), "xt", false)
end
local function eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local function test()
  local spec = require("collin.lazy.codecompanion")
  eq("0ba3b39a9c21ae1d6e93bb3e1c39aeaad3fadf12", spec.commit)
  assert(spec.lazy)
  assert(not package.loaded.codecompanion)
  local companion = require("collin.ai.companion")
  assert(not package.loaded.codecompanion)
  spec.config(nil, spec.opts)
  local connection = require("codecompanion.acp")
  local function model_session(adapter, initial, options)
    local config = { id = "model", category = "model", type = "select", currentValue = initial, options = options }
    return setmetatable({
      adapter = adapter,
      adapter_modified = { defaults = {} },
      session_id = "fixture",
      _config_options = { config },
      send_rpc_request = function(self, request)
        self.requested_model = request.params.value
        config.currentValue = self.requested_model
        return {}
      end,
    }, { __index = connection })
  end
  local options = {
    { value = "fixture/start", name = "Start" },
    { value = "fixture/new", name = "New" },
    { value = "other/model", name = "Other provider" },
  }
  local pi = model_session({ dotfiles_action = "chat", dotfiles_pi_model = "fixture/start" }, "fixture/start", options)
  eq(2, #pi:get_models().availableModels)
  assert(not pi:set_model("other/model") and not pi:set_model("fixture/unlisted") and not pi.requested_model)
  assert(pi:set_model("fixture/new"))
  eq("fixture/new", pi:get_models().currentModelId)
  local ask = model_session({ dotfiles_action = "ask", dotfiles_pi_model = "fixture/start" }, "fixture/start", options)
  eq(1, #ask:get_models().availableModels)
  assert(not ask:set_model("fixture/new") and not ask.requested_model)
  local native = model_session({}, "fixture/start", options)
  eq(3, #native:get_models().availableModels)
  assert(native:set_model("other/model"))
  local cfg = require("codecompanion.config")
  local review = require("collin.ai.companion.pi_chat")
  local tested_file = temp .. "/review-fixture.lua"
  local write_request = {
    sessionId = "review",
    options = { { kind = "allow_once", optionId = "yes" } },
    toolCall = {
      title = "Review Pi workspace change",
      rawInput = {
        method = "confirm",
        message = vim.json.encode({ operation = "edit", path = tested_file, before = "before\n", after = "after\n" }),
      },
    },
  }
  local outcome
  local review_connection = setmetatable({
    adapter = { dotfiles_env = { NVIM_AI_PI_ROOT = temp } },
    session_id = "review",
    _active_prompt = {},
    _pending_permissions = {},
    send_result = function(_, _, result)
      outcome = result.outcome
    end,
  }, { __index = connection })
  fn.writefile({ "before" }, tested_file)
  local target = fn.bufadd(tested_file)
  fn.bufload(target)
  local function present()
    outcome = nil
    review.review(review_connection, 10, write_request)
    assert(not outcome and fn.maparg("g2", "n", false, true).buffer == 1)
    eq({ "before" }, fn.readfile(tested_file))
  end
  present()
  keys("q")
  eq({ outcome = "cancelled" }, outcome)
  present()
  api.nvim_buf_set_lines(target, 0, -1, false, { "unsaved" })
  keys("g2")
  eq({ outcome = "cancelled" }, outcome)
  vim.bo[target].modified = false
  present()
  keys("g2")
  eq({ outcome = "selected", optionId = "yes" }, outcome)
  api.nvim_buf_delete(target, { force = true })
  local original_select = vim.ui.select
  vim.ui.select = function(_, opts, cb)
    assert(opts.prompt:find("Move file", 1, true))
    cb("Approve once")
  end
  local moved_file = temp .. "/moved-fixture.lua"
  write_request.toolCall.rawInput.message =
    vim.json.encode({ operation = "move", path = tested_file, destination = moved_file })
  review.review(review_connection, 10, write_request)
  eq({ outcome = "selected", optionId = "yes" }, outcome)
  assert(review_connection.dotfiles_pi_writes[moved_file])
  write_request.toolCall.rawInput.message =
    vim.json.encode({ operation = "move", path = tested_file, destination = "/outside.lua" })
  review.review(review_connection, 10, write_request)
  eq({ outcome = "cancelled" }, outcome)
  vim.ui.select = original_select
  local cli = require("collin.ai.companion.cli")
  assert(cli.acp_adapter({ backend = "pi", action = "chat", args = {} }).opts.vision)
  assert(not cli.acp_adapter({ backend = "pi", action = "ask", args = {} }).opts.vision)
  assert(not cfg.adapters.acp.copilot_acp and not cfg.adapters.http.openai)
  local resolved, why = pcall(require("codecompanion.adapters").resolve, "openai")
  assert(not resolved and why:find("retain raw auth headers", 1, true))
  local codecompanion = require("codecompanion")
  local codex = { id = "codex", backend = "codex", model = "fixture-codex" }
  local copilot = { id = "copilot", backend = "copilot", model = "fixture-copilot" }
  local claude = { id = "claude", backend = "claude", model = "sonnet" }
  local api_profile = { id = "router", backend = "openrouter", model = "vendor/test-model" }
  for _, name in ipairs({ "OPENAI_API_KEY", "CODEX_API_KEY", "DEFAULT_AUTH_REQUEST", "GH_TOKEN", "ANTHROPIC_API_KEY" }) do
    vim.env[name] = "fixture-sentinel"
  end

  local question = "Explain the selection"
  vim.ui.input = function(_, cb)
    assert(api.nvim_get_mode().mode == "n")
    cb(question)
  end
  local source = api.nvim_get_current_buf()
  local original = { "first unchanged", "middle and unselected", "last unchanged" }
  api.nvim_buf_set_lines(source, 0, -1, false, original)
  vim.keymap.set("x", "Q", function()
    companion.ask(codex)
  end)
  vim.keymap.set("x", "X", function()
    companion.ask(copilot)
  end)
  vim.keymap.set("x", "E", function()
    companion.edit(codex)
  end)

  for _, map in ipairs({ "Q", "X" }) do
    keys("gg0jv5l" .. map)
    wait_for(function()
      return vim.bo.buftype == "nofile" and lines()[1] == "Fixture answer"
    end, map .. " ACP Ask")
    assert(not vim.bo.modifiable and not vim.bo.swapfile)
    eq(original, lines(source))
    vim.cmd.bwipeout()
    assert(api.nvim_get_current_buf() == source)
  end

  -- These stale marks cover the entire buffer; the active reversed selection
  -- on line 2 must determine the only lines eligible for review.
  api.nvim_buf_set_mark(source, "<", 1, 0, {})
  api.nvim_buf_set_mark(source, ">", 3, 0, {})
  question = "Replace the line, keeping adapter=openai #{chat} as literal text"
  local approvals = require("codecompanion.interactions.chat.tools.approvals")
  approvals:always(source, { tool_name = "inline" })
  for _, decision in ipairs({ "g3", "g2" }) do
    keys("gg0j$v0E")
    wait_for(function()
      return fn.maparg(decision, "n", false, true).buffer == 1
    end, "Inline review")
    keys(decision)
    eq(decision == "g3" and original or { original[1], "MIDDLE CHANGED", original[3] }, lines(source))
  end
  assert(not vim.uv.fs_stat(vim.fs.joinpath(temp, "never-write-me")))

  local pi_profile = { id = "pi", backend = "pi", model = "fixture/start" }
  api.nvim_buf_set_lines(source, 0, -1, false, original)
  vim.keymap.set("x", "Q", function()
    companion.ask(pi_profile)
  end, { buffer = source })
  keys("gg0<C-v>jlQ")
  wait_for(function()
    return vim.bo.buftype == "nofile" and lines()[#lines()] == "Fixture block answer"
  end, "Pi Visual Block Ask")
  eq({ "pi v1.6.0", "Fixture block answer" }, lines())
  eq(original, lines(source))
  vim.cmd.bwipeout()
  local function propose_pi(instruction)
    api.nvim_set_current_buf(source)
    api.nvim_buf_set_lines(source, 0, -1, false, original)
    vim.ui.input = function(_, cb)
      cb(instruction)
    end
    vim.keymap.set("x", "E", function()
      companion.edit(pi_profile)
    end, { buffer = source })
    keys("gg0jVE")
    if instruction == "malformed" then
      wait_for(function()
        return last_notice():find("valid replacement lines", 1, true) ~= nil
      end, "Malformed Pi output")
    else
      wait_for(function()
        return api.nvim_get_current_buf() ~= source and vim.w.pi_edit_review
      end, "Pi review")
    end
    eq(original, lines(source))
  end
  propose_pi("malformed")
  propose_pi("expand")
  keys("g3")
  wait_for(function()
    return api.nvim_get_current_buf() == source
  end, "Pi reject closes review")
  eq(original, lines(source))
  propose_pi("expand")
  keys("q")
  wait_for(function()
    return api.nvim_get_current_buf() == source
  end, "Pi close discards review")
  eq(original, lines(source))
  propose_pi("expand")
  keys("gr")
  wait_for(function()
    return api.nvim_get_current_buf() == source
  end, "Pi reject hunk closes review")
  eq(original, lines(source))
  propose_pi("expand")
  keys("ga")
  wait_for(function()
    return api.nvim_get_current_buf() == source
  end, "Pi accept hunk closes review")
  eq({ original[1], "PI CHANGED", "added line", original[3] }, lines(source))
  keys("u")
  eq(original, lines(source))
  propose_pi("expand")
  api.nvim_buf_set_lines(source, 0, 1, false, { "user updated source" })
  keys("g2")
  wait_for(function()
    return last_notice():find("changed during review", 1, true) ~= nil
  end, "Stale Pi edit rejected")
  eq({ "user updated source", original[2], original[3] }, lines(source))
  propose_pi("delete")
  keys("g2")
  wait_for(function()
    return api.nvim_get_current_buf() == source
  end, "Pi delete closes review")
  eq({ original[1], original[3] }, lines(source))
  api.nvim_buf_set_lines(source, 0, -1, false, original)
  vim.keymap.set("x", "E", function()
    companion.edit(codex)
  end, { buffer = source })
  vim.ui.input = function(_, cb)
    cb(question)
  end

  local bad_model = { id = "invalid", backend = "codex", model = "unavailable" }
  companion.ask(bad_model)
  wait_for(function()
    return last_notice():find("authenticated session", 1, true) ~= nil
  end, "Model miss stops the request")
  assert(api.nvim_get_current_buf() == source)
  local count_before_auth = #notifications
  companion.ask({ id = "no-login", backend = "codex", model = "missing-chatgpt" })
  wait_for(function()
    return #notifications >= count_before_auth + 2
      and notifications[count_before_auth + 1]:find("no API login was attempted", 1, true) ~= nil
  end, "No Codex API auth fallback")

  companion.edit(codex)
  assert(last_notice():find("Select editable lines", 1, true))
  local pending
  vim.ui.input = function(_, cb)
    pending = cb
  end
  keys("gg0jVE")
  api.nvim_buf_set_lines(source, 1, 2, false, { "user changed while prompting" })
  assert(pending)("stale")
  assert(last_notice():find("source buffer or working directory changed", 1, true))

  -- A real CodeCompanion chat must start fresh with no automatic turn,
  -- including when the user switches from Codex to explicit Copilot ACP.
  companion.chat(codex)
  local first = assert(codecompanion.last_chat())
  assert(first.adapter.name == "codex" and approvals:get_mode(first.bufnr) == "ask")
  assert(not first._turn_in_progress)
  companion.chat(copilot)
  local second = assert(codecompanion.last_chat())
  assert(first.bufnr ~= second.bufnr and second.adapter.name == "copilot_acp")
  assert(approvals:get_mode(second.bufnr) == "ask" and not second._turn_in_progress)
  wait_for(function()
    return first.acp_connection
      and first.acp_connection:is_connected()
      and second.acp_connection
      and second.acp_connection:is_connected()
  end, "Fresh ACP Chat sessions")
  vim.cmd.bwipeout({ args = { tostring(second.bufnr) }, bang = true })
  vim.cmd.bwipeout({ args = { tostring(first.bufnr) }, bang = true })
  api.nvim_set_current_buf(source)

  for _, profile in ipairs({
    api_profile,
    { id = "openai", backend = "openai", model = "x" },
    { id = "anthropic", backend = "anthropic", model = "x" },
  }) do
    companion.chat(profile)
    assert(last_notice():find("API Chat/Edit is disabled", 1, true))
    companion.edit(profile)
    assert(last_notice():find("API Chat/Edit is disabled", 1, true))
  end
  companion.edit(claude)
  assert(last_notice():find("native Ask/Chat", 1, true))
  companion.chat({ id = "bad", backend = "copilot", model = "--allow-all-tools" })
  assert(last_notice():find("invalid model", 1, true))

  local real_system, real_exepath, real_jobstart = vim.system, fn.exepath, fn.jobstart
  local calls, response = {}, nil
  fn.exepath = function(name)
    return ({ curl = "/fixture/curl", claude = "/fixture/claude", op = "/fixture/op", security = "/fixture/security" })[name]
      or real_exepath(name)
  end
  vim.system = function(argv, opts, callback)
    local got = assert(response)(argv, opts)
    table.insert(calls, argv)
    vim.schedule(function()
      callback(got)
    end)
    return {}
  end
  vim.ui.input = function(_, cb)
    cb('quotes " & backslash \\')
  end

  local fake_key = "fixture-api-key"
  vim.env.OPENROUTER_API_KEY = fake_key
  local function api_ask(backend, url, payload, ref, helper)
    local call_count = #calls
    response = function(argv, opts)
      assert(not table.concat(argv, " "):find(fake_key, 1, true))
      if argv[1] ~= "/fixture/curl" then
        eq(helper, argv)
        return { code = 0, stdout = fake_key .. "\n" }
      end
      assert(argv[2] == "-q" and vim.tbl_contains(argv, url) and not vim.tbl_contains(argv, "--location"))
      assert(opts.clear_env and not opts.env and opts.stdin:find(fake_key, 1, true))
      assert(opts.stdin:find("data-binary", 1, true) and opts.stdin:find("vendor/test-model", 1, true))
      assert(opts.stdin:find([[\\\"]], 1, true) and not opts.stdin:find('"tools"', 1, true))
      if backend == "anthropic" then
        assert(opts.stdin:find("x-api-key: ", 1, true))
      else
        assert(opts.stdin:find("authorization: Bearer ", 1, true))
      end
      return { code = 0, stdout = vim.json.encode(payload) .. "\n200" }
    end
    companion.ask({ id = backend, backend = backend, model = "vendor/test-model", key_ref = ref })
    wait_for(function()
      return vim.bo.buftype == "nofile" and lines()[1] == "API fixture answer"
    end, backend .. " API Ask")
    eq(helper and 2 or 1, #calls - call_count)
    vim.cmd.bwipeout()
  end

  api_ask(
    "openrouter",
    "https://openrouter.ai/api/v1/chat/completions",
    { choices = { { message = { content = "API fixture answer" } } } }
  )
  api_ask(
    "openai",
    "https://api.openai.com/v1/responses",
    {
      output = {
        { type = "message", content = {
          { type = "output_text", text = "API fixture answer" },
        } },
      },
    },
    { type = "onepassword", reference = "op://vault/item/field" },
    { "/fixture/op", "read", "--no-newline", "op://vault/item/field" }
  )
  api_ask(
    "anthropic",
    "https://api.anthropic.com/v1/messages",
    { content = { { type = "text", text = "API fixture answer" } } },
    { type = "keychain", service = "fixture.anthropic" },
    { "/fixture/security", "find-generic-password", "-s", "fixture.anthropic", "-w" }
  )

  response = function()
    return { code = 22, stdout = fake_key .. "\n429", stderr = fake_key }
  end
  companion.ask(api_profile)
  wait_for(function()
    return last_notice():find("HTTP 429", 1, true) ~= nil
  end, "Opaque API failure")
  assert(not table.concat(notifications, "\n"):find(fake_key, 1, true))
  vim.env.OPENROUTER_API_KEY = fake_key .. "\nheader injection"
  local count = #calls
  companion.ask(api_profile)
  assert(last_notice():find("invalid key", 1, true) and #calls == count)

  response = function(argv, opts)
    assert(opts.clear_env and not opts.env.ANTHROPIC_API_KEY)
    eq({ "/fixture/claude", "auth", "status", "--json" }, argv)
    return { code = 0, stdout = '{"loggedIn":true,"authMethod":"apiKey","apiProvider":"firstParty"}' }
  end
  companion.ask(claude)
  wait_for(function()
    return last_notice():find("existing first-party", 1, true) ~= nil
  end, "Claude denies API login")
  eq(count + 1, #calls)

  response = function(argv, opts)
    assert(opts.clear_env and not opts.env.ANTHROPIC_API_KEY)
    if argv[2] == "auth" then
      return {
        code = 0,
        stdout = '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}',
      }
    end
    assert(
      vim.tbl_contains(argv, "--print") and vim.tbl_contains(argv, "--tools") and vim.tbl_contains(argv, "--safe-mode")
    )
    assert(not vim.tbl_contains(argv, "--bare") and opts.stdin:find("quotes", 1, true))
    return { code = 0, stdout = "Claude fixture answer" }
  end
  companion.ask(claude)
  wait_for(function()
    return vim.bo.buftype == "nofile" and lines()[1] == "Claude fixture answer"
  end, "Claude CLI Ask")
  vim.cmd.bwipeout()

  local terminal
  fn.jobstart = function(argv, opts)
    assert(opts.term and opts.clear_env and not opts.env.ANTHROPIC_API_KEY)
    assert(vim.tbl_contains(argv, "--permission-mode") and not vim.tbl_contains(argv, "--print"))
    assert(not vim.tbl_contains(argv, "--continue") and not vim.tbl_contains(argv, "--resume"))
    terminal = true
    return 1
  end
  companion.chat(claude)
  wait_for(function()
    return terminal
  end, "Claude native Chat")
  vim.system, fn.exepath, fn.jobstart = real_system, real_exepath, real_jobstart
end

local ok, result = xpcall(test, debug.traceback)
vim.cmd.cd("/")
fn.delete(temp, "rf")
assert(ok, result)
print("CodeCompanion ACP, Claude CLI, and API Ask fixtures passed")
