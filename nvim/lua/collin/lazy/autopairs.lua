return {
  "windwp/nvim-autopairs",
  event = "InsertEnter",
  keys = {
    {
      "<leader>ua",
      function()
        require("nvim-autopairs").toggle()
      end,
      desc = "Toggle autopairs",
    },
  },
  opts = {
    check_ts = true,
    disable_filetype = { "TelescopePrompt", "spectre_panel", "snacks_picker_input", "gitcommit" },
    map_bs = true,
    map_cr = true,
    fast_wrap = {
      map = "<M-e>",
    },
    ts_config = {
      lua = { "string" },
      javascript = { "template_string" },
      javascriptreact = { "template_string" },
      typescript = { "template_string" },
      typescriptreact = { "template_string" },
    },
  },
  config = function(_, opts)
    local autopairs = require("nvim-autopairs")
    local Rule = require("nvim-autopairs.rule")
    local cond = require("nvim-autopairs.conds")

    autopairs.setup(opts)

    -- Pair angle brackets only in markup-like buffers, not general code expressions.
    autopairs.add_rule(
      Rule("<", ">", { "html", "xml", "javascriptreact", "typescriptreact", "svelte" })
        :with_pair(cond.not_before_regex("[%w_]"))
        :with_pair(cond.not_after_regex("[%w=]"))
        :with_move(cond.done())
    )
  end,
}
