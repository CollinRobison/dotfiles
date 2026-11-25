local M = {}

function M.setup()
  local profiles = require("collin.ai.profiles")
  local completion = require("collin.ai.completion")
  completion.setup()

  local function choose_completion()
    profiles.choose("completion", completion.clear)
  end

  local function choose_companion()
    profiles.choose("companion")
  end

  local function companion(action)
    return function()
      completion.clear()
      local profile = profiles.current("companion")
      if not profile then
        vim.notify("AI assistance profile is unavailable. Choose one with :AIAssistProvider.", vim.log.levels.WARN)
        return
      end
      if action ~= "chat" and not completion.normal_buffer(vim.api.nvim_get_current_buf()) then
        vim.notify("AI actions are unavailable for this selection.", vim.log.levels.WARN)
        return
      end
      if action == "edit" and not profile.inline_edit then
        vim.notify("This AI profile does not support reviewed inline edits.", vim.log.levels.WARN)
        return
      end
      require("collin.ai.companion")[action](profile)
    end
  end

  vim.api.nvim_create_user_command("AICompletionProvider", choose_completion, {
    desc = "Choose the AI autocomplete provider",
  })
  vim.api.nvim_create_user_command("AIAssistProvider", choose_companion, {
    desc = "Choose the AI assistance provider",
  })

  vim.keymap.set("n", "<leader>ap", "<cmd>AICompletionProvider<CR>", { desc = "Choose the AI autocomplete provider" })
  vim.keymap.set("n", "<leader>as", "<cmd>AIAssistProvider<CR>", { desc = "Choose the AI assistance provider" })
  vim.keymap.set("x", "<leader>aq", companion("ask"), { desc = "Ask AI about the selected code" })
  vim.keymap.set("x", "<leader>ae", companion("edit"), { desc = "Propose a reviewed AI edit to the selected lines" })
  vim.keymap.set("n", "<leader>ac", companion("chat"), { desc = "Open a new AI chat" })

  vim.keymap.set("i", "<M-]>", function()
    local request = "<Cmd>lua require('collin.ai.completion').request()<CR>"
    return vim.fn.pumvisible() == 1 and "<C-e>" .. request or request
  end, { expr = true, replace_keycodes = true, desc = "Request one AI completion" })
  vim.keymap.set("i", "<M-a>", completion.accept, { desc = "Accept the current AI completion" })

  require("which-key").add({ { "<leader>a", group = "AI assisted" } })
end

return M
