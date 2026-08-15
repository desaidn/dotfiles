local gh = require('custom.lib.pack').gh

-- rustaceanvim owns rust-analyzer startup. Its filetype plugin also detects
-- Mason's codelldb executable and derives Cargo debug targets from rust-analyzer.
vim.g.rustaceanvim = {
  server = {
    -- rustaceanvim discovers CodeLLDB and installs its Rust configurations
    -- during LSP attachment, so DAP must be ready before its default callback.
    on_attach = function(_, bufnr)
      require('custom.lib.dap').ensure()
      local opts = { buffer = bufnr }
      vim.keymap.set('n', '<leader>rr', '<cmd>RustLsp runnables<cr>', vim.tbl_extend('force', opts, { desc = 'Rust: Runnables' }))
      vim.keymap.set('n', '<leader>rt', '<cmd>RustLsp testables<cr>', vim.tbl_extend('force', opts, { desc = 'Rust: Testables' }))
      vim.keymap.set('n', '<leader>rd', '<cmd>RustLsp debuggables<cr>', vim.tbl_extend('force', opts, { desc = 'Rust: Debuggables' }))
      vim.keymap.set('n', '<leader>rm', '<cmd>RustLsp expandMacro<cr>', vim.tbl_extend('force', opts, { desc = 'Rust: Expand macro' }))
      vim.keymap.set('n', 'K', '<cmd>RustLsp hover actions<cr>', vim.tbl_extend('force', opts, { desc = 'Rust: Hover actions' }))
    end,
    default_settings = {
      ['rust-analyzer'] = {
        cargo = { features = {} },
        check = { command = 'clippy' },
      },
    },
  },
}

vim.pack.add {
  { src = gh 'mrcjkb/rustaceanvim', version = vim.version.range '^9' },
}
