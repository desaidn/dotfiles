local prettier = { 'prettierd', 'prettier', stop_after_first = true }
local capabilities = require 'custom.languages.capabilities'

-- Inject Neovim runtime settings only when editing the Neovim config directory.
-- Other Lua projects get the nvim-lspconfig defaults or use their own .luarc.json.
-- See: https://luals.github.io/wiki/settings/
---@param client vim.lsp.Client
local function configure_neovim_lua_workspace(client)
  if client.workspace_folders then
    local path = vim.fn.resolve(client.workspace_folders[1].name)
    if path ~= vim.fn.resolve(vim.fn.stdpath 'config') then return end
  end

  local current = client.config.settings.Lua or {} --[[@as table]]
  client.config.settings.Lua = vim.tbl_deep_extend('force', current, {
    runtime = { version = 'LuaJIT' },
    diagnostics = { globals = { 'vim' } },
    workspace = {
      checkThirdParty = false,
      library = {
        vim.env.VIMRUNTIME,
        '${3rd}/luv/library',
      },
    },
  })
end

return {
  treesitter_parsers = {
    'bash',
    'c',
    'css',
    'diff',
    'dockerfile',
    'fish',
    'gitcommit',
    'gitignore',
    'haskell',
    'html',
    'java',
    'javascript',
    'json',
    'kotlin',
    'lua',
    'luadoc',
    'markdown',
    'markdown_inline',
    'python',
    'query',
    'regex',
    'rust',
    'scss',
    'sql',
    'toml',
    'tsx',
    'typescript',
    'vim',
    'vimdoc',
    'yaml',
  },

  lsp_servers = {
    lua_ls = {
      on_init = configure_neovim_lua_workspace,
      settings = {
        Lua = {
          completion = { callSnippet = 'Replace' },
          -- Uncomment to ignore noisy `missing-fields` warnings.
          -- diagnostics = { disable = { 'missing-fields' } },
        },
      },
    },
    ts_ls = {},
    bashls = {
      filetypes = { 'bash', 'sh' },
      on_attach = capabilities.disable_formatting,
      settings = {
        bashIde = {
          globPattern = '*@(.sh|.inc|.bash|.command)',
        },
      },
    },
    fish_lsp = {
      root_markers = { 'config.fish', '.git' },
    },
    pyright = {},
    jsonls = { init_options = { provideFormatter = false } },
    yamlls = { settings = { yaml = { keyOrdering = false } } },
    html = { init_options = { provideFormatter = false } },
    cssls = { init_options = { provideFormatter = false } },
    hls = {},
    kotlin_lsp = {},
  },

  -- Keep install ownership explicit: an enabled LSP need not be Mason-managed.
  mason_tools = {
    'lua-language-server',
    'stylua',
    'typescript-language-server',
    'bash-language-server',
    'fish-lsp',
    'shellcheck',
    'shfmt',
    'prettier',
    'prettierd',
    'eslint_d',
    'rust-analyzer',
    'codelldb',
    'pyright',
    'ruff',
    'json-lsp',
    'yaml-language-server',
    'html-lsp',
    'css-lsp',
    'haskell-language-server',
    'jdtls',
    'java-debug-adapter',
    'java-test',
    'google-java-format',
    'kotlin-lsp',
    'ktlint',
  },

  formatters_by_ft = {
    lua = { 'stylua' },
    javascript = prettier,
    javascriptreact = prettier,
    bash = { 'shfmt' },
    sh = { 'shfmt' },
    typescript = prettier,
    typescriptreact = prettier,
    json = prettier,
    jsonc = prettier,
    css = prettier,
    scss = prettier,
    html = prettier,
    markdown = prettier,
    python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' },
    java = { 'google-java-format' },
    kotlin = { 'ktlint' },
  },

  format_on_save_disabled_filetypes = {
    c = true,
    cpp = true,
  },

  -- Debug launch files are resolved from the active buffer's nearest project
  -- marker, never Neovim's process-wide current directory.
  dap_by_ft = {
    rust = {
      lsp_client = 'rust_analyzer',
      root_profile = { markers = { 'Cargo.toml', 'rust-project.json', '.git' } },
      launch_types = { 'codelldb' },
    },
    python = {
      lsp_client = 'pyright',
      root_profile = {
        markers = { 'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' },
      },
      launch_types = { 'python' },
    },
  },

  linters_by_ft = {
    javascript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescript = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
    python = { 'ruff' },
  },
}
