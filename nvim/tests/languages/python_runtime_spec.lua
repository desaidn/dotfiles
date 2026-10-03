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
vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = nil, nil
local captured
local explicit_pythons = { '/configured/python', { '/configured/python', '-I' }, function() return { '/configured/python', '-I' } end }
local test_lines = { 'import unittest', '', 'class TestThing(unittest.TestCase):', '    def test_one(self):', '        assert True' }
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0)
end
local function enrich(config)
  local dap = require 'dap'
  local enriched
  coroutine.wrap(function()
    local expanded = dap.listeners.on_config['dap.expand_variable'](config)
    dap.adapters[expanded.type](function(adapter)
      adapter.enrich_config(expanded, function(value) enriched = value end)
    end, expanded)
  end)()
  assert(enriched, 'native adapter must finish synchronous configuration enrichment')
  return enriched
end
local ok, err = xpcall(function()
  -- Keep expected paths canonical; the explicit alias below exercises symlinks.
  vim.fn.mkdir(fixture, 'p')
  fixture = assert(vim.uv.fs_realpath(fixture))
  write(fixture .. '/other/pytest.ini', {})
  write(fixture .. '/project/pyproject.toml', {})
  write(fixture .. '/project/test_case.py', test_lines)
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

  local defaults = require('dap').providers.configs['dap.global'](vim.api.nvim_get_current_buf())
  for index, python in ipairs(explicit_pythons) do
    assert(defaults[index].python == python and defaults[index].pythonPath == nil, vim.inspect(defaults[index]))
    local expected = type(python) == 'function' and python() or python
    local enriched = enrich(defaults[index])
    assert(vim.deep_equal(enriched.python, expected) and enriched.pythonPath == nil, vim.inspect(enriched))
  end

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

  for _, project_marker in ipairs { 'requirements.txt', 'pyproject.toml' } do
    for marker, runner in pairs { ['pytest.ini'] = 'pytest', ['manage.py'] = 'django' } do
      local project = fixture .. '/' .. runner .. '-' .. project_marker
      local interpreter = project .. (vim.fn.has 'win32' == 1 and '/.venv/Scripts/python.exe' or '/.venv/bin/python')
      write(project .. '/' .. project_marker, {})
      write(project .. '/tests/' .. marker, {})
      write(project .. '/tests/test_case.py', test_lines)
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
      assert(vim.fn.haslocaldir() == 1 and vim.fn.getcwd() == vim.uv.fs_realpath(fixture .. '/other'), 'nested test changed window directory scope')

      for _, config in ipairs(defaults) do
        if config.request == 'launch' and not config.python then
          assert(config.pythonPath() == interpreter, 'nested test config changed the default DAP interpreter')
        end
      end
      launches = require('dap').providers.configs['dap.launch.json'](vim.api.nvim_get_current_buf())
      assert(#launches == 4, 'nested test config hid the parent launch.json')
      for index, config in ipairs(launches) do
        assert(config.cwd == project, 'test root leaked into project launch directory')
        local enriched = enrich(config)
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
assert(ok, err)
io.stdout:write 'All native Python test-command checks passed.\n'
