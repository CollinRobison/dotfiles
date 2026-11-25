-- Run from the repository root: nvim --headless -u NONE -l nvim/tests/ai/backends_spec.lua
vim.opt.rtp:prepend("nvim")
local backend = require("collin.ai.backends")
local common = require("collin.ai.backends.common")
local eq = function(expected, actual)
  assert(vim.deep_equal(expected, actual), ("expected %s; got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end
local encode = vim.json.encode
local suffix = '\treturn "🙂\\""\r\n'
local expected = suffix:gsub("\r\n", "\n")
local model_text = encode({ suffix = suffix })
local context = { prefix = "local x = ", suffix = ";\n", filetype = "lua", cwd = vim.uv.cwd() }
local calls, responses = {}, {}
local missing = {}
common.executable = function(name)
  return not missing[name] and "/mock/" .. name or nil
end
vim.env.DOTFILES_AI_TEST_KEY = 'dummy-test-"token\\'
vim.env.OPENAI_API_KEY = "dummy-codex-override"
vim.env.CODEX_API_KEY = "dummy-codex-override"
vim.env.CODEX_HOME = "/dummy/alternate"
vim.env.ANTHROPIC_API_KEY = "dummy-claude-override"
vim.env.ANTHROPIC_AUTH_TOKEN = "dummy-claude-override"
vim.env.CLAUDE_CODE_OAUTH_TOKEN = "dummy-claude-override"
vim.env.CLAUDE_CODE_USE_BEDROCK = "1"
vim.env.ANTHROPIC_BASE_URL = "https://dummy.invalid"
vim.env.HTTPS_PROXY = "https://dummy.invalid"

vim.system = function(argv, opts, reply)
  local response = table.remove(responses, 1)
  local call = { argv = argv, opts = opts, reply = reply }
  calls[#calls + 1] = call
  assert(response ~= nil, "unexpected subprocess")
  if response ~= false then
    vim.schedule(function()
      reply(response)
    end)
  end
  return {
    kill = function(_, signal)
      call.signal = signal
    end,
  }
end

local function prepare(...)
  eq(0, #responses)
  calls, responses = {}, { ... }
end

local function begin(profile, ctx)
  local result = { count = 0 }
  local cancel = backend.request(profile, ctx or context, function(err, text)
    result.err, result.text, result.count = err, text, result.count + 1
  end)
  eq(0, result.count)
  return result, cancel
end

local function wait_for(predicate)
  assert(vim.wait(500, predicate), "mock completion did not arrive")
end

local function run(profile, ctx)
  local result = begin(profile, ctx)
  wait_for(function()
    return result.count > 0
  end)
  eq(1, result.count)
  eq(0, #responses)
  return result.err, result.text
end

local function succeeds(profile, ctx, text)
  local err, result = run(profile, ctx)
  eq(nil, err)
  eq(text or expected, result)
end

local function fails(profile, message, ctx)
  local err, text = run(profile, ctx)
  eq(message, err)
  eq(nil, text)
end

local function ok(stdout, stderr)
  return { code = 0, stdout = stdout, stderr = stderr }
end

local function has(argv, sequence)
  for i = 1, #argv do
    if vim.deep_equal(vim.list_slice(argv, i, i + #sequence - 1), sequence) then
      return true
    end
  end
  return false
end

local function secure(call)
  eq(true, call.opts.clear_env)
  eq(true, call.opts.text)
  for _, name in ipairs({
    "OPENAI_API_KEY",
    "CODEX_API_KEY",
    "CODEX_HOME",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "CLAUDE_CODE_USE_BEDROCK",
    "ANTHROPIC_BASE_URL",
    "HTTPS_PROXY",
    "DOTFILES_AI_TEST_KEY",
  }) do
    eq(nil, call.opts.env[name])
  end
  assert(not table.concat(call.argv, " "):find("dummy", 1, true))
  assert(not table.concat(call.argv, " "):find(context.prefix, 1, true))
end

local credentials = {
  env = { type = "env", name = "DOTFILES_AI_TEST_KEY" },
  keychain = { type = "keychain", service = "test-completion" },
  op = { type = "onepassword", reference = "op://Test/Completion/key" },
}
local cases = {
  {
    name = "openrouter",
    key = vim.env.DOTFILES_AI_TEST_KEY,
    ref = credentials.env,
    url = "https://openrouter.ai/api/v1/chat/completions",
    response = { choices = { { finish_reason = "stop", message = { role = "assistant", content = model_text } } } },
    inspect = function(body)
      eq(false, body.provider.allow_fallbacks)
      eq(context.prefix, vim.json.decode(body.messages[2].content).prefix)
    end,
  },
  {
    name = "openai",
    key = "dummy-keychain-test",
    ref = credentials.keychain,
    helper = { "/mock/security", "find-generic-password", "-s", "test-completion", "-w" },
    url = "https://api.openai.com/v1/responses",
    response = {
      status = "completed",
      output = {
        { type = "reasoning" },
        {
          type = "message",
          role = "assistant",
          status = "completed",
          content = { { type = "output_text", text = model_text } },
        },
      },
    },
    inspect = function(body)
      eq(false, body.store)
      eq("none", body.tool_choice)
      eq(context.suffix, vim.json.decode(body.input).suffix)
    end,
  },
  {
    name = "anthropic",
    key = "dummy-1password-test",
    ref = credentials.op,
    helper = { "/mock/op", "read", "--no-newline", "op://Test/Completion/key" },
    url = "https://api.anthropic.com/v1/messages",
    response = {
      type = "message",
      role = "assistant",
      stop_reason = "end_turn",
      content = { { type = "text", text = model_text } },
    },
    inspect = function(body)
      eq(context.filetype, vim.json.decode(body.messages[1].content).filetype)
    end,
  },
}
for _, case in ipairs(cases) do
  local response = ok(encode(case.response))
  if case.helper then
    prepare(ok(case.key .. "\n"), response)
  else
    prepare(response)
  end
  succeeds({ backend = case.name, model = "test/model:1", key_ref = case.ref, endpoint = "https://ignored.invalid" })
  eq(case.helper and 2 or 1, #calls)
  local curl = calls[#calls]
  if case.helper then
    eq(case.helper, calls[1].argv)
    secure(calls[1])
  end
  secure(curl)
  eq("/mock/curl", curl.argv[1])
  eq("--disable", curl.argv[2])
  assert(has(curl.argv, { "--url", case.url }))
  assert(has(curl.argv, { "--proto", "=https" }))
  assert(has(curl.argv, { "--config", "-" }))
  local headers = {}
  for value in curl.opts.stdin:gmatch("header = ([^\n]+)\n") do
    headers[vim.json.decode(value)] = true
  end
  local auth = case.name == "anthropic" and "x-api-key: " or "Authorization: Bearer "
  eq(true, headers[auth .. case.key])
  if case.name == "anthropic" then
    eq(true, headers["anthropic-version: 2023-06-01"])
  end
  local body = vim.json.decode(vim.json.decode(curl.opts.stdin:match("data%-binary = ([^\n]+)\n")))
  eq("test/model:1", body.model)
  eq(nil, body.tools)
  eq(nil, body.models)
  case.inspect(body)
end

local http = { backend = "openrouter", model = "test", key_ref = credentials.env }
prepare({ code = 22, stderr = "sensitive remote body" })
fails(http, "Completion API request failed")
prepare(ok(encode({ error = { message = "sensitive remote body" } })))
fails(http, "Invalid completion API response")
for _, bad in ipairs({ "```json\n{}\n```", '{"suffix":"e","extra":"x"}', '"not an object"' }) do
  local response = vim.deepcopy(cases[1].response)
  response.choices[1].message.content = bad
  prepare(ok(encode(response)))
  fails(http, "Invalid completion response")
end
for _, bad in ipairs({ "\0", "\27", "a\r", string.char(0xED, 0xA0, 0x80), ("a"):rep(4097) }) do
  local result
  common
    .job(function(err, text)
      result = { err, text }
    end)
    .finish(nil, bad)
  wait_for(function()
    return result ~= nil
  end)
  eq({ "Invalid completion text" }, result)
end
for _, case in ipairs({
  { backend = "openai", payload = { status = "incomplete" } },
  { backend = "openai", payload = { status = "completed", output = { { type = "function_call" } } } },
  { backend = "anthropic", payload = { type = "message", role = "assistant", stop_reason = "tool_use" } },
  {
    backend = "openrouter",
    payload = { choices = { { finish_reason = "length", message = { role = "assistant", content = model_text } } } },
  },
}) do
  prepare(ok(encode(case.payload)))
  fails({ backend = case.backend, model = "test", key_ref = credentials.env }, "Invalid completion response")
end
prepare()
fails({ backend = "does-not-exist" }, "Unknown completion backend")
fails({ backend = "openai", key_ref = credentials.env }, "An API completion model is required")
fails({ backend = "openai", model = "--invalid", key_ref = credentials.env }, "Invalid completion model")
fails({ backend = "openai", model = "test" }, "A completion credential reference is required")
fails({ backend = "codex", key_ref = credentials.env }, "This completion backend uses its own sign-in")
vim.env.DOTFILES_AI_TEST_KEY = "injection\nurl = https://example.invalid"
fails(http, "Completion credential unavailable")
vim.env.DOTFILES_AI_TEST_KEY = "dummy-test-key"
eq(0, #calls)

prepare({ code = 1, stderr = "sensitive helper error" })
fails({ backend = "openai", model = "test", key_ref = credentials.keychain }, "Completion credential unavailable")
eq(1, #calls)
prepare(false)
local pending, cancel = begin({ backend = "openai", model = "test", key_ref = credentials.op })
wait_for(function()
  return #calls == 1
end)
cancel()
cancel()
eq(15, calls[1].signal)
calls[1].reply(ok("dummy-cancelled-key"))
vim.wait(30, function()
  return pending.count ~= 0
end)
eq(0, pending.count)
eq(1, #calls)

local codex = { backend = "codex", model = "test-codex" }
local codex_status = ok("", "Logged in using ChatGPT\n")
local function events(...)
  return table.concat(vim.tbl_map(encode, { ... }), "\n") .. "\n"
end
local codex_message = { type = "item.completed", item = { type = "agent_message", text = model_text } }
local codex_done = { type = "turn.completed" }
prepare(
  codex_status,
  ok(
    events(
      { type = "thread.started" },
      { type = "item.completed", item = { type = "reasoning" } },
      codex_message,
      codex_done
    )
  )
)
succeeds(codex)
eq(2, #calls)
for _, call in ipairs(calls) do
  secure(call)
  assert(has(call.argv, { "-c", 'forced_login_method="chatgpt"' }))
  eq(calls[1].opts.cwd, call.opts.cwd)
  eq(nil, vim.uv.fs_stat(call.opts.cwd))
end
assert(has(calls[1].argv, { "login", "status" }))
assert(has(calls[2].argv, { "-a", "never", "exec" }))
assert(has(calls[2].argv, { "--sandbox", "read-only" }))
assert(has(calls[2].argv, { "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--ephemeral" }))
assert(has(calls[2].argv, { "--model", "test-codex", "-" }))
assert(calls[2].opts.stdin:find(context.prefix, 1, true))
prepare(ok("API key configured - dummy output"))
fails(codex, "Codex ChatGPT sign-in could not be verified")
eq(1, #calls)
prepare(codex_status, ok(events(codex_message)))
fails(codex, "Incomplete Codex response")
prepare(
  codex_status,
  ok(events({ type = "item.completed", item = { type = "command_execution" } }, codex_message, codex_done))
)
fails(codex, "Codex returned a non-completion action")
missing.codex = true
local original_executable = vim.fn.executable
vim.fn.executable = function(path)
  return path == "/Applications/Codex.app/Contents/Resources/codex" and 1 or 0
end
if vim.fn.has("mac") == 1 then
  prepare(codex_status, ok(events(codex_message, codex_done)))
  succeeds(codex)
  eq("/Applications/Codex.app/Contents/Resources/codex", calls[2].argv[1])
end
vim.fn.executable = original_executable
missing.codex = nil

local claude = { backend = "claude", model = "sonnet" }
local subscription = { loggedIn = true, authMethod = "claude.ai", apiProvider = "firstParty", subscriptionType = "max" }
prepare(
  ok(encode(subscription)),
  ok(encode({ type = "result", subtype = "success", is_error = false, result = model_text }))
)
succeeds(claude)
eq(2, #calls)
for _, call in ipairs(calls) do
  secure(call)
  assert(has(call.argv, { "--safe-mode" }))
  assert(has(call.argv, { "--setting-sources", "" }))
  assert(not has(call.argv, { "--bare" }))
  eq(nil, vim.uv.fs_stat(call.opts.cwd))
end
assert(has(calls[1].argv, { "auth", "status", "--json" }))
assert(
  has(
    calls[2].argv,
    { "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}' }
  )
)
assert(has(calls[2].argv, { "--model", "sonnet" }))
eq(context.prefix, vim.json.decode(calls[2].opts.stdin).prefix)
for _, changes in ipairs({
  { apiProvider = "bedrock" },
  { authMethod = "oauth_token" },
  { subscriptionType = vim.NIL },
  { apiKeySource = "helper" },
}) do
  prepare(ok(encode(vim.tbl_extend("force", subscription, changes))))
  fails(claude, "Claude Code subscription sign-in could not be verified")
  eq(1, #calls)
end
prepare(ok(encode(subscription)), ok(encode({ is_error = true, result = "private server output" })))
fails(claude, "Invalid Claude Code completion response")
missing.claude = true
prepare()
fails(claude, "The Claude Code CLI is not installed")
eq(0, #calls)

prepare(false)
local timed_out = {}
local job = common.job(function(err, text)
  timed_out = { err, text }
end)
job.deadline(10)
job.run({ "/mock/idle" }, {}, function()
  error("unexpected process callback")
end)
wait_for(function()
  return #timed_out > 0
end)
eq({ "Completion request timed out" }, timed_out)
eq(15, calls[1].signal)

print("backend subprocess tests passed")
