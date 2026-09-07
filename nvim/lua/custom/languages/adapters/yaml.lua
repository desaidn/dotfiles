return {
  lsp_servers = { yamlls = { settings = { yaml = { keyOrdering = false } } } },
  mason_tools = { 'yaml-language-server' },
  treesitter_parsers = { 'yaml' },
}
