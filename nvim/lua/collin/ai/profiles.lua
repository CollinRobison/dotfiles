local M = {}

local supported = {
  codex = { completion = true, companion = true, inline_edit = true },
  copilot = { companion = true, inline_edit = true },
  claude = { completion = true, companion = true },
  pi = { completion = true, companion = true, inline_edit = true },
  openrouter = { completion = true, companion = true, http = true },
  openai = { completion = true, companion = true, http = true },
  anthropic = { completion = true, companion = true, http = true },
}

local default_id = "codex-chatgpt"
local default_profile = {
  id = default_id,
  label = "Codex · ChatGPT subscription",
  backend = "codex",
  completion = true,
  companion = true,
  inline_edit = true,
}
local workflows = { completion = true, companion = true }
local directory = vim.fs.joinpath(vim.fn.stdpath("config"), "ai-workflows")
local profile_path = vim.env.NVIM_AI_PROFILE_FILE or vim.fs.joinpath(directory, "profiles.json")
local selection_path = vim.fs.joinpath(directory, "selection.json")
local profiles, selections, profile_error

local function read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, value = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if ok and type(value) == "table" then
    return value
  end
  return nil, true
end

local function matches(value, pattern, limit)
  return type(value) == "string" and #value <= limit and value:match(pattern) ~= nil
end

local function key_reference(input)
  if type(input) ~= "table" then
    return nil
  end
  -- Whitelist the reference fields; never retain a plaintext value from the config.
  if input.type == "env" and matches(input.name, "^[A-Z_][A-Z_0-9]*$", 90) then
    return { type = "env", name = input.name }
  elseif input.type == "keychain" and matches(input.service, "^[%w][%w_.%-]*$", 120) then
    return { type = "keychain", service = input.service }
  elseif input.type == "onepassword" and matches(input.reference, "^op://[^%c]+$", 240) then
    return { type = "onepassword", reference = input.reference }
  end
end

local function normalize(input)
  if type(input) ~= "table" or not matches(input.id, "^[%w][%w_.%-]*$", 60) then
    return nil
  end
  local caps = type(input.backend) == "string" and supported[input.backend]
  if not caps then
    return nil
  end
  if input.model ~= nil and not matches(input.model, "^[%w][%w._:/@%[%]%-]*$", 120) then
    return nil
  end
  if input.backend == "pi" and not matches(input.model, "^[%w._-]+/[%w][%w._:/@%[%]%-]*$", 120) then
    return nil
  end
  local ref = caps.http and key_reference(input.key_ref) or nil
  if caps.http and (not ref or not input.model) then
    return nil
  end
  if input.key_ref ~= nil and not caps.http then
    return nil
  end
  local completion = input.completion == true and caps.completion or false
  local companion = input.companion == true and caps.companion or false
  if not completion and not companion then
    return nil
  end
  return {
    id = input.id,
    label = matches(input.label, "^[^%c]+$", 100) and input.label or input.id,
    backend = input.backend,
    model = input.model,
    key_ref = ref,
    http = caps.http or false,
    completion = completion,
    companion = companion,
    inline_edit = companion and (caps.inline_edit or false),
  }
end

local function load()
  if profiles then
    return
  end
  profiles = { default_profile }
  local loaded, invalid = read_json(profile_path)
  if invalid or (loaded and not vim.islist(loaded)) then
    profile_error = "AI profiles: expected a JSON array; check the local profile file."
  elseif loaded then
    local seen, skipped = { [default_id] = true }, 0
    for _, entry in ipairs(loaded) do
      local profile = normalize(entry)
      if profile and not seen[profile.id] then
        seen[profile.id] = true
        table.insert(profiles, profile)
      else
        skipped = skipped + 1
      end
    end
    if skipped > 0 then
      profile_error = ("AI profiles: skipped %d invalid or duplicate entries."):format(skipped)
    end
  end
  selections = { completion = default_id, companion = default_id }
  local chosen = read_json(selection_path)
  if chosen then
    for workflow in pairs(workflows) do
      if matches(chosen[workflow], "^[%w][%w_.%-]*$", 60) then
        -- A disappeared profile stays selected until the user chooses another.
        -- Do not silently route its requests to the default provider.
        selections[workflow] = chosen[workflow]
      end
    end
  end
end

function M.for_workflow(workflow)
  assert(workflows[workflow], "unknown AI workflow")
  load()
  return vim.tbl_filter(function(profile)
    return profile[workflow]
  end, profiles)
end

function M.current(workflow)
  for _, profile in ipairs(M.for_workflow(workflow)) do
    if profile.id == selections[workflow] then
      return profile
    end
  end
end

local function save()
  if vim.fn.isdirectory(directory) == 0 and vim.fn.mkdir(directory, "p", 448) ~= 1 then
    return false
  end
  local tmp = selection_path .. "." .. vim.uv.os_getpid() .. ".tmp"
  local fd = vim.uv.fs_open(tmp, "wx", 384)
  if not fd then
    return false
  end
  local body = ('{\n  "completion": %s,\n  "companion": %s\n}\n'):format(
    vim.json.encode(selections.completion),
    vim.json.encode(selections.companion)
  )
  local written = vim.uv.fs_write(fd, body, 0)
  vim.uv.fs_close(fd)
  local ok = written == #body and vim.uv.fs_rename(tmp, selection_path)
  if not ok then
    vim.uv.fs_unlink(tmp)
  end
  return not not ok
end

function M.choose(workflow, on_change)
  local choices = M.for_workflow(workflow)
  if profile_error then
    vim.notify(profile_error, vim.log.levels.WARN)
  end
  vim.ui.select(choices, {
    prompt = workflow == "completion" and "AI autocomplete provider" or "AI assistance provider",
    format_item = function(profile)
      local active = selections[workflow] == profile.id and " (current)" or ""
      local billing = profile.http and " [metered API]" or ""
      local capabilities = ""
      if workflow == "companion" and not profile.inline_edit then
        capabilities = profile.http and " [Ask only]" or " [Ask and Chat]"
      end
      return profile.label .. billing .. capabilities .. active
    end,
  }, function(profile)
    if not profile or selections[workflow] == profile.id then
      return
    end
    selections[workflow] = profile.id
    if on_change then
      on_change()
    end
    if not save() then
      vim.notify("AI profile changed for this session; could not save the preference.", vim.log.levels.WARN)
    end
  end)
end

return M
