local M = {}
local modes = { "n", "x", "s", "o", "i", "l", "c", "t" }

function M.snapshot()
  local data = {
    rows = {}, modified = {}, leader = vim.g.mapleader or "\\", localleader = vim.g.maplocalleader or "\\",
  }
  local scripts = {}
  for _, item in ipairs(vim.fn.getscriptinfo()) do
    scripts[item.sid] = item.name
  end
  local function add(maps, mode, scope, context)
    for _, map in ipairs(maps) do
      local source = scripts[map.sid]
      local callback = type(map.callback) == "function" and debug.getinfo(map.callback, "S")
      if callback and callback.source:sub(1, 1) == "@" and not source then
        source = callback.source:sub(2)
      end
      data.rows[#data.rows + 1] = {
        mode = mode, key = map.lhs, rhs = map.rhs, desc = map.desc,
        file = source, line = map.lnum, scope = scope, context = context,
      }
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      local name = vim.uv.fs_realpath(vim.api.nvim_buf_get_name(buf))
      if name then data.modified[#data.modified + 1] = name end
    end
  end
  data.lsp_clients = #vim.lsp.get_clients()
  data.filetype = vim.bo.filetype
  data.buffer_lsp = #vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() }) > 0
  for _, mode in ipairs(modes) do
    add(vim.api.nvim_get_keymap(mode), mode, "", "Global")
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local ft = vim.bo[buf].filetype
        local context = ft ~= "" and ft .. " buffer" or "Buffer-local"
        add(vim.api.nvim_buf_get_keymap(buf, mode), mode, ft ~= "" and ft or "*", context)
      end
    end
  end
  return data
end

if vim.env.KEYMAP_PROBE_OUT then
  vim.schedule(function()
    local baseline = M.snapshot()
    local probes = {
      { vim.env.KEYMAP_PROBE_DIR .. "/guide.md", "markdown" },
      { vim.env.KEYMAP_PROBE_DIR .. "/diagram.mmd", "mermaid" },
    }
    for _, probe in ipairs(probes) do
      pcall(vim.cmd.edit, vim.fn.fnameescape(probe[1]))
      if vim.bo.filetype == "" then pcall(vim.cmd.setfiletype, probe[2]) end
    end
    pcall(vim.cmd.copen)
    pcall(vim.cmd.help, "help")
    if vim.fn.exists(":NvimTreeOpen") == 2 then pcall(vim.cmd.NvimTreeOpen) end
    if vim.fn.exists(":Telescope") == 2 then
      -- Opening the picker registers its local mappings before taking the snapshot.
      pcall(vim.cmd, "Telescope buffers")
    end
    local data = M.snapshot()
    vim.list_extend(data.rows, baseline.rows)
    vim.fn.writefile({ vim.json.encode(data) }, vim.env.KEYMAP_PROBE_OUT)
    vim.cmd("qa!")
  end)
end

return M
