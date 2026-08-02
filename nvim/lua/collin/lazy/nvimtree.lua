return {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    {
      "<leader>nt",
      function()
        require("nvim-tree.api").tree.toggle()
      end,
      desc = "Toggle nvim-tree",
      silent = true,
    },
    {
      "<leader>nn",
      function()
        require("nvim-tree.api").tree.focus()
      end,
      desc = "Focus nvim-tree",
      silent = true,
    },
    {
      "<leader>nf",
      function()
        require("nvim-tree.api").tree.find_file({ open = true, focus = true })
      end,
      desc = "Reveal current file",
      silent = true,
    },
    {
      "<leader>nr",
      function()
        require("nvim-tree.api").tree.reload()
      end,
      desc = "Refresh nvim-tree",
      silent = true,
    },
    {
      "<leader>nc",
      function()
        require("nvim-tree.api").tree.collapse_all()
      end,
      desc = "Collapse nvim-tree",
      silent = true,
    },
    {
      "<leader>ne",
      function()
        require("nvim-tree.api").tree.expand_all()
      end,
      desc = "Expand nvim-tree",
      silent = true,
    },
  },
  config = function()
    local function destination_for_cursor(api)
      local node = api.tree.get_node_under_cursor()
      if not node then
        return nil
      end

      if node.type == "directory" then
        return node.absolute_path
      end

      return vim.fs.dirname(node.absolute_path)
    end

    local function dropped_paths(lines)
      local paths = {}
      for _, line in ipairs(lines) do
        local path = line:gsub("\r$", "")
        if path:sub(1, 7) == "file://" then
          path = vim.uri_to_fname(path)
        end

        if path:sub(1, 1) ~= "/" or not vim.uv.fs_stat(path) then
          return nil
        end
        table.insert(paths, path)
      end
      return #paths > 0 and paths or nil
    end

    local function copy_dropped_files(api, paths, destination)
      local destinations = {}
      for _, source in ipairs(paths) do
        local target = vim.fs.joinpath(destination, vim.fs.basename(source))
        if vim.uv.fs_stat(target) then
          vim.notify(("Drop cancelled: %s already exists"):format(target), vim.log.levels.ERROR)
          return
        end
        table.insert(destinations, target)
      end

      local remaining = #paths
      for index, source in ipairs(paths) do
        vim.system({ "ditto", source, destinations[index] }, {}, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              vim.notify(
                ("Could not copy %s: %s"):format(source, result.stderr),
                vim.log.levels.ERROR
              )
            end

            remaining = remaining - 1
            if remaining == 0 then
              api.tree.reload()
            end
          end)
        end)
      end
    end

    local function enable_file_drops()
      local original_paste = vim.paste
      local pending_drop

      vim.paste = function(lines, phase)
        if phase == 1 then
          local api = require("nvim-tree.api")
          local destination = api.tree.is_tree_buf(0) and destination_for_cursor(api)
          if not destination then
            return original_paste(lines, phase)
          end

          pending_drop = { api = api, destination = destination, lines = vim.deepcopy(lines) }
          return true
        end

        if pending_drop then
          vim.list_extend(pending_drop.lines, lines)
          if phase ~= 3 then
            return true
          end

          local drop = pending_drop
          pending_drop = nil
          local paths = dropped_paths(drop.lines)
          if paths then
            copy_dropped_files(drop.api, paths, drop.destination)
            return true
          end

          return original_paste(drop.lines, -1)
        end

        if phase == -1 then
          local api = require("nvim-tree.api")
          local destination = api.tree.is_tree_buf(0) and destination_for_cursor(api)
          local paths = destination and dropped_paths(lines)
          if paths then
            copy_dropped_files(api, paths, destination)
            return true
          end
        end

        return original_paste(lines, phase)
      end
    end

    enable_file_drops()

    require("nvim-tree").setup({
      filters = {
        dotfiles = false,
        git_ignored = false,
      },
      sync_root_with_cwd = true,
      respect_buf_cwd = true,
      update_focused_file = {
        enable = true,
        update_root = { enable = false },
      },
    })
  end
}
