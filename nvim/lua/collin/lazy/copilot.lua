return {
  "zbirenbaum/copilot.lua",
  -- The backend uses the plugin's client API and legacy getCompletions protocol.
  commit = "d1570ddc00fc4fc4caf7422803805ee22cca14ff",
  cmd = "Copilot",
  enabled = function()
    local ok, profiles = pcall(require, "collin.ai.profiles")
    return ok and profiles.has_backend("copilot", "completion")
  end,
  opts = {
    suggestion = { enabled = false, auto_trigger = false },
    panel = { enabled = false },
    nes = { enabled = false },
    filetypes = { ["*"] = true },
    should_attach = function()
      return false -- The explicit backend request owns document attachment.
    end,
    server_opts_overrides = {
      capabilities = { textDocument = { completion = { dynamicRegistration = false } } },
    },
  },
}
