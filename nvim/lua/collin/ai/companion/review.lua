local M = {}
local api = vim.api

-- Use CodeCompanion's hunk controls on a scratch buffer: its inline preview
-- writes proposed lines into the review buffer, which must not be the source.
function M.show(before, after, ft, title, apply, cleanup)
  local function with_sentinel(lines)
    return vim.list_extend(vim.deepcopy(lines), { "" })
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modeline = false
  api.nvim_create_autocmd("BufWipeout", { buffer = buf, once = true, callback = cleanup })
  local ok = pcall(function()
    vim.cmd("botright split")
    api.nvim_win_set_buf(0, buf)
    api.nvim_win_set_var(0, "pi_edit_review", true)
    vim.wo.winbar = title .. "  ·  g2 accept, g3 reject, ga/gr hunk"
    local from, to = with_sentinel(before), with_sentinel(after)
    api.nvim_buf_set_lines(buf, 0, -1, false, from)
    local resolving_hunk = false
    local function finish(lines)
      local replacement = vim.list_slice(lines, 1, #lines - 1)
      vim.schedule(function()
        pcall(api.nvim_buf_delete, buf, { force = true })
        apply(replacement)
      end)
    end
    local ui = require("codecompanion.helpers").show_diff({
      bufnr = buf,
      from_lines = from,
      to_lines = to,
      ft = ft,
      inline = true,
      hunk_actions = true,
      keymaps = {
        on_accept = function(diff)
          if resolving_hunk then
            -- The final hunk decision leaves the resolved text in the scratch buffer.
            finish(api.nvim_buf_get_lines(buf, 0, -1, false))
          else
            finish(diff.diff.to.lines)
          end
        end,
        on_reject = function(diff)
          finish(diff.diff.from.lines) -- Keep hunks already accepted.
        end,
        on_always_accept = function() end, -- Never persist approvals for Pi.
      },
    })
    local resolve_hunk = ui.resolve_hunk
    ui.resolve_hunk = function(self, ...)
      resolving_hunk = true
      resolve_hunk(self, ...)
      resolving_hunk = false
    end
    vim.keymap.set("n", "q", function()
      api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, desc = "Close Pi review without applying changes" })
  end)
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  return ok
end

return M
