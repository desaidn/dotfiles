return {
  lsp_servers = { fish_lsp = { root_markers = { 'config.fish', '.git' } } },
  mason_tools = { 'fish-lsp' },
  treesitter_parsers = { 'fish' },
}
