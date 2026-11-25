-- Run from the repository root: nvim --headless -u NONE -l nvim/tests/ai/backends_copilot_spec.lua
vim.opt.rtp:prepend("nvim")
local backend = require("collin.ai.backends")
local eq = function(expected, actual)
  assert(vim.deep_equal(expected, actual), ("expected %s; got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end
local function wait_for(predicate)
  assert(vim.wait(500, predicate), "mock Copilot completion did not arrive")
end

local spec = require("collin.lazy.copilot")
local has_copilot = false
package.loaded["collin.ai.profiles"] = {
  has_backend = function(name, use)
    eq("copilot", name)
    eq("completion", use)
    return has_copilot
  end,
}
eq(false, spec.enabled())
has_copilot = true
eq(true, spec.enabled())
eq(false, spec.opts.should_attach())
eq(false, spec.opts.suggestion.enabled)
eq(false, spec.opts.suggestion.auto_trigger)
eq(false, spec.opts.panel.enabled)
eq(false, spec.opts.nes.enabled)

local cwd = vim.uv.cwd()
local bufnr = vim.api.nvim_create_buf(true, false)
local filename = cwd .. "/copilot-test.lua"
vim.api.nvim_buf_set_name(bufnr, filename)
vim.bo[bufnr].shiftwidth = 3
vim.bo[bufnr].expandtab = true
local line = "pré🙂尾)"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "-- first line", line })
local context = { bufnr = bufnr, row = 1, col = #"pré🙂", line = line, filename = filename, cwd = cwd }
local attached, attaches, detaches
local requests, notifications, cancellations
local plugin, client
client = {
  id = 123,
  request = function(_, method, params, reply, buf)
    eq(bufnr, buf)
    requests[#requests + 1] = { method = method, params = params, reply = reply }
    return true, #requests
  end,
  notify = function(_, method, params)
    notifications[#notifications + 1] = { method = method, params = params }
    return true
  end,
  cancel_request = function(_, id)
    cancellations[#cancellations + 1] = id
  end,
}
vim.lsp.buf_is_attached = function(buf, id)
  eq(bufnr, buf)
  eq(client.id, id)
  return attached
end
vim.lsp.buf_attach_client = function(buf, id)
  eq(bufnr, buf)
  eq(client.id, id)
  eq(nil, client.server_capabilities.completionProvider)
  attached, attaches = true, attaches + 1
  return true
end
vim.lsp.buf_detach_client = function(buf, id)
  eq(bufnr, buf)
  eq(client.id, id)
  attached, detaches = false, detaches + 1
end
plugin = {
  get = function()
    return client
  end,
  is_disabled = function()
    return false
  end,
}
package.loaded["copilot.client"] = plugin

local function prepare()
  eq(false, attached or false)
  requests, notifications, cancellations = {}, {}, {}
  attached, attaches, detaches = false, 0, 0
  client.server_capabilities = { completionProvider = {} }
  plugin.initialized = true
  plugin.startup_error = nil
end

local function begin(model, ctx)
  local result = { count = 0 }
  local cancel = backend.request({ backend = "copilot", model = model }, ctx or context, function(err, text)
    result.err, result.text, result.count = err, text, result.count + 1
  end)
  eq(0, result.count)
  return result, cancel
end

local function done(result, err, text)
  wait_for(function()
    return result.count ~= 0
  end)
  eq({ count = 1, err = err, text = text }, result)
end

local function item(first, last, replacement)
  return {
    text = replacement,
    range = { start = { line = 1, character = first }, ["end"] = { line = 1, character = last } },
  }
end

prepare()
plugin.initialized = false
local result = begin("test-model")
vim.defer_fn(function()
  plugin.initialized = true
end, 20)
wait_for(function()
  return #requests == 1
end)
eq("copilot/models", requests[1].method)
eq(vim.empty_dict(), requests[1].params)
requests[1].reply(nil, { { id = "test-model", scopes = { "completion" } } })
wait_for(function()
  return #requests == 2
end)
local settings = notifications[1]
eq("workspace/didChangeConfiguration", settings.method)
eq("test-model", settings.params.settings.github.copilot.selectedCompletionModel)
eq(false, settings.params.settings.enableAutoCompletions)
local req = requests[2]
eq("getCompletions", req.method)
eq({ line = 1, character = 5 }, req.params.position)
eq(req.params.position, req.params.doc.position)
eq(vim.uri_from_bufnr(bufnr), req.params.textDocument.uri)
eq("copilot-test.lua", req.params.textDocument.relativePath)
eq(vim.api.nvim_buf_get_changedtick(bufnr), req.params.doc.version)
eq(3, req.params.doc.tabSize)
eq(3, req.params.doc.indentSize)
eq(true, req.params.doc.insertSpaces)
req.reply(nil, {
  completions = {
    item(4, 7, "🙂corrupt-surrogate尾)"), -- UTF-16 column 4 splits 🙂.
    item(1, 7, "replaces existing code"),
    item(1, 7, "ré🙂\tnew🙂\r\n尾)"),
  },
})
done(result, nil, "\tnew🙂\n")
eq(1, attaches)
eq(1, detaches)
eq({}, cancellations)

prepare()
result = begin("unknown-model")
wait_for(function()
  return #requests == 1
end)
requests[1].reply(nil, { { id = "unknown-model", scopes = { "chat" } } })
done(result, "The configured Copilot completion model is unavailable")
eq(1, #requests)
eq(1, detaches)

prepare()
result = begin(nil)
wait_for(function()
  return #requests == 1
end)
eq("", notifications[1].params.settings.github.copilot.selectedCompletionModel)
local multiline = item(1, 7, "ré🙂\nspurious尾)")
multiline.range.start.line = 0
requests[1].reply(nil, { completions = { item(0, 7, line), multiline, { displayText = "untrusted" } } })
done(result, nil, nil)

prepare()
local cancel
result, cancel = begin(nil)
wait_for(function()
  return #requests == 1
end)
cancel()
cancel()
requests[1].reply(nil, { completions = { item(5, 5, "must not be delivered") } })
vim.wait(30, function()
  return result.count ~= 0
end)
eq(0, result.count)
eq({ 1 }, cancellations)
eq(1, detaches)

prepare()
result = begin(nil)
wait_for(function()
  return #requests == 1
end)
vim.api.nvim_buf_set_lines(bufnr, 0, 1, true, { "-- changed other context" })
requests[1].reply(nil, { completions = { item(5, 5, "stale") } })
done(result, nil, nil)

prepare()
result = begin(nil)
wait_for(function()
  return #requests == 1
end)
requests[1].reply({ message = "private token in error" })
done(result, "Copilot completion request failed; check :Copilot status")

prepare()
result = begin(nil, vim.tbl_extend("force", context, { col = context.col - 1 }))
done(result, "Invalid Copilot cursor column")
eq(0, attaches)

prepare()
package.loaded["copilot.client"] = nil
package.preload["copilot.client"] = function()
  error("mock unavailable plugin")
end
result = begin(nil)
done(result, "The Copilot plugin is not available")
eq(0, attaches)

print("backend Copilot tests passed")
