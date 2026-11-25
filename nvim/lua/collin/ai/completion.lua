local M = {}
local namespace = vim.api.nvim_create_namespace("collin.ai.completion")
local active
local max_context_bytes = 2400
local context_lines = 12

local function insert_mode()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

local function same_cursor(request)
  return vim.api.nvim_get_current_win() == request.winid
    and vim.api.nvim_get_current_buf() == request.bufnr
    and vim.deep_equal(vim.api.nvim_win_get_cursor(request.winid), request.cursor)
end

local function current(request)
  return active == request
    and insert_mode()
    and same_cursor(request)
    and vim.api.nvim_buf_get_changedtick(request.bufnr) == request.changedtick
end

function M.clear()
  local request = active
  active = nil
  if not request then
    return
  end
  if request.cancel then
    pcall(request.cancel)
  end
  if vim.api.nvim_buf_is_valid(request.bufnr) then
    vim.api.nvim_buf_clear_namespace(request.bufnr, namespace, 0, -1)
  end
end

function M.normal_buffer(bufnr)
  if vim.bo[bufnr].buftype ~= "" or not vim.bo[bufnr].modifiable then
    return false
  end
  local name = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)):lower()
  -- This is a short denylist of common credential files, not a DLP guarantee.
  return name ~= ".envrc"
    and name ~= "auth.json"
    and name ~= "credentials.json"
    and name ~= ".netrc"
    and name ~= ".npmrc"
    and not name:match("^id_[%w_]+$")
    and not name:match("^%.env[%.%w_-]*$")
    and not name:match("%.pem$")
    and not name:match("%.key$")
end

local function continuation_byte(byte)
  return byte and byte >= 128 and byte < 192
end

local function keep_tail(text)
  local first = math.max(1, #text - max_context_bytes + 1)
  while continuation_byte(text:byte(first)) do
    first = first + 1
  end
  return text:sub(first)
end

local function keep_head(text)
  local after = math.min(#text, max_context_bytes) + 1
  while continuation_byte(text:byte(after)) do
    after = after - 1
  end
  return text:sub(1, after - 1)
end

local function context(request)
  local bufnr = request.bufnr
  local row, col = request.cursor[1] - 1, request.cursor[2]
  local first = math.max(0, row - context_lines)
  local after = math.min(vim.api.nvim_buf_line_count(bufnr), row + context_lines + 1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, after, true)
  local index = row - first + 1
  local line = lines[index]
  local prefix = table.concat(lines, "\n", 1, index - 1)
  local suffix = table.concat(lines, "\n", index + 1)
  if index > 1 then
    prefix = prefix .. "\n"
  end
  if index < #lines then
    suffix = "\n" .. suffix
  end
  return {
    bufnr = bufnr,
    row = row,
    col = col,
    line = line,
    prefix = keep_tail(prefix .. line:sub(1, col)),
    suffix = keep_head(line:sub(col + 1) .. suffix),
    cwd = vim.fn.getcwd(),
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
  }
end

local function mark(request, text, highlight, position)
  return vim.api.nvim_buf_set_extmark(request.bufnr, namespace, request.cursor[1] - 1, request.cursor[2], {
    virt_text = { { text, highlight } },
    virt_text_pos = position,
    hl_mode = "combine",
  })
end

function M.request()
  if not insert_mode() then
    return
  end
  M.clear()
  local bufnr = vim.api.nvim_get_current_buf()
  if not M.normal_buffer(bufnr) then
    vim.notify("AI completion is unavailable in this buffer.", vim.log.levels.WARN)
    return
  end
  local profile = require("collin.ai.profiles").current("completion")
  if not profile then
    vim.notify("AI completion profile is unavailable. Choose one with :AICompletionProvider.", vim.log.levels.WARN)
    return
  end
  local request = {
    winid = vim.api.nvim_get_current_win(),
    bufnr = bufnr,
    cursor = vim.api.nvim_win_get_cursor(0),
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
  }
  active = request
  mark(request, "  AI: waiting…", "DiagnosticHint", "eol")
  local done = vim.schedule_wrap(function(err, suffix)
    if not current(request) then
      if active == request then
        M.clear()
      end
      return
    end
    request.cancel = nil
    if err then
      M.clear()
      vim.notify("AI completion: " .. err, vim.log.levels.WARN)
      return
    end
    if
      type(suffix) ~= "string"
      or not suffix:match("%S")
      or #suffix > 512
      or suffix:find("[%c]")
      or suffix:find("```", 1, true)
      or suffix:find("<CURSOR>", 1, true)
    then
      M.clear()
      vim.notify("AI completion returned no valid single-line insertion.", vim.log.levels.INFO)
      return
    end
    vim.api.nvim_buf_clear_namespace(request.bufnr, namespace, 0, -1)
    request.suffix = suffix
    mark(request, suffix, "Comment", "inline")
  end)
  local ok, cancel = pcall(function()
    return require("collin.ai.backends").request(profile, context(request), done)
  end)
  if ok then
    request.cancel = cancel
  else
    -- Backend exceptions can contain response bodies or request configuration.
    done("backend failed to start; check the selected provider setup.")
  end
end

function M.accept()
  local request = active
  if not request or not request.suffix or not current(request) then
    return
  end
  local row, col = request.cursor[1] - 1, request.cursor[2]
  M.clear()
  if not vim.bo[request.bufnr].modifiable then
    return
  end
  vim.api.nvim_buf_set_text(request.bufnr, row, col, row, col, { request.suffix })
  vim.api.nvim_win_set_cursor(request.winid, { row + 1, col + #request.suffix })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("CollinAICompletion", { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "InsertLeave", "InsertCharPre", "CmdlineEnter" }, {
    group = group,
    callback = M.clear,
  })
  -- CTRL-C can leave Insert mode without firing InsertLeave.
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      if active and not insert_mode() then
        M.clear()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMovedI", "TextChangedI", "TextChangedP", "TextChanged", "BufUnload" }, {
    group = group,
    callback = function(event)
      if active and event.buf == active.bufnr and (event.event == "BufUnload" or not current(active)) then
        M.clear()
      end
    end,
  })
end

return M
