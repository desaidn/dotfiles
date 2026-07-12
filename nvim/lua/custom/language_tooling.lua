local language_tooling = require 'custom.lib.language_tooling'

---@type LanguageToolingFormatterList
local prettier = { 'prettierd', 'prettier', stop_after_first = true }

---@type string[]
local prettier_tools = { 'prettier', 'prettierd' }

---@type LanguageToolingLanguage[]
local languages = {
  {
    name = 'lua',
    filetypes = { 'lua' },
    lsps = {
      { server = 'lua_ls', install = 'lua-language-server' },
    },
    tools = { 'stylua' },
    formatters = { 'stylua' },
  },
  {
    name = 'typescript',
    filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
    lsps = {
      { server = 'ts_ls', install = 'typescript-language-server' },
    },
    tools = { 'prettier', 'prettierd', 'eslint_d' },
    formatters = prettier,
    linters = { 'eslint_d' },
  },
  {
    name = 'rust',
    lsps = {
      { server = 'rust_analyzer', install = 'rust-analyzer' },
    },
  },
  {
    name = 'go',
    lsps = {
      { server = 'gopls' },
    },
  },
  {
    name = 'python',
    filetypes = { 'python' },
    lsps = {
      { server = 'pyright' },
    },
    tools = { 'ruff' }, -- Conform's ruff_* formatters are all installed by this package.
    formatters = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' },
    linters = { 'ruff' },
  },
  {
    name = 'json',
    filetypes = { 'json', 'jsonc' },
    lsps = {
      { server = 'jsonls', install = 'json-lsp' },
    },
    tools = prettier_tools,
    formatters = prettier,
  },
  {
    name = 'yaml',
    lsps = {
      { server = 'yamlls', install = 'yaml-language-server' },
    },
  },
  {
    name = 'html',
    filetypes = { 'html' },
    lsps = {
      { server = 'html', install = 'html-lsp' },
    },
    tools = prettier_tools,
    formatters = prettier,
  },
  {
    name = 'css',
    filetypes = { 'css', 'scss' },
    lsps = {
      { server = 'cssls', install = 'css-lsp' },
    },
    tools = prettier_tools,
    formatters = prettier,
  },
  {
    name = 'haskell',
    lsps = {
      { server = 'hls', install = 'haskell-language-server' },
    },
  },
  {
    name = 'java',
    filetypes = { 'java' },
    lsps = {
      { server = 'jdtls' },
    },
    tools = { 'google-java-format' },
    formatters = { 'google-java-format' },
  },
  {
    name = 'kotlin',
    filetypes = { 'kotlin' },
    lsps = {
      { server = 'kotlin_lsp', install = 'kotlin-lsp' },
    },
    tools = { 'ktlint' },
    formatters = { 'ktlint' },
  },
  {
    name = 'markdown',
    filetypes = { 'markdown' },
    tools = prettier_tools,
    formatters = prettier,
  },
}

return language_tooling.create { languages = languages }
