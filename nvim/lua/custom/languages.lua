local prettier = { 'prettierd', 'prettier', stop_after_first = true }

local function disable_lsp_formatting(client)
  client.server_capabilities.documentFormattingProvider = false
  client.server_capabilities.documentRangeFormattingProvider = false
end

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
      on_attach = disable_lsp_formatting,
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
    jdtls = { init_options = { provideFormatter = false } },
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

  linters_by_ft = {
    javascript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescript = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
    python = { 'ruff' },
  },
}
