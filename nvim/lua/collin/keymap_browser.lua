local M = {}

local function python()
  if vim.env.NVIM_KEYMAPS_PYTHON then return { vim.env.NVIM_KEYMAPS_PYTHON } end
  if vim.fn.has("win32") == 1 then
    if vim.fn.executable("py") == 1 then return { "py", "-3" } end
    return { "python" }
  end
  return { "python3" }
end

function M.register()
  local module_path = debug.getinfo(1, "S").source:sub(2)
  local config = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(module_path)))
  local browser = vim.fs.joinpath(config, "scripts", "keymap-browser")

  local function launch(atlas)
    local cmd = python()
    vim.list_extend(cmd, { "-B", vim.fs.joinpath(browser, "server.py") })
    local snapshot
    if atlas then
      vim.list_extend(cmd, { "--atlas", "--open" })
      vim.notify("Regenerating the Neovim Atlas…")
    else
      snapshot = vim.fn.tempname()
      local collected = dofile(vim.fs.joinpath(browser, "runtime.lua")).snapshot()
      vim.fn.writefile({ vim.json.encode(collected) }, snapshot)
      vim.list_extend(cmd, { "--foreground", "--snapshot", snapshot })
    end
    local errors = {}
    local ok, job = pcall(vim.fn.jobstart, cmd, {
      detach = not atlas,
      env = { NVIM_KEYMAPS_NVIM = vim.v.progpath },
      stderr_buffered = true,
      on_stderr = function(_, lines) errors = lines end,
      on_exit = function(_, code)
        if code ~= 0 then
          local message = vim.trim(table.concat(errors, "\n"))
          vim.notify(message ~= "" and message or "Keymaps exited with status " .. code, vim.log.levels.ERROR)
        elseif atlas then
          vim.notify("Neovim Atlas regenerated")
        end
        if snapshot then vim.fn.delete(snapshot) end
      end,
    })
    if not ok or job <= 0 then
      if snapshot then vim.fn.delete(snapshot) end
      vim.notify("Could not launch Keymaps. Check that Python 3 is available.", vim.log.levels.ERROR)
    end
  end

  vim.api.nvim_create_user_command("Keymaps", function() launch(false) end,
    { desc = "Browse and edit Neovim keybindings" })
  vim.api.nvim_create_user_command("KeymapAtlas", function() launch(true) end,
    { desc = "Regenerate and open the Neovim keybinding PDF" })
end

return M
