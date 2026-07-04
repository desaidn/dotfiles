-- Autocompletion
-- See `:help blink-cmp`

local gh = require('custom.lib.pack').gh

vim.pack.add {
  { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' },
  gh 'rafamadriz/friendly-snippets',
  { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' },
}

require('luasnip').setup {}
require('luasnip.loaders.from_vscode').lazy_load()

require('blink.cmp').setup {
  keymap = {
    -- Presets: 'default' (<c-y> accept), 'super-tab', 'enter', 'none'
    --  See `:help ins-completion` and `:help blink-cmp-config-keymap`
    --
    -- Common keymaps (all presets):
    --  <c-space>: open menu/docs  |  <c-n>/<c-p>: navigate  |  <c-e>: dismiss
    --  <tab>/<s-tab>: snippet jump  |  <c-k>: signature help
    preset = 'enter',
  },

  -- For advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
  --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps

  appearance = {
    kind_icons = {},
  },

  completion = {
    -- By default, you may press `<c-space>` to show the documentation.
    -- Optionally, set `auto_show = true` to show the documentation after a delay.
    documentation = {
      auto_show = true,
      auto_show_delay_ms = 200,
      window = {
        max_width = 96,
        max_height = 24,
        desired_min_width = 72,
      },
    },

    -- Customize completion menu appearance
    menu = {
      draw = {
        -- Disable icons by showing only text
        columns = {
          { 'label', 'label_description', gap = 1 },
          { 'kind' },
        },
      },
    },
  },

  sources = {
    default = { 'lsp', 'path', 'snippets' },
  },

  snippets = { preset = 'luasnip' },

  -- Blink.cmp includes an optional, recommended rust fuzzy matcher,
  -- which automatically downloads a prebuilt binary when enabled.
  --
  -- By default, we use the Lua implementation instead, but you may enable
  -- the rust implementation via `'prefer_rust_with_warning'`
  --
  -- See :h blink-cmp-config-fuzzy for more information
  fuzzy = { implementation = 'prefer_rust_with_warning' },

  -- Shows a signature help window while you type arguments for a function
  signature = { enabled = true },
}
