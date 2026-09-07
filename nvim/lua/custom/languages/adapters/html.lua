local prettier = { 'prettierd', 'prettier', stop_after_first = true }

return {
  lsp_servers = { html = { init_options = { provideFormatter = false } } },
  mason_tools = { 'html-lsp', 'prettier', 'prettierd' },
  treesitter_parsers = { 'html' },
  formatters_by_ft = { html = prettier },
}
