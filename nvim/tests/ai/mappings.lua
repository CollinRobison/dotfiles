-- Run with: nvim --clean --headless -i NONE -l nvim/tests/ai/mappings.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p", 448)
local job = vim.fn.jobstart({ vim.v.progpath, "--clean", "--embed", "--headless", "-i", "NONE" }, {
  rpc = true,
  env = { XDG_STATE_HOME = temp, NVIM_AI_PROFILE_FILE = vim.fs.joinpath(temp, "profiles.json") },
})
assert(job > 0)

local function call(method, ...)
  return vim.rpcrequest(job, method, ...)
end

local function lua(code, args)
  return call("nvim_exec_lua", code, args or {})
end

local function step(keys)
  call("nvim_input", keys)
end

local function await(predicate, message)
  assert(vim.wait(1200, predicate, 15), message)
end

local function emulated_requests()
  return lua("return #TestRequests")
end

local function lines()
  return call("nvim_buf_get_lines", 0, 0, -1, true)
end

local function test()
  lua(
    [[
    vim.opt.rtp:prepend(...)
    vim.g.mapleader = " "
    vim.o.completeopt = "menuone,noselect"
    package.loaded['which-key'] = { add = function() end }
    TestRequests, TestCompanion = {}, {}
    package.loaded['collin.ai.backends'] = {
      request = function(profile, ctx, done)
        local request = { profile = profile.id, ctx = ctx, done = done }
        table.insert(TestRequests, request)
        return function() request.cancelled = true end
      end,
    }
    local function capture(action)
      return function(profile)
        table.insert(TestCompanion, {
          action = action, profile = profile.id, mode = vim.api.nvim_get_mode().mode,
        })
      end
    end
    package.loaded['collin.ai.companion'] = { ask = capture('ask'), edit = capture('edit'), chat = capture('chat') }
    require('collin.ai').setup()
  ]],
    { root }
  )
  lua("return vim.api.nvim_buf_set_lines(0, 0, -1, true, { 'return ;' })")
  call("nvim_win_set_cursor", 0, { 1, 7 })
  step("i")
  await(function()
    return call("nvim_get_mode").mode == "i"
  end, "enter insert mode")
  step("x<BS>")
  await(function()
    return lines()[1] == "return ;"
  end, "ordinary input restored")
  assert(emulated_requests() == 0, "ordinary typing must not request AI")
  lua("vim.fn.complete(8, { 'local completion', 'other completion' })")
  await(function()
    return lua("return vim.fn.pumvisible()") == 1
  end, "native completion menu before AI")
  step("<M-]>")
  await(function()
    return emulated_requests() == 1
  end, "AI mapping requests once")
  assert(lua("return vim.fn.pumvisible()") == 0, "AI shortcut must clear the popup")
  assert(lua("return TestRequests[1].ctx.col") == 7, "capture original insertion point")
  lua("TestRequests[1].done(nil, '42')")
  await(function()
    return lua(
      [[local mark = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()['collin.ai.completion'], 0, -1, { details = true })[1]
      return mark ~= nil and mark[4].virt_text_pos == 'inline']]
    )
  end, "display the ghost-text extmark")
  assert(lines()[1] == "return ;")
  step("<M-a>")
  await(function()
    return lines()[1] == "return 42;"
  end, "accept mapping inserts only the suggestion")
  step("<M-]>")
  await(function()
    return emulated_requests() == 2
  end, "start another completion")
  step("<C-c>")
  await(function()
    return call("nvim_get_mode").mode == "n" and lua("return TestRequests[2].cancelled")
  end, "leaving insert mode with CTRL-C invalidates the request")
  assert(lines()[1] == "return 42;")
  step("V aq")
  await(function()
    return lua("return #TestCompanion") == 1
  end, "visual Ask reaches CodeCompanion adapter")
  step("<Esc>V ae")
  await(function()
    return lua("return #TestCompanion") == 2
  end, "visual Edit reaches CodeCompanion adapter")
  step("<Esc> ac")
  await(function()
    return lua("return #TestCompanion") == 3
  end, "normal Chat reaches CodeCompanion adapter")
  local requests = lua("return TestCompanion")
  assert(requests[1].action == "ask" and requests[1].mode == "V")
  assert(requests[2].action == "edit" and requests[2].mode == "V")
  assert(requests[3].action == "chat" and requests[3].mode == "n")
  assert(requests[1].profile == "codex-chatgpt" and requests[2].profile == "codex-chatgpt")
end

local ok, err = xpcall(test, debug.traceback)
pcall(vim.fn.jobstop, job)
vim.fn.jobwait({ job }, 1000)
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
print("AI keybindings: real Neovim input, LSP popup handoff, and visual routes passed")
