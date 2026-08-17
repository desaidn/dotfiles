local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local languages = require 'custom.languages.config'

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end

  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function contains(items, expected)
  for _, item in ipairs(items) do
    if item == expected then return true end
  end
  return false
end

check('declares Fish parsing and language-server support', function()
  assert(contains(languages.treesitter_parsers, 'fish'), 'missing Fish Tree-sitter parser')
  assert(languages.lsp_servers.fish_lsp ~= nil, 'missing fish_lsp configuration')
  assert(contains(languages.mason_tools, 'fish-lsp'), 'missing fish-lsp Mason package')
  assert(vim.deep_equal(languages.lsp_servers.fish_lsp.root_markers, { 'config.fish', '.git' }), 'Fish must use its configuration or repository root')
  assert(languages.formatters_by_ft.fish == nil, 'Fish must use its LSP formatter, not a second Conform formatter')
  assert(languages.linters_by_ft.fish == nil, 'Fish diagnostics must not be duplicated through nvim-lint')
end)

check('declares Bash and POSIX shell tooling with one save formatter', function()
  assert(languages.lsp_servers.bashls ~= nil, 'missing bashls configuration')
  assert(contains(languages.mason_tools, 'bash-language-server'), 'missing bash-language-server Mason package')
  assert(contains(languages.mason_tools, 'shellcheck'), 'missing shellcheck Mason package')
  assert(contains(languages.mason_tools, 'shfmt'), 'missing shfmt Mason package')
  assert(vim.deep_equal(languages.lsp_servers.bashls.filetypes, { 'bash', 'sh' }), 'BashLS must never attach to Zsh')
  assert(languages.lsp_servers.bashls.settings.bashIde.globPattern == '*@(.sh|.inc|.bash|.command)', 'BashLS must not recursively scan standalone scripts')
  assert(vim.deep_equal(languages.formatters_by_ft.bash, { 'shfmt' }), 'Bash must use shfmt through Conform')
  assert(vim.deep_equal(languages.formatters_by_ft.sh, { 'shfmt' }), 'POSIX sh must use shfmt through Conform')
  assert(languages.linters_by_ft.bash == nil, 'Bash diagnostics must not be duplicated through nvim-lint')
  assert(languages.linters_by_ft.sh == nil, 'POSIX sh diagnostics must not be duplicated through nvim-lint')

  local client = {
    server_capabilities = {
      documentFormattingProvider = true,
      documentRangeFormattingProvider = true,
    },
  }
  languages.lsp_servers.bashls.on_attach(client)
  assert(not client.server_capabilities.documentFormattingProvider, 'BashLS formatting must be disabled')
  assert(not client.server_capabilities.documentRangeFormattingProvider, 'BashLS range formatting must be disabled')
end)

check('separates Python semantics, lint actions, formatting, and debugging', function()
  assert(languages.lsp_servers.pyright == nil, 'Pyright must not attach beside BasedPyright')
  assert(languages.lsp_servers.basedpyright ~= nil, 'missing BasedPyright configuration')
  assert(languages.lsp_servers.basedpyright.init_options.disablePullDiagnostics == true, 'BasedPyright must use push diagnostics')
  assert(languages.lsp_servers.basedpyright.settings.basedpyright.analysis.diagnosticMode == 'workspace', 'BasedPyright must analyze the workspace')
  assert(languages.lsp_servers.ruff ~= nil, 'missing Ruff language-server configuration')
  assert(languages.lsp_servers.basedpyright.settings.basedpyright.disableOrganizeImports == true)
  assert(contains(languages.mason_tools, 'basedpyright'), 'missing basedpyright Mason package')
  assert(contains(languages.mason_tools, 'ruff'), 'missing Ruff Mason package')
  assert(contains(languages.mason_tools, 'debugpy'), 'missing debugpy Mason package')
  assert(not contains(languages.mason_tools, 'pyright'), 'Pyright Mason package must be removed')
  assert(languages.linters_by_ft.python == nil, 'Ruff diagnostics must not be duplicated through nvim-lint')
  assert(vim.deep_equal(languages.formatters_by_ft.python, { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' }))

  local client = {
    server_capabilities = {
      hoverProvider = true,
      documentFormattingProvider = true,
      documentRangeFormattingProvider = true,
    },
  }
  languages.lsp_servers.ruff.on_attach(client)
  assert(not client.server_capabilities.hoverProvider, 'Ruff hover must defer to BasedPyright')
  assert(not client.server_capabilities.documentFormattingProvider, 'Ruff formatting must defer to Conform')
  assert(not client.server_capabilities.documentRangeFormattingProvider, 'Ruff range formatting must defer to Conform')
end)

check('leaves Rust lifecycle to rustaceanvim and installs its debugger', function()
  assert(languages.lsp_servers.rust_analyzer == nil, 'rust-analyzer must not be enabled through the generic LSP inventory')
  assert(contains(languages.mason_tools, 'rust-analyzer'), 'missing rust-analyzer Mason package')
  assert(contains(languages.mason_tools, 'codelldb'), 'missing codelldb Mason package')
end)

check('leaves Java lifecycle to nvim-jdtls and installs its debugger bundles', function()
  assert(languages.lsp_servers.jdtls == nil, 'JDTLS must not be enabled through the generic LSP inventory')
  assert(contains(languages.mason_tools, 'jdtls'), 'missing jdtls Mason package')
  assert(contains(languages.mason_tools, 'java-debug-adapter'), 'missing Java debug adapter Mason package')
  assert(contains(languages.mason_tools, 'java-test'), 'missing Java test Mason package')
  assert(vim.deep_equal(languages.formatters_by_ft.java, { 'google-java-format' }), 'Java must use Google Java Format through Conform')
end)

if #failures > 0 then error(string.format('%d language inventory check(s) failed: %s', #failures, table.concat(failures, ', '))) end

io.stdout:write 'All language inventory checks passed.\n'
