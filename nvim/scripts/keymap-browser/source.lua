-- Inspect literal Lua declarations without running the configuration.
local rows, commands, digests = {}, {}, {}
local file, source
local function field(node, name)
  return node and node:field(name)[1]
end

local function raw(node)
  return node and vim.treesitter.get_node_text(node, source)
end

local function literal(node)
  if not node or node:type() ~= "string" then return end
  local loader = loadstring("return " .. raw(node))
  if loader then return loader() end
end

local function fields(node)
  local positional, named = {}, {}
  if node and node:type() == "table_constructor" then
    for item in node:iter_children() do
      if item:type() == "field" then
        local name, value = field(item, "name"), field(item, "value")
        if name then
          named[literal(name) or raw(name)] = value
        else
          positional[#positional + 1] = value
        end
      end
    end
  end
  return positional, named
end

local function modes(node)
  if not node then return { "n" } end
  local single = literal(node)
  if single then return { single } end
  local result = {}
  for _, item in ipairs(fields(node)) do
    result[#result + 1] = literal(item)
  end
  if #result > 0 then return result end
end

local function context(label, scope)
  return { label = label, scope = scope }
end

local global = context("Global", "")
local markdown = context("Markdown buffer", "markdown")
local markdown_and_mermaid = context("Markdown / Mermaid buffer", "markdown|mermaid")
local dashboard = context("Dashboard buffer", "alpha")
local lsp = context("LSP-attached buffer", "lsp")
local function buffer_context()
  if vim.endswith(file, "/markdown.lua") then return markdown end
  if vim.endswith(file, "/lsp.lua") then return lsp end
  if vim.endswith(file, "/mermaid_preview.lua") then return markdown_and_mermaid end
  return context("Buffer-local", "*")
end

local function arguments(node)
  local result = {}
  for child in node:iter_children() do
    if child:named() and child:type() ~= "comment" then
      result[#result + 1] = child
    end
  end
  return result
end

local function options(node)
  if not node then return {} end
  if node:type() == "function_call" and raw(field(node, "name")) == "vim.tbl_extend" then
    local args = arguments(field(node, "arguments"))
    local opts = options(args[#args])
    if vim.endswith(file, "/markdown.lua") and raw(args[2]) == "opts" then
      opts.buffer = true -- configure_markdown_buffer defines opts = { buffer = buf }
    end
    return opts
  end
  local _, named = fields(node)
  return named
end

local function add(node, key, binding_modes, action, description, where, style)
  if not key or not binding_modes or not node then return end
  local line, _, start = node:start()
  local _, _, finish = node:end_()
  local rhs = (literal(action) or raw(action) or ""):match("^[^\r\n]*")
  rows[#rows + 1] = {
    key = key, modes = binding_modes, rhs = rhs, desc = description, file = file,
    line = line + 1, start = start, finish = finish, style = style or "string",
    context = where.label, scope = where.scope,
  }
end

local function key_specs(node)
  for _, spec in ipairs(fields(node)) do
    local items, opts = fields(spec)
    if items[2] then
      local ft = literal(opts.ft)
      local ft_list = {}
      for _, value in ipairs(fields(opts.ft)) do
        ft_list[#ft_list + 1] = literal(value)
      end
      if not ft and #ft_list > 0 then ft = table.concat(ft_list, "|") end
      local where = ft and context(ft:gsub("|", " / ") .. " buffer", ft)
        or opts.buffer and raw(opts.buffer) ~= "false" and buffer_context() or global
      add(items[1], literal(items[1]), modes(opts.mode), items[2], literal(opts.desc), where)
    end
  end
end

local function scan(node)
  if node:type() == "function_call" then
    local name = raw(field(node, "name"))
    local args = arguments(field(node, "arguments"))
    if name == "vim.keymap.set" or name == "vim.api.nvim_set_keymap" or name == "vim.api.nvim_buf_set_keymap" then
      local offset = name == "vim.api.nvim_buf_set_keymap" and 1 or 0
      local key = args[2 + offset]
      local opts = options(args[4 + offset])
      local is_local = offset == 1 or (opts.buffer and (opts.buffer == true or raw(opts.buffer) ~= "false"))
      local desc = literal(opts.desc)
      if not desc and vim.endswith(file, "/mermaid_preview.lua") and literal(key) == "<leader>mv" then
        desc = "Open Mermaid browser preview"
      end
      add(key, literal(key), modes(args[1 + offset]), args[3 + offset], desc, is_local and buffer_context() or global)
    elseif name == "vim.api.nvim_create_user_command" then
      local command = literal(args[1])
      if command then
        local line = node:start()
        commands[#commands + 1] = {
          name = command, desc = literal(options(args[3]).desc), file = file, line = line + 1,
        }
      end
    elseif name == "which_key.add" then
      key_specs(args[1])
    elseif name == "map" and (vim.endswith(file, "/dap.lua") or vim.endswith(file, "/neotest.lua")) then
      add(args[1], literal(args[1]), { "n" }, args[2], literal(args[3]), global)
    end
  elseif node:type() == "field" then
    local name = raw(field(node, "name"))
    local value = field(node, "value")
    if name == "keys" and file:find("/lua/collin/lazy/", 1, true) then
      key_specs(value)
    elseif name == "MkdnEnter" and vim.endswith(file, "/markdown.lua") then
      local items = fields(value)
      add(items[2], literal(items[2]), modes(items[1]), nil, "Mkdnflow smart Enter", markdown)
    end
  elseif node:type() == "assignment_statement" and vim.endswith(file, "/alpha.lua") then
    if raw(node:named_child(0)) == "launcher_keys" then
      local values = node:named_child(1)
      local table_node = values and values:named_child(0)
      if table_node and table_node:type() == "table_constructor" then
        for item in table_node:iter_children() do
          local key, action = field(item, "name"), field(item, "value")
          add(key, literal(key) or (key and key:type() == "identifier" and raw(key)), {"n"}, action, nil,
            dashboard, literal(key) and "string" or "field")
        end
      end
    end
  end
  for child in node:iter_children() do
    if child:named() and child:type() ~= "comment" then scan(child) end
  end
end

for _, path in ipairs(arg) do
  file = path:gsub("\\", "/")
  local handle = assert(io.open(path, "rb"))
  source = handle:read("*a")
  handle:close()
  digests[file] = vim.fn.sha256(source)
  local tree = vim.treesitter.get_string_parser(source, "lua"):parse()[1]
  scan(tree:root())
end
io.write(vim.json.encode({ rows = rows, commands = commands, digests = digests, runtime = vim.env.VIMRUNTIME }))
