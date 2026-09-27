-- Formats without a language server or debugger share one declaration.
return {
  mason_tools = { 'prettier', 'prettierd' },
  treesitter_parsers = {
    'diff',
    'dockerfile',
    'gitcommit',
    'gitignore',
    'markdown',
    'markdown_inline',
    'query',
    'regex',
    'sql',
    'toml',
    'vim',
    'vimdoc',
  },
  formatters_by_ft = { markdown = { 'prettierd', 'prettier', stop_after_first = true } },
}
