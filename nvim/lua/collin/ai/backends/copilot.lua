local M = {}
local busy = false

-- getCompletions uses UTF-16 even though the controller uses byte offsets.
-- Round-trip to reject invalid columns and positions inside surrogate pairs.
local function byte_index(line, col)
  if type(col) ~= "number" or col < 0 or col % 1 ~= 0 then
    return nil
  end
  local ok, byte = pcall(vim.str_byteindex, line, "utf-16", col, true)
  if ok and vim.str_utfindex(line, "utf-16", byte, true) == col then
    return byte
  end
end

local function insertion(item, context)
  if type(item) ~= "table" or type(item.text) ~= "string" or type(item.range) ~= "table" then
    return nil
  end
  local first, last = item.range.start, item.range["end"]
  if type(first) ~= "table" or type(last) ~= "table" or first.line ~= context.row or last.line ~= context.row then
    return nil
  end
  local line, cursor = context.line, context.col
  local left, right = byte_index(line, first.character), byte_index(line, last.character)
  if not left or not right or left > cursor or right < cursor then
    return nil
  end
  local before, after = line:sub(left + 1, cursor), line:sub(cursor + 1, right)
  local text = item.text
  local last_inserted = #text - #after
  if last_inserted > #before and text:sub(1, #before) == before and text:sub(last_inserted + 1) == after then
    return text:sub(#before + 1, last_inserted)
  end
end

local function rpc(client, bufnr, job, method, params, callback)
  local replied = false
  local sent, id = client:request(method, params, function(err, result)
    replied = true
    vim.schedule(job.guard(function()
      if err then
        return job.finish("Copilot completion request failed; check :Copilot status")
      end
      callback(result)
    end))
  end, bufnr)
  if not sent then
    return job.finish("Copilot completion request could not be sent")
  end
  if id then
    job.on_stop(function()
      if not replied then
        client:cancel_request(id)
      end
    end)
  end
end

function M.request(profile, context, job)
  if busy then
    return job.finish("Copilot is already completing")
  end
  local ok, plugin = pcall(require, "copilot.client")
  if not ok then
    return job.finish("The Copilot plugin is not available")
  end
  busy = true
  job.on_stop(function()
    busy = false
  end)
  local bufnr = context.bufnr
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" then
    return job.finish(nil)
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local function current()
    return vim.api.nvim_buf_is_loaded(bufnr)
      and vim.api.nvim_buf_get_changedtick(bufnr) == tick
      and vim.api.nvim_buf_get_lines(bufnr, context.row, context.row + 1, true)[1] == context.line
  end

  local function start()
    if not current() then
      return job.finish(nil)
    end
    if plugin.startup_error or plugin.is_disabled() then
      return job.finish("Copilot is not available; check :Copilot status")
    end
    local client = plugin.get()
    if not client or not plugin.initialized then
      vim.defer_fn(job.guard(start), 50)
      return
    end

    local character = vim.str_utfindex(context.line, "utf-16", context.col, true)
    if byte_index(context.line, character) ~= context.col then
      return job.finish("Invalid Copilot cursor column")
    end
    -- Only attach while an explicit request needs document synchronization.
    -- Do not register ordinary LSP completion or compete with the existing popup.
    client.server_capabilities.completionProvider = nil
    if not vim.lsp.buf_is_attached(bufnr, client.id) then
      if not vim.lsp.buf_attach_client(bufnr, client.id) then
        return job.finish("Could not open the Copilot completion document")
      end
      job.on_stop(function()
        if vim.api.nvim_buf_is_valid(bufnr) and vim.lsp.buf_is_attached(bufnr, client.id) then
          vim.lsp.buf_detach_client(bufnr, client.id)
        end
      end)
    end

    local function complete()
      if not current() then
        return job.finish(nil)
      end
      -- Copilot exposes model choice as a server setting, not a request field.
      -- One in-flight request avoids racing two model selections.
      if
        not client:notify("workspace/didChangeConfiguration", {
          settings = {
            github = { copilot = { selectedCompletionModel = profile.model or "" } },
            enableAutoCompletions = false,
            disabledLanguages = {},
          },
        })
      then
        return job.finish("Could not configure Copilot completion")
      end
      local text_document = {
        uri = vim.uri_from_bufnr(bufnr),
        version = tick,
        relativePath = vim.fs.relpath(context.cwd, filename) or vim.fs.basename(filename),
      }
      local position = { line = context.row, character = character }
      local width = vim.api.nvim_buf_call(bufnr, vim.fn.shiftwidth)
      local doc = vim.tbl_extend("force", text_document, {
        position = position,
        insertSpaces = vim.bo[bufnr].expandtab,
        tabSize = width,
        indentSize = width,
      })
      rpc(
        client,
        bufnr,
        job,
        "getCompletions",
        { doc = doc, textDocument = text_document, position = position },
        function(result)
          if not current() then
            return job.finish(nil)
          end
          if type(result) ~= "table" or not vim.islist(result.completions) then
            return job.finish("Invalid Copilot completion response")
          end
          for _, item in ipairs(result.completions) do
            local suffix = insertion(item, context)
            if suffix then
              return job.finish(nil, suffix)
            end
          end
          job.finish(nil)
        end
      )
    end

    if not profile.model then
      return complete()
    end
    rpc(client, bufnr, job, "copilot/models", vim.empty_dict(), function(models)
      if vim.islist(models) then
        for _, model in ipairs(models) do
          if
            type(model) == "table"
            and model.id == profile.model
            and vim.islist(model.scopes)
            and vim.tbl_contains(model.scopes, "completion")
          then
            return complete()
          end
        end
      end
      job.finish("The configured Copilot completion model is unavailable")
    end)
  end
  start()
end

return M
