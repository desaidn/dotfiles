local prettier = { 'prettierd', 'prettier', stop_after_first = true }

return {
  lsp_servers = { jsonls = { init_options = { provideFormatter = false } } },
  mason_tools = { 'json-lsp', 'prettier', 'prettierd' },
  treesitter_parsers = { 'json' },
  formatters_by_ft = { json = prettier, jsonc = prettier },
}
