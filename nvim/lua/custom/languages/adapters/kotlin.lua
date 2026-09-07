return {
  lsp_servers = { kotlin_lsp = {} },
  mason_tools = { 'kotlin-lsp', 'ktlint' },
  treesitter_parsers = { 'kotlin' },
  formatters_by_ft = { kotlin = { 'ktlint' } },
}
