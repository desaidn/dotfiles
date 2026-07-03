require('custom.lib.plugins_loader').require_dir('kickstart.plugins', {
  order = {
    'telescope',
    'lsp',
    'conform',
    'blink-cmp',
    'treesitter',
    'debug',
    'lint',
    'autopairs',
    'neo-tree',
    'gitsigns',
  },
})
