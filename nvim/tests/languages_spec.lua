local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local function assert_deep_equal(actual, expected, path)
  path = path or 'value'
  assert(type(actual) == type(expected), string.format('%s: expected %s, got %s', path, type(expected), type(actual)))
  if type(expected) ~= 'table' then
    assert(actual == expected, string.format('%s: expected %q, got %q', path, tostring(expected), tostring(actual)))
    return
  end

  for key, expected_value in pairs(expected) do
    assert(actual[key] ~= nil, string.format('%s: missing key %q', path, tostring(key)))
    assert_deep_equal(actual[key], expected_value, string.format('%s[%q]', path, tostring(key)))
  end
  for key in pairs(actual) do
    assert(expected[key] ~= nil, string.format('%s: unexpected key %q', path, tostring(key)))
  end
end

assert_deep_equal(require 'custom.languages', {
  lsp_servers = {
    'lua_ls',
    'ts_ls',
    'rust_analyzer',
    'gopls',
    'pyright',
    'jsonls',
    'yamlls',
    'html',
    'cssls',
    'hls',
    'jdtls',
    'kotlin_lsp',
  },
  mason_tools = {
    'lua-language-server',
    'stylua',
    'typescript-language-server',
    'prettier',
    'prettierd',
    'eslint_d',
    'rust-analyzer',
    'gopls',
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
    javascript = { 'prettierd', 'prettier', stop_after_first = true },
    javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    typescript = { 'prettierd', 'prettier', stop_after_first = true },
    typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    json = { 'prettierd', 'prettier', stop_after_first = true },
    jsonc = { 'prettierd', 'prettier', stop_after_first = true },
    css = { 'prettierd', 'prettier', stop_after_first = true },
    scss = { 'prettierd', 'prettier', stop_after_first = true },
    html = { 'prettierd', 'prettier', stop_after_first = true },
    markdown = { 'prettierd', 'prettier', stop_after_first = true },
    python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' },
    java = { 'google-java-format' },
    kotlin = { 'ktlint' },
  },
  linters_by_ft = {
    javascript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescript = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
    python = { 'ruff' },
  },
})

io.stdout:write 'language inventory regression passed\n'
