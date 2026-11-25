local M = {}
local api = vim.api

local function dirty(path)
  local real = vim.uv.fs_realpath(path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      local name = api.nvim_buf_get_name(buf)
      if name == path or (real and name ~= "" and vim.uv.fs_realpath(name) == real) then
        return true
      end
    end
  end
  return false
end

local function deny(request)
  request.respond(nil, true)
end

function M.refresh(connection)
  local paths = connection.dotfiles_pi_writes
  connection.dotfiles_pi_writes = nil
  if not paths then
    return
  end
  vim.schedule(function()
    for _, buf in ipairs(api.nvim_list_bufs()) do
      local name = api.nvim_buf_get_name(buf)
      if
        api.nvim_buf_is_loaded(buf)
        and name ~= ""
        and not vim.bo[buf].modified
        and (paths[name] or paths[vim.uv.fs_realpath(name)])
      then
        pcall(vim.cmd.checktime, { args = { tostring(buf) } })
      end
    end
  end)
end

function M.review(connection, id, params)
  local request = connection:build_permission_request({ id = id, params = params })
  local tool = request.tool_call or {}
  local raw = tool.rawInput or {}
  if
    not connection._active_prompt
    or request.session_id ~= connection.session_id
    or raw.method ~= "confirm"
    or type(raw.message) ~= "string"
    or #raw.message > 1600000
  then
    return deny(request)
  end
  local yes = vim.iter(request.options):find(function(option)
    return option.kind == "allow_once" and option.optionId == "yes"
  end)
  local ok, payload = pcall(vim.json.decode, raw.message)
  if not yes or not ok or type(payload) ~= "table" then
    return deny(request)
  end
  local function answer(allowed)
    if connection.session_id == request.session_id and connection._active_prompt then
      request.respond(allowed and yes.optionId or nil, not allowed)
    else
      deny(request)
    end
  end
  if tool.title == "Run Pi workspace command" then
    if type(payload.command) ~= "string" or #payload.command > 1024 then
      return deny(request)
    end
    return vim.ui.select({ "Reject", "Run once" }, {
      prompt = "Pi (read-only workspace, no network): " .. vim.json.encode(payload.command),
    }, function(choice)
      answer(choice == "Run once")
    end)
  end
  local path, before, after = payload.path, payload.before, payload.after
  local operation, destination = payload.operation, payload.destination
  local root = connection.adapter.dotfiles_env.NVIM_AI_PI_ROOT
  local labels = {
    create = "Create file",
    edit = "Edit file",
    delete = "Delete file",
    mkdir = "Create directory",
    move = "Move file",
  }
  local function valid_path(value)
    return type(root) == "string"
      and type(value) == "string"
      and not value:find("%c")
      and vim.startswith(value, root .. "/")
      and vim.fs.normalize(value) == value
  end
  local needs_text = operation == "edit" or operation == "create" or operation == "delete"
  if
    tool.title ~= "Review Pi workspace change"
    or not labels[operation]
    or not valid_path(path)
    or (operation == "move" and (not valid_path(destination) or destination == path))
    or (needs_text and (type(before) ~= "string" or type(after) ~= "string" or #before > 128000 or #after > 128000))
    or (operation == "edit" and before == after)
    or (operation == "delete" and after ~= "")
    or (operation == "create" and before ~= "")
  then
    return deny(request)
  end
  local function check_buffer()
    local blocked = dirty(path) and path or (operation == "move" and dirty(destination) and destination)
    if not blocked then
      return true
    end
    vim.notify("Save or discard your unsaved changes before letting Pi change: " .. blocked, vim.log.levels.WARN)
    return false
  end
  local function approve()
    local allowed = check_buffer()
    if allowed and request.is_pending() then
      connection.dotfiles_pi_writes = connection.dotfiles_pi_writes or {}
      connection.dotfiles_pi_writes[path] = true
      if operation == "move" then
        connection.dotfiles_pi_writes[destination] = true
      end
    end
    answer(allowed)
  end
  if not check_buffer() then
    return deny(request)
  end
  local title = labels[operation] .. " · " .. path:sub(#root + 2)
  if not needs_text or before == after then
    if operation == "move" then
      title = title .. " → " .. destination:sub(#root + 2)
    end
    return vim.ui.select({ "Reject", "Approve once" }, { prompt = "Pi: " .. title }, function(choice)
      if choice == "Approve once" then
        approve()
      else
        deny(request)
      end
    end)
  end
  local function lines(text)
    return vim.split(text, "\n", { plain = true })
  end
  local review
  local shown = pcall(function()
    review = require("codecompanion.helpers").show_diff({
      from_lines = lines(before),
      to_lines = lines(after),
      ft = vim.filetype.match({ filename = path }) or "text",
      title = "Pi · " .. title,
      banner = "g2 approve change once | g3 or q reject",
      keymaps = {
        on_accept = approve,
        on_reject = function()
          deny(request)
        end,
      },
    })
    api.nvim_create_autocmd("BufWipeout", {
      buffer = review.bufnr,
      once = true,
      callback = function()
        deny(request)
      end,
    })
    vim.keymap.set("n", "q", function()
      deny(request)
      review:close()
    end, { buffer = review.bufnr, desc = "Reject Pi write" })
    -- Pi must never inherit a chat's always-approve choice.
    local always = require("codecompanion.config").interactions.shared.keymaps.always_accept.modes.n
    if always then
      pcall(vim.keymap.del, "n", always, { buffer = review.bufnr })
    end
  end)
  if not shown then
    deny(request)
    if review then
      pcall(review.close, review)
    end
  end
end

return M
