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

local original_pack_add = vim.pack.add
local original_create_user_command = vim.api.nvim_create_user_command
local original_dap = package.loaded['custom.languages.dap']
local original_dap_core = package.loaded.dap
local original_dap_python = package.preload['dap-python']
local original_context = package.loaded['custom.languages.context']
local original_registry = package.loaded['mason-registry']
local original_virtual_env = vim.env.VIRTUAL_ENV
local original_conda_prefix = vim.env.CONDA_PREFIX
local original_has = vim.fn.has
local original_exepath = vim.fn.exepath
local captured
local buffer_setups = {}
local registered_project
local dap_python
local setup_calls = 0
local commands = {}
local test_actions = {}
local pack_root = vim.fn.tempname()
local original_packpath = vim.o.packpath
local project_root = pack_root .. '/project'
local unrelated_venv = pack_root .. '/unrelated-venv'
local debugpy_root = pack_root .. '/debugpy'
local fallback_root = pack_root .. '/fallback'
local conda_root = project_root .. '/conda'

vim.pack.add = function(spec) captured = spec end
vim.api.nvim_create_user_command = function(name, callback) commands[name] = callback end
package.loaded['custom.languages.dap'] = {
  register_buffer_setup = function(bufnr, setup) buffer_setups[bufnr] = setup end,
  register_project = function(filetype, config) registered_project = { filetype = filetype, config = config } end,
}
package.loaded.dap = { configurations = { python = { { request = 'launch' }, { request = 'attach' } } } }
package.preload['dap-python'] = function()
  dap_python = {
    setup = function(adapter, options)
      dap_python.adapter = adapter
      dap_python.options = options
      setup_calls = setup_calls + 1
    end,
    test_class = function(options) test_actions[#test_actions + 1] = { name = 'class', options = options } end,
    test_method = function(options) test_actions[#test_actions + 1] = { name = 'method', options = options } end,
  }
  return dap_python
end
package.loaded['custom.languages.context'] = {
  for_buffer = function() return { root = project_root, path = project_root .. '/src/main.py' } end,
}
package.loaded['mason-registry'] = {
  get_package = function(name)
    assert(name == 'debugpy')
    return { get_install_path = function() return debugpy_root end }
  end,
}
vim.fn.mkdir(pack_root .. '/pack/test/opt/nvim-dap-python', 'p')
vim.fn.mkdir(project_root .. '/.venv/bin', 'p')
vim.fn.mkdir(unrelated_venv .. '/bin', 'p')
vim.fn.mkdir(project_root .. '/active/bin', 'p')
vim.fn.mkdir(conda_root, 'p')
vim.fn.mkdir(debugpy_root .. '/venv/bin', 'p')
vim.fn.mkdir(fallback_root, 'p')
assert(vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, project_root .. '/.venv/bin/python') == 0)
assert(vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, unrelated_venv .. '/bin/python') == 0)
assert(vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, project_root .. '/active/bin/python') == 0)
assert(vim.fn.writefile({}, conda_root .. '/python.exe') == 0)
assert(vim.uv.fs_chmod(project_root .. '/.venv/bin/python', 493))
assert(vim.uv.fs_chmod(unrelated_venv .. '/bin/python', 493))
assert(vim.uv.fs_chmod(project_root .. '/active/bin/python', 493))
vim.o.packpath = pack_root .. ',' .. original_packpath

local ok, err = xpcall(function() dofile(nvim_root .. '/lua/custom/languages/adapters/python.lua') end, debug.traceback)
vim.pack.add = original_pack_add

check('registers Python DAP only for Python buffers and initializes Mason debugpy once', function()
  assert(ok, err)
  assert(captured and captured[1] == 'https://github.com/mfussenegger/nvim-dap-python', 'missing nvim-dap-python package')
  assert(registered_project.filetype == 'python')
  assert(registered_project.config.lsp_client == 'basedpyright')
  assert(vim.deep_equal(registered_project.config.launch_types, { 'python' }))

  local python = vim.api.nvim_create_buf(false, true)
  local rust = vim.api.nvim_create_buf(false, true)
  vim.bo[python].filetype = 'python'

  assert(type(buffer_setups[python]) == 'function', 'Python buffer did not register debugpy setup')
  assert(buffer_setups[rust] == nil, 'non-Python buffer registered debugpy setup')
  assert(setup_calls == 0, 'opening a Python buffer must not initialize debugpy')

  buffer_setups[python]()
  buffer_setups[python]()
  assert(setup_calls == 1, 'debugpy must initialize once for Python debug actions')
  assert(dap_python.adapter == debugpy_root .. '/venv/bin/python', dap_python.adapter)
  assert(dap_python.resolve_python() == project_root .. '/.venv/bin/python')
  assert(package.loaded.dap.configurations.python[1].pythonPath() == project_root .. '/.venv/bin/python')
  assert(registered_project.config.prepare_launch({}, { root = project_root }).pythonPath == project_root .. '/.venv/bin/python')

  vim.env.VIRTUAL_ENV = unrelated_venv
  assert(dap_python.resolve_python() == project_root .. '/.venv/bin/python', 'must reject an unrelated active environment')

  vim.env.VIRTUAL_ENV = project_root .. '/active'
  assert(dap_python.resolve_python() == project_root .. '/active/bin/python', 'must prefer an in-root active environment')
  assert(registered_project.config.prepare_launch({}, { root = project_root }).pythonPath == project_root .. '/active/bin/python')
  assert(registered_project.config.prepare_launch({ pythonPath = '/configured/python' }, { root = project_root }).pythonPath == '/configured/python')

  package.loaded['custom.languages.context'].for_buffer = function() return { root = fallback_root, path = fallback_root .. '/main.py' } end
  vim.fn.exepath = function(name)
    assert(name == 'python3')
    return '/mise/python3'
  end
  vim.env.VIRTUAL_ENV = nil
  assert(dap_python.resolve_python() == '/mise/python3')
end)

check('exposes Python test debugging through commands, not keymaps', function()
  assert(type(commands.DapPythonTestClass) == 'function')
  assert(type(commands.DapPythonTestMethod) == 'function')
  commands.DapPythonTestClass()
  commands.DapPythonTestMethod()
  assert(vim.deep_equal(vim.tbl_map(function(action) return action.name end, test_actions), { 'class', 'method' }), vim.inspect(test_actions))
  assert(test_actions[1].options.config.pythonPath() == '/mise/python3')
  assert(test_actions[2].options.config.pythonPath() == '/mise/python3')
end)

check('uses Windows virtualenv and Mason adapter paths when applicable', function()
  vim.fn.has = function(feature)
    if feature == 'win32' then return 1 end
    return original_has(feature)
  end
  package.loaded['dap-python'] = nil
  package.loaded['custom.languages.context'].for_buffer = function() return { root = project_root, path = project_root .. '/src/main.py' } end
  vim.env.VIRTUAL_ENV = nil
  vim.env.CONDA_PREFIX = conda_root
  dofile(nvim_root .. '/lua/custom/languages/adapters/python.lua')
  commands.DapPythonTestClass()
  assert(dap_python.adapter == debugpy_root .. '/venv/Scripts/python.exe', dap_python.adapter)
  assert(dap_python.resolve_python() == conda_root .. '/python.exe')
  vim.fn.has = original_has
end)

vim.o.packpath = original_packpath
vim.api.nvim_create_user_command = original_create_user_command
vim.fn.delete(pack_root, 'rf')
package.loaded['custom.languages.dap'] = original_dap
package.loaded.dap = original_dap_core
package.preload['dap-python'] = original_dap_python
package.loaded['custom.languages.context'] = original_context
package.loaded['mason-registry'] = original_registry
vim.env.VIRTUAL_ENV = original_virtual_env
vim.env.CONDA_PREFIX = original_conda_prefix
vim.fn.has = original_has
vim.fn.exepath = original_exepath
if #failures > 0 then error(string.format('%d Python configuration check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Python configuration checks passed.\n'
