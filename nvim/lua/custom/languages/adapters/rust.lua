local M = {
  mason_tools = { 'rust-analyzer', 'codelldb' },
  treesitter_parsers = { 'rust' },
  dap_by_ft = {
    rust = {
      lsp_client = 'rust_analyzer',
      root_profile = { markers = { 'Cargo.toml', 'rust-project.json', '.git' } },
      launch_types = { 'codelldb' },
    },
  },
}

function M.setup()
  local gh = require('custom.lib.pack').gh

  -- rustaceanvim owns rust-analyzer startup. Its filetype plugin also detects
  -- Mason's codelldb executable and derives Cargo debug targets from rust-analyzer.
  vim.g.rustaceanvim = {
    server = {
      -- rustaceanvim discovers CodeLLDB and installs its Rust configurations
      -- during LSP attachment, so DAP must be ready before its default callback.
      on_attach = function(_, _) require('custom.languages.dap').ensure() end,
      default_settings = {
        ['rust-analyzer'] = {
          cargo = { features = {} },
          check = { command = 'clippy' },
        },
      },
    },
  }

  -- Keep the interactive surface language-neutral. Rustaceanvim extensions are
  -- deliberately available as commands until a shared target interface exists:
  --   :RustLsp runnables, :RustLsp testables, :RustLsp debuggables
  --   :RustLsp expandMacro, :RustLsp hover actions

  vim.pack.add {
    { src = gh 'mrcjkb/rustaceanvim', version = vim.version.range '^9' },
  }
end

return M
