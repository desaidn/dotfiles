local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')

package.path = table.concat({ nvim_root .. '/lua/?.lua', nvim_root .. '/lua/?/init.lua', package.path }, ';')

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end
  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function create_file(path, lines)
  assert(vim.fn.mkdir(vim.fs.dirname(path), 'p') == 1 or vim.uv.fs_stat(vim.fs.dirname(path)), 'failed to create fixture directory')
  assert(vim.fn.writefile(lines or {}, path) == 0, 'failed to create ' .. path)
end

local fixture = vim.fn.tempname()
local project_root = fixture .. '/workspace'
local source = project_root .. '/packages/web/src/index.ts'
local compiler = project_root .. '/node_modules/.bin/tsc'
create_file(project_root .. '/pnpm-lock.yaml')
create_file(source)
create_file(compiler, { '#!/bin/sh', 'echo "Version 7.0.2"' })
assert(vim.uv.fs_chmod(compiler, 493))
local expected_project_root = assert(vim.uv.fs_realpath(project_root))
local expected_compiler = vim.fs.joinpath(expected_project_root, 'node_modules', '.bin', 'tsc')

local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(bufnr, source)
vim.bo[bufnr].filetype = 'typescript'

local languages = require 'custom.languages.config'
local config = languages.lsp_servers.tsc
local original_rpc_start = vim.lsp.rpc.start
local original_has = vim.fn.has
local original_executable = vim.fn.executable
local original_exepath = vim.fn.exepath
local original_getcwd = vim.fn.getcwd
local original_system = vim.system
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_notify = vim.notify
local started
vim.lsp.rpc.start = function(command, dispatchers, options)
  started = { command = command, dispatchers = dispatchers, options = options }
  return started
end

local function root_for_config(server_config, path)
  local buffer = vim.fn.bufnr(path)
  local created = buffer == -1
  if created then
    buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buffer, path)
    vim.bo[buffer].filetype = 'typescript'
  end
  local root
  server_config.root_dir(buffer, function(value) root = value end)
  if created then vim.api.nvim_buf_delete(buffer, { force = true }) end
  return root
end

local function root_for(path) return root_for_config(config, path) end

local ok, err = xpcall(function()
  check('starts the workspace TypeScript 7 compiler for a project buffer', function()
    local root
    config.root_dir(bufnr, function(value) root = value end)
    assert(root == expected_project_root, ('expected %s, got %s'):format(expected_project_root, tostring(root)))

    local dispatchers = {}
    local result = config.cmd(dispatchers, { root_dir = root })
    assert(result == started)
    assert(vim.deep_equal(started.command, { expected_compiler, '--lsp', '--stdio' }), vim.inspect(started.command))
    assert(started.dispatchers == dispatchers)
    assert(vim.deep_equal(started.options, { cwd = expected_project_root }), vim.inspect(started.options))
  end)

  check('keeps nested TypeScript projects in one workspace-root client', function()
    local node_source = project_root .. '/packages/node/src/server.ts'
    create_file(project_root .. '/packages/node/tsconfig.json', { '{"compilerOptions":{"module":"nodenext"}}' })
    create_file(project_root .. '/packages/web/tsconfig.json', { '{"compilerOptions":{"moduleResolution":"bundler"}}' })
    create_file(node_source)
    assert(root_for(node_source) == expected_project_root, 'Node package must use the workspace root')
    assert(root_for(source) == expected_project_root, 'browser package must use the same workspace root')
  end)

  check('routes a pre-TypeScript-7 workspace to one project-owned compatibility client', function()
    local legacy_config = assert(languages.lsp_servers.ts_ls, 'missing pre-TypeScript-7 compatibility client')
    local legacy_root = fixture .. '/typescript-five'
    local legacy_source = legacy_root .. '/src/App.tsx'
    local legacy_compiler = legacy_root .. '/node_modules/.bin/tsc'
    local legacy_tsserver = legacy_root .. '/node_modules/typescript/lib/tsserver.js'
    create_file(legacy_root .. '/pnpm-lock.yaml')
    create_file(legacy_source)
    create_file(legacy_compiler, { '#!/bin/sh', 'echo "Version 5.9.3"' })
    create_file(legacy_tsserver)
    assert(vim.uv.fs_chmod(legacy_compiler, 493))
    local expected_legacy_root = assert(vim.uv.fs_realpath(legacy_root))
    local expected_legacy_tsserver = vim.fs.joinpath(expected_legacy_root, 'node_modules', 'typescript', 'lib', 'tsserver.js')

    assert(root_for(legacy_source) == nil, 'the native client must reject pre-TypeScript-7 projects')
    assert(root_for_config(legacy_config, legacy_source) == expected_legacy_root, 'the compatibility client must own the project')
    assert(root_for_config(legacy_config, source) == nil, 'the compatibility client must reject TypeScript 7 projects')

    local dispatchers = {}
    local result = legacy_config.cmd(dispatchers, { root_dir = expected_legacy_root })
    assert(result == started)
    assert(vim.deep_equal(started.command, { 'typescript-language-server', '--stdio' }), vim.inspect(started.command))
    assert(vim.deep_equal(started.options, { cwd = expected_legacy_root }), vim.inspect(started.options))

    local client_config = { root_dir = expected_legacy_root, init_options = { hostInfo = 'neovim' } }
    local initialize_params = {}
    legacy_config.before_init(initialize_params, client_config)
    assert(client_config.init_options.tsserver.path == expected_legacy_tsserver, vim.inspect(client_config.init_options))
    assert(client_config.init_options.hostInfo == 'neovim', 'upstream initialization options must survive routing')
    assert(initialize_params.initializationOptions == client_config.init_options, 'the initialize request must receive the exact project tsserver')

    local version_handler = assert(legacy_config.handlers and legacy_config.handlers['$/typescriptVersion'], 'missing project TypeScript enforcement')
    local stopped = {}
    local notices = {}
    local fake_client = {
      config = { root_dir = expected_legacy_root },
      stop = function(_, force) stopped[#stopped + 1] = force end,
    }
    vim.lsp.get_client_by_id = function(client_id)
      assert(client_id == 42)
      return fake_client
    end
    vim.notify = function(message, level) notices[#notices + 1] = { message = message, level = level } end

    version_handler(nil, { version = '5.9.3', source = 'user-setting' }, { client_id = 42 })
    assert(#stopped == 0, 'the exact project TypeScript must remain attached')
    version_handler(nil, { version = '6.0.3', source = 'bundled' }, { client_id = 42 })
    assert(stopped[1] == true, 'a bundled TypeScript fallback must be terminated')
    version_handler(nil, { version = '5.8.2', source = 'user-setting' }, { client_id = 42 })
    assert(stopped[2] == true, 'a mismatched project TypeScript version must be terminated')
    assert(#notices == 2 and notices[1].level == vim.log.levels.ERROR, vim.inspect(notices))
    vim.lsp.get_client_by_id = original_get_client_by_id
    vim.notify = original_notify
  end)

  check('does not attach outside a project-local TypeScript 7 workspace', function()
    local legacy_config = languages.lsp_servers.ts_ls
    local missing_root = fixture .. '/missing-compiler'
    local missing_source = missing_root .. '/src/index.ts'
    create_file(missing_root .. '/package-lock.json')
    create_file(missing_source)
    vim.fn.exepath = function() error 'must not inspect PATH' end
    vim.fn.getcwd = function() error 'must not inspect Neovim cwd' end
    local rooted, missing_result = pcall(function()
      assert(root_for(missing_source) == nil)
      return root_for_config(legacy_config, missing_source)
    end)
    vim.fn.exepath = original_exepath
    vim.fn.getcwd = original_getcwd
    assert(rooted, missing_result)
    assert(missing_result == nil, 'must not fall back to a PATH compiler')

    local invalid_root = fixture .. '/invalid-version'
    local invalid_source = invalid_root .. '/src/index.ts'
    local invalid_compiler = invalid_root .. '/node_modules/.bin/tsc'
    create_file(invalid_root .. '/package-lock.json')
    create_file(invalid_source)
    create_file(invalid_compiler, { '#!/bin/sh', 'echo "not a TypeScript version"' })
    create_file(invalid_root .. '/node_modules/typescript/lib/tsserver.js')
    assert(vim.uv.fs_chmod(invalid_compiler, 493))
    assert(root_for(invalid_source) == nil, 'the native route must reject an unparseable project version')
    assert(root_for_config(legacy_config, invalid_source) == nil, 'compatibility must reject an unparseable project version')

    local legacy_root = fixture .. '/typescript-six'
    local legacy_source = legacy_root .. '/src/index.ts'
    local legacy_compiler = legacy_root .. '/node_modules/.bin/tsc'
    create_file(legacy_root .. '/yarn.lock')
    create_file(legacy_source)
    create_file(legacy_compiler, { '#!/bin/sh', 'echo "Version 6.0.3"' })
    assert(vim.fn.mkdir(legacy_root .. '/node_modules/typescript/lib/tsserver.js', 'p') == 1)
    assert(vim.uv.fs_chmod(legacy_compiler, 493))
    assert(root_for(legacy_source) == nil, 'TypeScript 6 must use an explicit compatibility lane')
    assert(root_for_config(legacy_config, legacy_source) == nil, 'a compatibility project must provide a root-local tsserver file')

    local deno_source = project_root .. '/packages/deno/mod.ts'
    create_file(project_root .. '/packages/deno/deno.json')
    create_file(deno_source)
    assert(root_for(deno_source) == nil, 'a nearer Deno project must own its TypeScript buffers')
    assert(root_for_config(legacy_config, deno_source) == nil, 'Deno must not use the compatibility client')

    create_file(project_root .. '/deno.json')
    assert(root_for(source) == nil, 'a Deno config at the workspace root must own its TypeScript buffers')
    assert(vim.fn.delete(project_root .. '/deno.json') == 0)

    create_file(project_root .. '/deno.lock')
    assert(root_for(source) == expected_project_root, 'a root-level Deno lock must not override the package-manager root')
    assert(vim.fn.delete(project_root .. '/deno.lock') == 0)

    local deno_lock_source = project_root .. '/packages/deno-lock/mod.ts'
    create_file(project_root .. '/packages/deno-lock/deno.lock')
    create_file(deno_lock_source)
    assert(root_for(deno_lock_source) == nil, 'a nearer Deno lock must own its TypeScript buffers')

    local unowned_source = fixture .. '/unowned/index.ts'
    create_file(unowned_source)
    assert(root_for(unowned_source) == nil, 'an unowned buffer must not fall back to Neovim cwd')
    assert(root_for_config(legacy_config, unowned_source) == nil, 'compatibility must not fall back to Neovim cwd')
  end)

  check('does not attach TypeScript to unnamed or special buffers', function()
    local special_source = project_root .. '/src/generated.ts'
    create_file(special_source)
    local unnamed = vim.api.nvim_create_buf(true, false)
    local special = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(special, special_source)
    vim.bo[special].filetype = 'typescript'
    local unnamed_root
    local special_root
    config.root_dir(unnamed, function(value) unnamed_root = value end)
    config.root_dir(special, function(value) special_root = value end)
    vim.api.nvim_buf_delete(unnamed, { force = true })
    vim.api.nvim_buf_delete(special, { force = true })
    assert(unnamed_root == nil, 'unnamed buffers must not join a project LSP workspace')
    assert(special_root == nil, 'special buffers must not join a project LSP workspace')
  end)

  check('uses the project npm command shim on Windows', function()
    local windows_root = fixture .. '/windows-workspace'
    local windows_source = windows_root .. '/src/index.ts'
    local windows_compiler = windows_root .. '/node_modules/.bin/tsc.cmd'
    create_file(windows_root .. '/package-lock.json')
    create_file(windows_source)
    create_file(windows_compiler)

    local expected_windows_root = assert(vim.uv.fs_realpath(windows_root))
    local expected_windows_compiler = vim.fs.joinpath(expected_windows_root, 'node_modules', '.bin', 'tsc.cmd')

    local buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buffer, windows_source)
    vim.bo[buffer].filetype = 'typescript'
    vim.fn.has = function(feature)
      if feature == 'win32' then return 1 end
      return original_has(feature)
    end
    vim.fn.executable = function(path)
      if path == expected_windows_compiler then return 1 end
      return original_executable(path)
    end
    vim.system = function(command, options)
      assert(vim.deep_equal(command, { expected_windows_compiler, '--version' }), vim.inspect(command))
      assert(vim.deep_equal(options, { text = true }), vim.inspect(options))
      return { wait = function() return { code = 0, stdout = 'Version 7.0.2' } end }
    end
    local root
    local rooted, root_error = pcall(config.root_dir, buffer, function(value) root = value end)
    vim.fn.has = original_has
    vim.fn.executable = original_executable
    vim.system = original_system
    vim.api.nvim_buf_delete(buffer, { force = true })

    assert(rooted, root_error)
    assert(root == expected_windows_root, ('expected %s, got %s'):format(expected_windows_root, tostring(root)))
    config.cmd({}, { root_dir = root })
    assert(started.command[1] == expected_windows_compiler, vim.inspect(started.command))
  end)
end, debug.traceback)

vim.lsp.rpc.start = original_rpc_start
vim.fn.has = original_has
vim.fn.executable = original_executable
vim.fn.exepath = original_exepath
vim.fn.getcwd = original_getcwd
vim.system = original_system
vim.lsp.get_client_by_id = original_get_client_by_id
vim.notify = original_notify
vim.api.nvim_buf_delete(bufnr, { force = true })
vim.fn.delete(fixture, 'rf')

if not ok then
  failures[#failures + 1] = 'initializes the TypeScript test fixture'
  io.stderr:write('FAIL initializes the TypeScript test fixture\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

if #failures > 0 then error(string.format('%d TypeScript check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All TypeScript configuration checks passed.\n'
