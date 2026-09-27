local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local original_pack_add = vim.pack.add
local original_autocmd = vim.api.nvim_create_autocmd
local original_command = vim.api.nvim_create_user_command
local original_rustaceanvim = vim.g.rustaceanvim
local function unexpected_setup() error 'Collecting language settings must not activate plugins or register behavior' end
vim.pack.add = unexpected_setup
vim.api.nvim_create_autocmd = unexpected_setup
vim.api.nvim_create_user_command = unexpected_setup
local languages = require 'custom.languages.config'
vim.pack.add = original_pack_add
vim.api.nvim_create_autocmd = original_autocmd
vim.api.nvim_create_user_command = original_command

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

local function assert_formatting_disabled(on_attach, server, server_capabilities)
  server_capabilities = server_capabilities or {}
  server_capabilities.documentFormattingProvider = true
  server_capabilities.documentRangeFormattingProvider = true
  local client = { server_capabilities = server_capabilities }

  on_attach(client)
  assert(not server_capabilities.documentFormattingProvider, server .. ' formatting must be disabled')
  assert(not server_capabilities.documentRangeFormattingProvider, server .. ' range formatting must be disabled')
  return client
end

check('collects complete declarations without activating adapters', function()
  assert(package.loaded['custom.languages.dap'] == nil, 'inventory collection must not initialize shared DAP')
  assert(vim.deep_equal(vim.g.rustaceanvim, original_rustaceanvim), 'inventory collection must not configure Rust')
  assert(languages.dap_by_ft.java.lsp_client == 'jdtls', 'Java routing must exist before setup')
  assert(languages.dap_by_ft.python.lsp_client == 'basedpyright', 'Python routing must exist before setup')
end)

check('deduplicates shared install requirements while preserving every consumer', function()
  for _, field in ipairs { 'mason_tools', 'treesitter_parsers' } do
    local seen = {}
    for _, name in ipairs(languages[field]) do
      assert(not seen[name], ('duplicate %s requirement: %s'):format(field, name))
      seen[name] = true
    end
  end
  for _, filetype in ipairs { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'json', 'jsonc', 'html', 'css', 'scss', 'markdown' } do
    assert(vim.deep_equal(languages.formatters_by_ft[filetype], { 'prettierd', 'prettier', stop_after_first = true }), filetype)
  end
end)

check('collects repeated tools and parsers once in first-declaration order', function()
  local bash_name, css_name = 'custom.languages.adapters.bash', 'custom.languages.adapters.css'
  local bash, css = package.loaded[bash_name], package.loaded[css_name]
  package.loaded[bash_name] = { mason_tools = { 'shared-tool', 'first-tool' }, treesitter_parsers = { 'shared-parser', 'first-parser' } }
  package.loaded[css_name] = { mason_tools = { 'shared-tool', 'second-tool' }, treesitter_parsers = { 'shared-parser', 'second-parser' } }
  local ok, collected = pcall(dofile, nvim_root .. '/lua/custom/languages/config.lua')
  package.loaded[bash_name], package.loaded[css_name] = bash, css
  assert(ok, collected)
  for field, suffix in pairs { mason_tools = 'tool', treesitter_parsers = 'parser' } do
    local selected = vim.tbl_filter(function(value) return value:match('%-' .. suffix .. '$') end, collected[field])
    assert(vim.deep_equal(selected, { 'shared-' .. suffix, 'first-' .. suffix, 'second-' .. suffix }), vim.inspect(selected))
  end
end)

check('rejects overlapping map ownership even when definitions agree', function()
  local bash_name = 'custom.languages.adapters.bash'
  local css_name = 'custom.languages.adapters.css'
  local bash, css = package.loaded[bash_name], package.loaded[css_name]
  for _, field in ipairs { 'lsp_servers', 'formatters_by_ft', 'format_on_save_disabled_filetypes', 'linters_by_ft', 'dap_by_ft' } do
    ---@type table|boolean
    local value = {}
    if field == 'format_on_save_disabled_filetypes' then value = false end
    package.loaded[bash_name] = { [field] = { duplicate = value } }
    package.loaded[css_name] = { [field] = { duplicate = value } }
    local ok, err = pcall(dofile, nvim_root .. '/lua/custom/languages/config.lua')
    package.loaded[bash_name], package.loaded[css_name] = bash, css
    assert(not ok, field .. ' must reject duplicate owners')
    for _, detail in ipairs { field, 'duplicate', 'bash', 'css' } do
      assert(tostring(err):find(detail, 1, true), tostring(err))
    end
  end
end)

check('activates the collected adapters after every shared surface is ready', function()
  local trace, saved_setups, saved_modules, saved_preloads = {}, {}, {}, {}
  for _, name in ipairs { 'c_cpp', 'java', 'javascript', 'python', 'rust' } do
    local adapter = require('custom.languages.adapters.' .. name)
    saved_setups[name] = adapter.setup
    adapter.setup = function() trace[#trace + 1] = name end
  end
  for _, name in ipairs { 'lsp', 'treesitter', 'format', 'dap' } do
    local module = 'custom.languages.' .. name
    saved_modules[module], saved_preloads[module] = package.loaded[module], package.preload[module]
    package.loaded[module] = nil
    package.preload[module] = function()
      assert(require('custom.languages.config').dap_by_ft.python, 'declarations must be complete before shared setup')
      trace[#trace + 1] = name
      return {}
    end
  end
  local ok, err = pcall(dofile, nvim_root .. '/lua/custom/languages/init.lua')
  for name, setup in pairs(saved_setups) do
    require('custom.languages.adapters.' .. name).setup = setup
  end
  for _, name in ipairs { 'lsp', 'treesitter', 'format', 'dap' } do
    local module = 'custom.languages.' .. name
    package.loaded[module], package.preload[module] = saved_modules[module], saved_preloads[module]
  end
  assert(ok, err)
  assert(vim.deep_equal(trace, { 'lsp', 'treesitter', 'format', 'dap', 'c_cpp', 'java', 'javascript', 'python', 'rust' }), vim.inspect(trace))
end)

check('declares C and C++ without expanding support to other clangd languages', function()
  assert(vim.deep_equal(languages.lsp_servers.clangd.filetypes, { 'c', 'cpp', 'c.doxygen', 'cpp.doxygen' }))
  assert(languages.lsp_servers.clangd.on_attach == nil and languages.lsp_servers.clangd.on_init == nil, 'upstream clangd callbacks must survive')
  assert(languages.lsp_servers.clangd.cmd == nil, 'clangd must retain upstream flags and project settings')
  for _, tool in ipairs { 'clangd', 'clang-format', 'codelldb' } do
    assert(contains(languages.mason_tools, tool), 'missing C/C++ tool: ' .. tool)
  end
  for _, filetype in ipairs { 'c', 'cpp' } do
    assert(contains(languages.treesitter_parsers, filetype), 'missing C/C++ parser: ' .. filetype)
    assert(vim.deep_equal(languages.formatters_by_ft[filetype], { 'clang-format' }))
    assert(languages.format_on_save_disabled_filetypes[filetype], 'C/C++ formatting must stay manual')
    assert(languages.linters_by_ft[filetype] == nil, 'clangd must own C/C++ diagnostics')
    assert(languages.dap_by_ft[filetype].lsp_client == 'clangd')
    assert(vim.deep_equal(languages.dap_by_ft[filetype].launch_types, { 'codelldb', 'lldb' }))
  end
end)

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

  assert_formatting_disabled(languages.lsp_servers.bashls.on_attach, 'BashLS')
end)

check('declares project-owned TypeScript and JavaScript tooling', function()
  assert(languages.lsp_servers.tsc ~= nil, 'missing TypeScript 7 native LSP configuration')
  assert(languages.lsp_servers.ts_ls ~= nil, 'missing mutually exclusive pre-TypeScript-7 compatibility client')
  assert_formatting_disabled(languages.lsp_servers.tsc.on_attach, 'TypeScript')
  assert_formatting_disabled(languages.lsp_servers.ts_ls.on_init, 'TypeScript compatibility')
  assert(not contains(languages.mason_tools, 'tsc'), 'Mason must not own the project TypeScript compiler')
  assert(contains(languages.mason_tools, 'typescript-language-server'), 'missing pre-TypeScript-7 compatibility wrapper')
  assert(contains(languages.mason_tools, 'js-debug-adapter'), 'missing JavaScript debug adapter')
  assert(contains(languages.mason_tools, 'eslint_d'), 'eslint_d must remain the JavaScript diagnostic owner')
  assert(vim.deep_equal(languages.linters_by_ft.javascript, { 'eslint_d' }))
  assert(vim.deep_equal(languages.linters_by_ft.typescript, { 'eslint_d' }))
  assert(vim.deep_equal(languages.formatters_by_ft.javascript, { 'prettierd', 'prettier', stop_after_first = true }))
  assert(vim.deep_equal(languages.formatters_by_ft.typescript, { 'prettierd', 'prettier', stop_after_first = true }))
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

  local client = assert_formatting_disabled(languages.lsp_servers.ruff.on_attach, 'Ruff', { hoverProvider = true })
  assert(not client.server_capabilities.hoverProvider, 'Ruff hover must defer to BasedPyright')
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
