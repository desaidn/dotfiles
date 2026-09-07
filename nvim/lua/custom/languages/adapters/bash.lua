local capabilities = require 'custom.languages.capabilities'

return {
  lsp_servers = {
    bashls = {
      filetypes = { 'bash', 'sh' },
      on_attach = capabilities.disable_formatting,
      settings = {
        bashIde = {
          globPattern = '*@(.sh|.inc|.bash|.command)',
        },
      },
    },
  },
  mason_tools = { 'bash-language-server', 'shellcheck', 'shfmt' },
  treesitter_parsers = { 'bash' },
  formatters_by_ft = { bash = { 'shfmt' }, sh = { 'shfmt' } },
}
