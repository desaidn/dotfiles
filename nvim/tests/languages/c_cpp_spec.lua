-- Exercise installed LSP defaults, Conform, and nvim-dap without starting servers.
local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/../..')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
vim.opt.packpath:prepend(vim.fn.stdpath 'data' .. '/site')
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/site')
local function ignore_packages() end
vim.pack.add = ignore_packages
vim.cmd.packadd 'conform.nvim'
vim.cmd.packadd 'nvim-lspconfig'
local conform = require 'conform'
local adapter = require 'custom.languages.adapters.c_cpp'
conform.setup { formatters_by_ft = adapter.formatters_by_ft }
adapter.setup()

local failures = {}
local function check(name, body)
  local ok, err = xpcall(body, debug.traceback)
  if ok then
    io.stdout:write('PASS ', name, '\n')
  else
    failures[#failures + 1] = name
    io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
  end
end

local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
fixture = assert(vim.uv.fs_realpath(fixture))
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0)
end
local function buffer(path, filetype)
  write(path, { 'int main() { return 0; }' })
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  vim.bo[bufnr].filetype = filetype
  return bufnr
end
local original_exepath, original_input = vim.fn.exepath, vim.fn.input
local original_get_client = vim.lsp.get_client_by_id
local original_notify_once = vim.notify_once
local cwd_before = vim.fn.getcwd()
local executable = fixture .. '/tools/codelldb'
write(executable, { '#!/bin/sh', 'exit 0' })
assert(vim.uv.fs_chmod(executable, 493))
local function codelldb_on_path(command)
  if command == 'codelldb' then return executable end
  return original_exepath(command)
end
vim.fn.exepath = codelldb_on_path
write(fixture .. '/one/.git', {})
write(fixture .. '/one/CMakeLists.txt', {})
write(fixture .. '/one/src/CMakeLists.txt', {})
write(fixture .. '/two/compile_flags.txt', { '-std=c17' })
local cpp = buffer(fixture .. '/one/src/main.cpp', 'cpp')
local c = buffer(fixture .. '/two/main.c', 'c')

check('keeps clangd upstream source/header commands and encoding negotiation', function()
  vim.lsp.config('clangd', adapter.lsp_servers.clangd)
  local config = assert(vim.lsp.config.clangd)
  assert(vim.deep_equal(config.cmd, { 'clangd' }))
  local clangd = {
    id = 81,
    name = 'clangd',
    server_capabilities = { documentFormattingProvider = true, documentRangeFormattingProvider = true, hoverProvider = true },
  }
  assert(config.on_init)(clangd --[[@as vim.lsp.Client]], { capabilities = {}, offsetEncoding = 'utf-8' })
  assert(clangd.offset_encoding == 'utf-8', 'upstream encoding negotiation was overwritten')
  assert(config.on_attach)(clangd --[[@as vim.lsp.Client]], cpp)
  local commands = vim.api.nvim_buf_get_commands(cpp, {})
  for _, name in ipairs { 'LspClangdSwitchSourceHeader', 'LspClangdShowSymbolInfo' } do
    assert(commands[name], 'upstream clangd command was overwritten: ' .. name)
  end
  local function get_clangd() return clangd end
  vim.lsp.get_client_by_id = get_clangd
  vim.api.nvim_exec_autocmds('LspAttach', { buffer = cpp, data = { client_id = clangd.id } })
  assert(not clangd.server_capabilities.documentFormattingProvider and not clangd.server_capabilities.documentRangeFormattingProvider)
  assert(clangd.server_capabilities.hoverProvider, 'formatting policy changed another clangd capability')
  clangd.name = 'other'
  clangd.server_capabilities.documentFormattingProvider = true
  vim.api.nvim_exec_autocmds('LspAttach', { buffer = cpp, data = { client_id = clangd.id } })
  assert(clangd.server_capabilities.documentFormattingProvider, 'C/C++ setup changed another server')
  vim.lsp.get_client_by_id = original_get_client
end)

check('defers CodeLLDB registration until a C/C++ debugger action', function()
  assert(package.loaded.dap == nil, 'opening C/C++ must not load nvim-dap')
  local dap = require('custom.languages.dap').ensure_buffer(cpp)
  local registered = dap.adapters.codelldb
  assert(registered.type == 'server' and registered.host == '127.0.0.1' and registered.port == '${port}')
  assert(registered.executable.command == executable and vim.deep_equal(registered.executable.args, { '--port', '${port}' }))
  assert(dap.providers.configs['c_cpp.defaults'], 'cold C++ setup did not provide default launches')
  require('custom.languages.dap').ensure_buffer(c)
  assert(dap.adapters.codelldb == registered, 'C registration replaced the shared adapter')
end)

check('freezes executable prompts and cwd to the initiating project before selection', function()
  local dap = require 'dap'
  local defaults = dap.providers.configs['c_cpp.defaults']
  local first, second = defaults(cpp), defaults(c)
  assert(#first == 2 and #second == 2)
  assert(first[1].cwd == fixture .. '/one', 'nested CMakeLists hid the repository root')
  assert(second[1].cwd == fixture .. '/two')
  assert(first[2].request == 'attach' and first[2].pid == require('dap.utils').pick_process)
  vim.api.nvim_set_current_buf(c)
  local function select_executable(_, initial, completion)
    assert(initial == fixture .. '/one/' and completion == 'file', 'prompt used a later buffer')
    return initial .. 'build/app'
  end
  vim.fn.input = select_executable
  assert(first[1].program() == fixture .. '/one/build/app')
  local function cancel_input() return '' end
  vim.fn.input = cancel_input
  assert(first[1].program() == dap.ABORT, 'cancelling an executable prompt must abort')
  vim.fn.input = original_input
  assert(vim.fn.getcwd() == cwd_before, 'debugger discovery changed editor cwd')
end)

check('preserves explicit C/C++ launches and suppresses unnecessary generic choices', function()
  local dap = require 'dap'
  local custom = { { name = 'My C++ program', type = 'codelldb', request = 'launch', program = '/custom/program' } }
  dap.configurations.cpp = custom
  require('custom.languages.dap').ensure_buffer(cpp)
  assert(dap.configurations.cpp == custom, 'C++ setup replaced user configurations')
  assert(#dap.providers.configs['c_cpp.defaults'](cpp) == 0)
  dap.configurations.cpp = nil
  write(fixture .. '/one/.vscode/launch.json', {
    vim.json.encode {
      configurations = {
        { name = 'Project', type = 'lldb', request = 'launch', program = '${workspaceFolder}/app', args = { '${relativeFile}', 'two words' } },
      },
    },
  })
  local launches = dap.providers.configs['dap.launch.json'](cpp)
  assert(#launches == 1 and launches[1].type == 'codelldb')
  assert(launches[1].cwd == fixture .. '/one' and launches[1].program == fixture .. '/one/app')
  assert(vim.deep_equal(launches[1].args, { 'src/main.cpp', 'two words' }))
  assert(#dap.providers.configs['c_cpp.defaults'](cpp) == 0)
end)

check('selects project metadata within repository boundaries and supports standalone files', function()
  local profile = adapter.dap_by_ft.cpp.root_profile
  local resolve = profile.resolve
  write(fixture .. '/.vscode/launch.json', { '{}' })
  write(fixture .. '/isolated/.git', {})
  write(fixture .. '/isolated/.clangd', {})
  write(fixture .. '/isolated/nested/CMakeLists.txt', {})
  local source = fixture .. '/isolated/nested/main.cpp'
  assert(resolve(source) == fixture .. '/isolated', 'inherited launch outside repository changed root')
  write(fixture .. '/isolated/nested/compile_commands.json', { '[]' })
  assert(resolve(source) == fixture .. '/isolated/nested', 'nearer explicit compiler settings were ignored')
  write(fixture .. '/isolated/.vscode/launch.json', { '{}' })
  assert(resolve(source) == fixture .. '/isolated', 'explicit launch root should win over compiler metadata')
  vim.fn.delete(fixture .. '/.vscode', 'rf')
  assert(resolve(fixture .. '/standalone/main.c') == fixture .. '/standalone')
  assert(#require('dap').providers.configs['c_cpp.defaults'](vim.api.nvim_create_buf(false, true)) == 0)
end)

check('inherits native formatting filename and range arguments for a per-buffer executable', function()
  local capture = fixture .. '/formatter-args'
  local formatter = fixture .. '/tools/pinned clang-format'
  write(formatter, { '#!/bin/sh', 'printf "%s\\n" "$@" > ' .. vim.fn.shellescape(capture), 'cat' })
  assert(vim.uv.fs_chmod(formatter, 493))
  vim.b[cpp].clang_format = formatter
  local config = assert(conform.get_formatter_config('clang-format', cpp))
  assert(config.command == formatter and config.stdin == true and type(config.range_args) == 'function')
  local callback_error
  conform.format({ bufnr = cpp, async = false, lsp_format = 'never' }, function(err) callback_error = err end)
  assert(callback_error == nil, callback_error)
  assert(vim.deep_equal(vim.fn.readfile(capture), { '-assume-filename', vim.api.nvim_buf_get_name(cpp) }))
  conform.format({ bufnr = cpp, async = false, range = { start = { 1, 0 }, ['end'] = { 1, 9 } }, lsp_format = 'never' }, function(err) callback_error = err end)
  assert(callback_error == nil, callback_error)
  local args = vim.fn.readfile(capture)
  assert(args[1] == '-assume-filename' and args[2] == vim.api.nvim_buf_get_name(cpp) and args[3] == '--offset' and args[5] == '--length')
  assert(conform.get_formatter_config('clang-format', c).command == 'clang-format', 'buffer-local version affected another project')
end)

check('reports an explicitly missing formatter without silently selecting another version', function()
  local message
  local function capture_notification(value) message = value end
  vim.notify_once = capture_notification
  vim.b[cpp].clang_format = fixture .. '/missing/clang-format'
  local info = conform.get_formatter_info('clang-format', cpp)
  assert(not info.available and info.command == vim.b[cpp].clang_format)
  assert(info.available_msg:find(vim.b[cpp].clang_format, 1, true), info.available_msg)
  assert(message and message:find(vim.b[cpp].clang_format, 1, true), 'missing explicit formatter did not identify its command')
  vim.b[cpp].clang_format = nil
  vim.notify_once = original_notify_once
  local override = { command = 'my-formatter' }
  local original = conform.formatters['clang-format']
  conform.formatters['clang-format'] = override
  adapter.setup()
  assert(conform.formatters['clang-format'] == override, 'setup replaced a native user override')
  conform.formatters['clang-format'] = original
end)

check('preserves CodeLLDB registered before C/C++ and retries missing installations', function()
  local dap = require 'dap'
  local saved = dap.adapters.codelldb
  local rust_adapter =
    { type = 'server', host = '127.0.0.1', port = '${port}', executable = { command = '/rust/codelldb', args = { '--liblldb', '/rust/liblldb' } } }
  dap.adapters.codelldb = rust_adapter
  require('custom.languages.dap').ensure_buffer(cpp)
  assert(dap.adapters.codelldb == rust_adapter, 'C++ replaced the existing Rust/user adapter')
  dap.adapters.codelldb = nil
  local settings = package.loaded['mason.settings']
  package.loaded['mason.settings'] = { current = { install_root_dir = fixture .. '/missing-mason' } }
  local function missing_codelldb(command)
    if command == 'codelldb' then return '' end
    return original_exepath(command)
  end
  vim.fn.exepath = missing_codelldb
  local ok, err = pcall(require('custom.languages.dap').ensure_buffer, cpp)
  assert(not ok and tostring(err):find('Install codelldb with :Mason', 1, true), tostring(err))
  local mason_executable = fixture .. '/missing-mason/packages/codelldb/extension/adapter/codelldb'
  write(mason_executable, { '#!/bin/sh', 'exit 0' })
  assert(vim.uv.fs_chmod(mason_executable, 493))
  require('custom.languages.dap').ensure_buffer(cpp)
  assert(dap.adapters.codelldb.executable.command == mason_executable, 'failed installation poisoned later setup')
  package.loaded['mason.settings'] = settings
  dap.adapters.codelldb = saved
  vim.fn.exepath = original_exepath
end)

check('shares the adapter with actual rustaceanvim launch registration in either startup order', function()
  vim.cmd.packadd 'rustaceanvim'
  local dap = require 'dap'
  local config = require 'rustaceanvim.config.internal'
  local saved_config = config.dap
  local saved_system = vim.system
  local c_adapter = dap.adapters.codelldb
  local rust_adapter = require('rustaceanvim.config').get_codelldb_adapter(executable, fixture .. '/liblldb')
  config.dap = {
    adapter = rust_adapter,
    configuration = { name = 'Rust', type = 'codelldb', request = 'launch' },
    auto_generate_source_map = false,
    load_rust_types = false,
    add_dynamic_library_paths = false,
  }
  ---@return vim.SystemObj
  local function cargo_artifact(_, _, callback)
    callback {
      code = 0,
      stdout = vim.json.encode {
        reason = 'compiler-artifact',
        target = { crate_types = { 'bin' }, kind = { 'bin' } },
        profile = { test = false },
        executable = fixture .. '/rust-app',
      } .. '\n',
    }
    local process = { pid = 1 }
    return process --[[@as vim.SystemObj]]
  end
  vim.system = cargo_artifact
  local ok, err = xpcall(function()
    for _, rust_first in ipairs { false, true } do
      if rust_first then dap.adapters.codelldb = nil end
      local launched, launch_error
      require('rustaceanvim.dap').start(
        { cargoArgs = { 'build' }, workspaceRoot = fixture, executableArgs = { 'example' } },
        false,
        function(value) launched = value end,
        function(value) launch_error = value end
      )
      assert(vim.wait(1000, function() return launched ~= nil or launch_error ~= nil end), 'Rust configuration did not complete')
      assert(launched and launched.program == fixture .. '/rust-app' and vim.deep_equal(launched.args, { 'example' }), tostring(launch_error))
      local expected = rust_first and rust_adapter or c_adapter
      assert(dap.adapters.codelldb == expected, 'Rust replaced the registered C/C++ adapter')
      require('custom.languages.dap').ensure_buffer(cpp)
      assert(dap.adapters.codelldb == expected, 'C/C++ replaced the registered Rust adapter')
    end
  end, debug.traceback)
  config.dap, vim.system, dap.adapters.codelldb = saved_config, saved_system, c_adapter
  assert(ok, err)
end)

vim.fn.exepath, vim.fn.input = original_exepath, original_input
vim.lsp.get_client_by_id, vim.notify_once = original_get_client, original_notify_once
vim.fn.delete(fixture, 'rf')
if #failures > 0 then error(string.format('%d C/C++ check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All C/C++ integration checks passed.\n'
