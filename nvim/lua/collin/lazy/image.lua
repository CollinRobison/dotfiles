return {
  "3rd/image.nvim",
  event = { "BufReadPre", "BufNewFile" },
  build = false,
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {
    backend = "kitty",
    processor = "magick_cli",
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        filetypes = { "markdown", "rmd", "quarto" },
      },
      asciidoc = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
      },
      typst = { enabled = true },
      neorg = { enabled = true },
      html = { enabled = true },
      css = { enabled = true },
    },
  },
  config = function(_, opts)
    local image = require("image")
    local magick_cli = require("image/processors/magick_cli")
    local orientation_cache = {}

    local function get_orientation(path)
      if vim.fn.executable("magick") ~= 1 then return 1 end

      local stat = vim.uv.fs_stat(path)
      if not stat then return 1 end

      local key = path .. ":" .. stat.size .. ":" .. stat.mtime.sec
      if orientation_cache[key] then return orientation_cache[key] end

      local orientation = tonumber(vim.trim(vim.fn.system({
        "magick",
        "identify",
        "-format",
        "%[EXIF:Orientation]",
        path,
      }))) or 1
      orientation_cache[key] = orientation
      return orientation
    end

    -- image.nvim's renderer is asynchronous, so add auto-orient to its
    -- existing transform instead of synchronously creating replacement files.
    if not magick_cli._collin_auto_orient_transform then
      local original_get_dimensions = magick_cli.get_dimensions
      magick_cli.get_dimensions = function(path)
        local dimensions = original_get_dimensions(path)
        local orientation = get_orientation(path)
        if orientation >= 5 and orientation <= 8 then
          dimensions.width, dimensions.height = dimensions.height, dimensions.width
        end
        return dimensions
      end

      local convert_cmd = vim.fn.executable("magick") == 1 and "magick" or "convert"
      magick_cli.transform = function(path, request, output_path, callback)
        local stderr = vim.loop.new_pipe()
        local error_output = ""
        local handle
        local source_path = path

        if (request.source_format or ""):lower() == "gif" then source_path = source_path .. "[0]" end

        local args = { source_path, "-auto-orient" }
        if request.target_width and request.target_height then
          args[#args + 1] = "-scale"
          args[#args + 1] = string.format("%dx%d", request.target_width, request.target_height)
        end
        if request.crop then
          args[#args + 1] = "-crop"
          args[#args + 1] = string.format("%dx%d+%d+%d", request.crop.width, request.crop.height, request.crop.x, request.crop.y)
        end
        args[#args + 1] = (request.output_format or "png") .. ":" .. output_path

        local function close_stderr()
          if not stderr or stderr:is_closing() then return end
          pcall(vim.loop.read_stop, stderr)
          stderr:close()
        end

        handle = vim.loop.spawn(convert_cmd, {
          args = args,
          stdio = { nil, nil, stderr },
          hide = true,
        }, function(code)
          close_stderr()
          if handle and not handle:is_closing() then handle:close() end
          if code == 0 then
            callback({ ok = true, path = output_path })
          else
            callback({ ok = false, error = error_output ~= "" and error_output or "Failed to transform image" })
          end
        end)

        if not handle then
          close_stderr()
          callback({ ok = false, error = "Failed to start image transform" })
          return
        end

        vim.loop.read_start(stderr, function(err, data)
          if err then
            error_output = error_output .. tostring(err)
          elseif data then
            error_output = error_output .. data
          end
        end)
      end
      magick_cli._collin_auto_orient_transform = true
    end

    image.setup(opts)

    -- image.nvim's overlap checker runs from its decoration provider. On a
    -- photo-heavy journal that makes every redraw scan and toggle every image.
    -- Clear all Kitty graphics on buffer changes and when a real floating tool opens.
    local function clear_terminal_images()
      -- Use the backend's delete-all operation even if image.nvim's state says
      -- an image is already clear; Kitty can otherwise retain stale graphics.
      if #image.get_images() > 0 then image.clear() end
    end

    local transient_float_filetypes = {
      cmp_docs = true,
      cmp_menu = true,
      image_nvim_popup = true,
      snacks_notif = true,
      scrollview = true,
      scrollview_sign = true,
    }
    local images_hidden = false

    local function has_blocking_float()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then
          local buf = vim.api.nvim_win_get_buf(win)
          if not transient_float_filetypes[vim.bo[buf].filetype] then
            return true
          end
        end
      end
      return false
    end

    local function refresh_image_visibility()
      vim.schedule(function()
        local should_hide = has_blocking_float()
        if should_hide and not images_hidden and image.is_enabled() then
          image.disable()
          images_hidden = true
        elseif not should_hide and images_hidden then
          image.enable()
          images_hidden = false
        end
      end)
    end

    local group = vim.api.nvim_create_augroup("collin-image-float-visibility", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "BufLeave", "TabEnter" }, {
      group = group,
      callback = clear_terminal_images,
    })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinClosed", "WinEnter", "WinNew" }, {
      group = group,
      callback = refresh_image_visibility,
    })
  end,
}
