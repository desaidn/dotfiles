-- Uses installed pinned plugins and the Python parser; never launches a debugger.
local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/../..')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
vim.opt.packpath:prepend(vim.fn.stdpath 'data' .. '/site')
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/site')
local function ignore_packages() end
vim.pack.add = ignore_packages
package.loaded['mason-registry'] = {
  get_package = function()
    return { get_install_path = function() return vim.fn.stdpath 'data' .. '/mason/packages/debugpy' end }
  end,
}

local fixture = vim.fn.tempname()
local previous = vim.fn.getcwd()
local original_virtual_env, original_conda_prefix = vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX
local original_env_file = vim.env.DOTFILES_TEST_ENV_FILE
local original_input, original_ui_input = vim.fn.input, vim.ui.input
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = nil, nil
local captured
local explicit_pythons = { '/configured/python', { '/configured/python', '-I' }, function() return { '/configured/python', '-I' } end }
local test_lines = { 'import unittest', '', 'class TestThing(unittest.TestCase):', '    def test_one(self):', '        assert True' }
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0)
end
local function expand_config(config)
  local dap = require 'dap'
  local finished, success, result = false, false, nil
  require('dap.async').run(function()
    success, result = xpcall(function()
      local metatable = getmetatable(config)
      if metatable and type(metatable.__call) == 'function' then config = config() end
      return dap.listeners.on_config['dap.expand_variable'](config)
    end, debug.traceback)
    finished = true
  end)
  assert(vim.wait(1000, function() return finished end), 'native configuration expansion did not finish')
  if success then return result end
  return nil, result
end
local function enrich(config, before_enrichment)
  local expanded, expansion_error = expand_config(config)
  assert(expanded, expansion_error)
  local enriched
  require('dap').adapters[expanded.type](function(adapter)
    if before_enrichment then before_enrichment() end
    adapter.enrich_config(expanded, function(value) enriched = value end)
  end, expanded)
  assert(vim.wait(1000, function() return enriched ~= nil end), 'native adapter must finish configuration enrichment')
  return enriched
end
local ok, err = xpcall(function()
  -- Keep expected paths canonical; the explicit alias below exercises symlinks.
  vim.fn.mkdir(fixture, 'p')
  fixture = assert(vim.uv.fs_realpath(fixture))
  write(fixture .. '/other/pytest.ini', {})
  write(fixture .. '/project/pyproject.toml', {})
  write(fixture .. '/project/test_case.py', test_lines)
  write(fixture .. '/project/.env', { 'DOTFILES_TEST_PROJECT=source' })
  write(fixture .. '/other/.env', { 'DOTFILES_TEST_PROJECT=unrelated' })
  assert(vim.uv.fs_symlink(fixture .. '/project', fixture .. '/alias', { dir = true }))
  vim.cmd.cd(fixture .. '/other')
  vim.cmd.edit(fixture .. '/alias/test_case.py')
  vim.bo.filetype = 'python'
  require('custom.languages.adapters.python').setup()
  assert(package.loaded.dap == nil, 'fixture must start with DAP unloaded')

  -- Capture only the external launch, while retaining real lazy setup and test generation.
  package.preload.dap = function()
    package.preload.dap = nil
    package.loaded.dap = nil
    local dap = require 'dap'
    dap.configurations.python = {}
    for index, python in ipairs(explicit_pythons) do
      table.insert(dap.configurations.python, { name = 'Explicit Python ' .. index, type = 'python', request = 'launch', python = python })
    end
    dap.run = function(config) captured = config end
    return dap
  end
  vim.api.nvim_win_set_cursor(0, { 5, 8 })
  vim.cmd.DapPythonTestClass()
  local launch = captured
  assert(launch and launch.module == 'unittest', vim.inspect(launch))
  assert(vim.deep_equal(launch.args, { '-v', 'test_case.TestThing' }), vim.inspect(launch.args))
  assert(vim.uv.fs_realpath(launch.cwd) == vim.uv.fs_realpath(fixture .. '/project'), vim.inspect(launch))
  assert(vim.fn.getcwd() == vim.uv.fs_realpath(fixture .. '/other'), 'test generation changed editor cwd')
  local generated = require('dap').providers.configs['dap.global'](vim.api.nvim_get_current_buf())
  assert(generated[4].cwd and vim.uv.fs_realpath(generated[4].cwd) == fixture .. '/project', 'generated file launch omitted its source project directory')
  assert(enrich(launch).env.DOTFILES_TEST_PROJECT == 'source', 'test enrichment read the editor directory environment')

  local defaults = require('dap').providers.configs['dap.global'](vim.api.nvim_get_current_buf())
  for index, python in ipairs(explicit_pythons) do
    assert(type(defaults[index].python) == type(python) and defaults[index].pythonPath == nil, vim.inspect(defaults[index]))
    local expected = type(python) == 'function' and python() or python
    local enriched = enrich(defaults[index])
    assert(vim.deep_equal(enriched.python, expected) and enriched.pythonPath == nil, vim.inspect(enriched))
  end

  local source = vim.api.nvim_get_current_buf()
  local source_path = vim.api.nvim_buf_get_name(source)
  write(fixture .. '/other/other.py', { 'pass' })
  vim.cmd.edit(fixture .. '/other/other.py')
  local other = vim.api.nvim_get_current_buf()
  local argument_prompts = 0
  local function enter_arguments()
    argument_prompts = argument_prompts + 1
    return '--flag value'
  end
  vim.fn.input = enter_arguments
  local generated_count = 0
  for _, config in ipairs(defaults) do
    if config.name == 'file' or config.name == 'file:args' or config.name == 'file:doctest' then
      generated_count = generated_count + 1
      local enriched = enrich(config)
      assert(enriched.cwd == fixture .. '/project', vim.inspect(enriched))
      assert(enriched.env.DOTFILES_TEST_PROJECT == 'source', vim.inspect(enriched))
      assert((enriched.program or enriched.args[1]) == source_path, 'selection changed the source file: ' .. vim.inspect(enriched))
      if config.name == 'file:args' then assert(vim.deep_equal(enriched.args, { '--flag', 'value' }), vim.inspect(enriched)) end
    end
  end
  assert(generated_count == 3 and argument_prompts == 1, 'generated configurations or lazy argument prompt changed')
  vim.fn.input = original_input
  vim.api.nvim_set_current_buf(source)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.DapPythonTestClass()
  assert(vim.deep_equal(captured.args, { '-v', 'test_case' }), vim.inspect(captured.args))

  local dap_python = require 'dap-python'
  local runner_calls = 0
  dap_python.test_runner = function()
    runner_calls = runner_calls + 1
    assert(vim.uv.cwd() == vim.uv.fs_realpath(fixture .. '/project'), 'runner resolved outside source project')
    return 'unittest'
  end
  vim.api.nvim_win_set_cursor(0, { 5, 8 })
  vim.cmd.lcd(fixture .. '/other')
  vim.cmd.DapPythonTestMethod()
  assert(runner_calls == 1, 'callable runner must resolve exactly once')
  assert(vim.deep_equal(captured.args, { '-v', 'test_case.TestThing.test_one' }), vim.inspect(captured.args))
  assert(enrich(captured, function() vim.api.nvim_set_current_buf(other) end).env.DOTFILES_TEST_PROJECT == 'source')
  vim.api.nvim_set_current_buf(source)
  assert(vim.fn.haslocaldir() == 1 and vim.fn.getcwd() == vim.uv.fs_realpath(fixture .. '/other'), 'callable runner changed window directory scope')
  dap_python.test_runner = nil

  for _, runner in ipairs { 'unittest', 'django' } do
    local built_in = dap_python.test_runners[runner]
    dap_python.test_runner = runner
    dap_python.test_runners[runner] = function(classes, method)
      local module, args = built_in(classes, method)
      table.insert(args, 2, '--extra-flag')
      return module, args
    end
    vim.cmd.DapPythonTestMethod()
    local first = runner == 'unittest' and '-v' or 'test'
    assert(vim.deep_equal(captured.args, { first, '--extra-flag', 'test_case.TestThing.test_one' }), vim.inspect(captured.args))
    dap_python.test_runners[runner] = function() return runner, { '--keep', 'intentional.relative.target' } end
    vim.cmd.DapPythonTestMethod()
    assert(vim.deep_equal(captured.args, { '--keep', 'intentional.relative.target' }), vim.inspect(captured.args))
    assert(vim.fn.haslocaldir() == 1 and vim.fn.getcwd() == vim.uv.fs_realpath(fixture .. '/other'), 'custom runner changed window directory scope')
    dap_python.test_runners[runner] = built_in
  end
  dap_python.test_runner = nil

  write(fixture .. '/project/pytest.ini', {})
  vim.cmd.lcd(fixture .. '/other')
  vim.cmd.DapPythonTestMethod()
  launch = captured
  assert(launch.module == 'pytest', vim.inspect(launch))
  assert(vim.deep_equal(launch.args, { '-s', vim.api.nvim_buf_get_name(0) .. '::TestThing::test_one' }), vim.inspect(launch.args))
  assert(vim.uv.fs_realpath(launch.cwd) == vim.uv.fs_realpath(fixture .. '/project'))
  assert(vim.fn.haslocaldir() == 1 and vim.fn.getcwd() == vim.uv.fs_realpath(fixture .. '/other'), 'test command changed window directory scope')

  write(fixture .. '/project/.vscode/launch.json', {
    '{"configurations":[{"name":"Python","type":"python","request":"launch"},{"name":"Debugpy","type":"debugpy","request":"launch"}]}',
  })
  local launches = require('dap').providers.configs['dap.launch.json'](vim.api.nvim_get_current_buf())
  assert(#launches == 2 and launches[2].type == 'debugpy', 'modern debugpy launch was filtered out')
  for _, config in ipairs(launches) do
    assert(enrich(config).env.DOTFILES_TEST_PROJECT == 'source', 'project launch read the editor environment')
  end

  write(fixture .. '/project/config/debug.env', { 'DOTFILES_TEST_PROJECT=configured' })
  write(fixture .. '/explicit.env', { 'DOTFILES_TEST_PROJECT=absolute' })
  vim.env.DOTFILES_TEST_ENV_FILE = fixture .. '/explicit.env'
  local path_configs = {
    { name = 'Relative environment', envFile = './config/debug.env', cwd = fixture .. '/other', expected = 'configured' },
    { name = 'Workspace environment', envFile = '${workspaceFolder}/config/debug.env', expected = 'configured' },
    { name = 'Absolute environment', envFile = fixture .. '/explicit.env', expected = 'absolute' },
    { name = 'Environment variable', envFile = '${env:DOTFILES_TEST_ENV_FILE}', expected = 'absolute' },
    { name = 'Deferred input', envFile = '${input:environment}', expected = 'configured' },
  }
  local configs = {}
  for _, config in ipairs(path_configs) do
    configs[#configs + 1] = {
      name = config.name,
      type = 'debugpy',
      request = 'launch',
      pythonPath = '/configured/python',
      cwd = config.cwd or '${workspaceFolder}/runtime',
      envFile = config.envFile,
      env = { KEPT = 'explicit' },
    }
  end
  write(fixture .. '/project/.vscode/launch.json', {
    vim.json.encode { configurations = configs, inputs = { { id = 'environment', type = 'promptString' } } },
  })
  launches = require('dap').providers.configs['dap.launch.json'](source)
  local environment_prompts = 0
  local function select_environment(_, callback)
    environment_prompts = environment_prompts + 1
    vim.api.nvim_set_current_buf(other)
    callback '${workspaceFolder}/config/debug.env'
  end
  vim.ui.input = select_environment
  vim.api.nvim_set_current_buf(other)
  for index, config in ipairs(launches) do
    local enriched = enrich(config)
    assert(enriched.env.DOTFILES_TEST_PROJECT == path_configs[index].expected, vim.inspect(enriched))
    assert(enriched.env.KEPT == 'explicit' and enriched.pythonPath == '/configured/python', vim.inspect(enriched))
    assert(enriched.cwd == (path_configs[index].cwd or fixture .. '/project/runtime'), vim.inspect(enriched))
  end
  assert(environment_prompts == 1, 'deferred environment input must be prompted exactly once')
  vim.ui.input = original_ui_input
  local dap = require 'dap'
  local environment_calls = 0
  local callable_config = {
    type = 'python',
    request = 'launch',
    name = 'Callable environment',
    cwd = fixture .. '/other',
    envFile = function()
      environment_calls = environment_calls + 1
      return '${workspaceFolder}/config/debug.env'
    end,
  }
  table.insert(dap.configurations.python, callable_config)
  local callable_defaults = dap.providers.configs['dap.global'](source)
  local callable_enriched = enrich(callable_defaults[#callable_defaults])
  assert(callable_enriched.env and callable_enriched.env.DOTFILES_TEST_PROJECT == 'configured' and environment_calls == 1, vim.inspect(callable_enriched))
  assert(callable_enriched.cwd == fixture .. '/other', 'explicit global cwd was overwritten')
  local original_environment = { SOURCE_ROOT = '${workspaceFolder}' }
  local environment_metatable = { marker = 'unchanged' }
  setmetatable(original_environment, environment_metatable)
  callable_config.env = original_environment
  for _, kind in ipairs { 'returned', 'direct' } do
    for _, completion in ipairs { 'synchronous', 'scheduled', 'fast event' } do
      local executions = 0
      local function environment_thread()
        return coroutine.create(function(co)
          executions = executions + 1
          local function complete() assert(coroutine.resume(co, '${workspaceFolder}/config/debug.env')) end
          if completion == 'scheduled' then
            vim.schedule(complete)
          elseif completion == 'fast event' then
            local timer = assert(vim.uv.new_timer())
            timer:start(0, 0, function()
              timer:close()
              complete()
            end)
          else
            complete()
          end
        end)
      end
      local option = kind == 'returned' and environment_thread or environment_thread()
      callable_config.envFile = option
      callable_defaults = dap.providers.configs['dap.global'](source)
      local thread_enriched = enrich(callable_defaults[#callable_defaults])
      assert(thread_enriched.env.DOTFILES_TEST_PROJECT == 'configured', kind .. ' ' .. completion .. ' lost source context')
      assert(thread_enriched.env.SOURCE_ROOT == fixture .. '/project' and executions == 1, 'thread ran more than once or changed root')
      assert(callable_config.envFile == option and callable_config.env == original_environment, 'preparation mutated the source configuration')
      assert(original_environment.SOURCE_ROOT == '${workspaceFolder}' and getmetatable(original_environment) == environment_metatable)
    end
  end
  local function abort_environment() return dap.ABORT end
  local function abort_thread()
    return coroutine.create(function(co) coroutine.resume(co, dap.ABORT) end)
  end
  for _, option in ipairs { abort_environment, abort_thread, abort_thread(), dap.ABORT } do
    callable_config.envFile = option
    callable_defaults = dap.providers.configs['dap.global'](source)
    local aborted = assert(expand_config(callable_defaults[#callable_defaults]))
    assert(aborted.envFile == dap.ABORT, 'deferred environment lost the native abort sentinel')
  end
  for _, kind in ipairs { 'returned', 'direct' } do
    for _, failure in ipairs { 'dead', 'failed' } do
      local function failing_thread()
        if failure == 'failed' then
          return coroutine.create(function() error 'fixture environment failure' end)
        end
        local dead = coroutine.create(function() end)
        assert(coroutine.resume(dead))
        return dead
      end
      callable_config.envFile = kind == 'returned' and failing_thread or failing_thread()
      callable_defaults = dap.providers.configs['dap.global'](source)
      local rejected, rejection = expand_config(callable_defaults[#callable_defaults])
      local expected = failure == 'dead' and 'must be suspended' or 'fixture environment failure'
      assert(not rejected and rejection and rejection:find(expected, 1, true), kind .. ' ' .. failure .. ': ' .. tostring(rejection))
    end
  end
  table.remove(dap.configurations.python)
  dap.configurations.lua = { { type = 'local-lua', name = 'Unaffected language' } }
  vim.bo[other].filetype = 'lua'
  assert(dap.providers.configs['dap.global'](other) == dap.configurations.lua, 'Python preparation changed another language')
  vim.api.nvim_set_current_buf(source)

  for _, project_marker in ipairs { 'requirements.txt', 'pyproject.toml' } do
    for marker, runner in pairs { ['pytest.ini'] = 'pytest', ['manage.py'] = 'django' } do
      local project = fixture .. '/' .. runner .. '-' .. project_marker
      local interpreter = project .. (vim.fn.has 'win32' == 1 and '/.venv/Scripts/python.exe' or '/.venv/bin/python')
      write(project .. '/' .. project_marker, {})
      write(project .. '/tests/' .. marker, {})
      write(project .. '/tests/test_case.py', test_lines)
      write(project .. '/.env', { 'DOTFILES_TEST_PROJECT=parent' })
      write(project .. '/tests/.env', { 'DOTFILES_TEST_PROJECT=nested' })
      write(interpreter, { '#!/bin/sh', 'exit 0' })
      assert(vim.uv.fs_chmod(interpreter, 493))
      write(project .. '/.vscode/launch.json', {
        vim.json.encode {
          configurations = {
            { name = 'Python', type = 'python', request = 'launch' },
            { name = 'Debugpy', type = 'debugpy', request = 'launch' },
            { name = 'Explicit string', type = 'debugpy', request = 'launch', python = explicit_pythons[1] },
            { name = 'Explicit list', type = 'python', request = 'launch', python = explicit_pythons[2] },
          },
        },
      })
      vim.cmd.edit(project .. '/tests/test_case.py')
      vim.bo.filetype = 'python'
      vim.api.nvim_win_set_cursor(0, { 5, 8 })
      vim.cmd.DapPythonTestMethod()
      assert(captured.module == runner and captured.cwd == project .. '/tests', vim.inspect(captured))
      assert(captured.pythonPath == interpreter, 'nested test config lost the parent project environment: ' .. vim.inspect(captured))
      assert(enrich(captured).env.DOTFILES_TEST_PROJECT == 'nested', 'nested method loaded the wrong environment file')
      vim.cmd.DapPythonTestClass()
      assert(enrich(captured).env.DOTFILES_TEST_PROJECT == 'nested', 'nested class loaded the wrong environment file')
      assert(vim.fn.haslocaldir() == 1 and vim.fn.getcwd() == vim.uv.fs_realpath(fixture .. '/other'), 'nested test changed window directory scope')

      for _, config in ipairs(require('dap').providers.configs['dap.global'](vim.api.nvim_get_current_buf())) do
        if config.request == 'launch' and not config.python then
          assert(config.pythonPath == interpreter, 'nested test config changed the default DAP interpreter')
        end
      end
      launches = require('dap').providers.configs['dap.launch.json'](vim.api.nvim_get_current_buf())
      assert(#launches == 4, 'nested test config hid the parent launch.json')
      for index, config in ipairs(launches) do
        assert(config.cwd == project, 'test root leaked into project launch directory')
        local enriched = enrich(config)
        assert(enriched.env.DOTFILES_TEST_PROJECT == 'parent', 'test environment leaked into a project launch')
        if index <= 2 then
          assert(enriched.pythonPath == interpreter, vim.inspect(enriched))
        else
          assert(vim.deep_equal(enriched.python, explicit_pythons[index - 2]) and enriched.pythonPath == nil, vim.inspect(enriched))
        end
      end
      local child = project .. '/tests/child'
      write(child .. '/requirements.txt', {})
      write(child .. '/test_case.py', test_lines)
      vim.cmd.edit(child .. '/test_case.py')
      vim.bo.filetype = 'python'
      vim.api.nvim_win_set_cursor(0, { 5, 8 })
      vim.cmd.DapPythonTestMethod()
      assert(captured.module == 'unittest' and captured.cwd == child, 'ancestor test config overrode a nearer project marker: ' .. vim.inspect(captured))
      assert(vim.deep_equal(captured.args, { '-v', 'test_case.TestThing.test_one' }), vim.inspect(captured.args))
      if project_marker == 'pyproject.toml' then assert(captured.pythonPath == interpreter, 'test root selection changed environment marker priority') end
    end
  end
end, debug.traceback)
vim.cmd.cd(previous)
vim.fs.rm(fixture, { recursive = true, force = true })
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = original_virtual_env, original_conda_prefix
vim.env.DOTFILES_TEST_ENV_FILE = original_env_file
vim.fn.input, vim.ui.input = original_input, original_ui_input
assert(ok, err)
io.stdout:write 'All native Python test-command checks passed.\n'
