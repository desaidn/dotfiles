local prettier = { 'prettierd', 'prettier', stop_after_first = true }

return {
  lsp_servers = { cssls = { init_options = { provideFormatter = false } } },
  mason_tools = { 'css-lsp', 'prettier', 'prettierd' },
  treesitter_parsers = { 'css', 'scss' },
  formatters_by_ft = { css = prettier, scss = prettier },
}
