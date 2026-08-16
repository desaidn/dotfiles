-- Python owns debugpy; the shared DAP module remains language-neutral.

local gh = require('custom.lib.pack').gh
local context = require 'custom.languages.context'
local dap = require 'custom.languages.dap'

vim.pack.add({ gh 'mfussenegger/nvim-dap-python' }, { load = function() end })

local did_setup = false
local root_profile = {
  markers = { 'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' },
}

local function is_windows() return vim.fn.has 'win32' == 1 end

local function python_in(environment)
  local directory = is_windows() and 'Scripts' or 'bin'
  local executable = is_windows() and 'python.exe' or 'python'
  local python = vim.fs.joinpath(environment, directory, executable)
  if vim.uv.fs_stat(python) and (is_windows() or vim.fn.executable(python) == 1) then return python end
end

local function conda_python(environment)
  local python = is_windows() and vim.fs.joinpath(environment, 'python.exe') or vim.fs.joinpath(environment, 'bin', 'python')
  if vim.uv.fs_stat(python) and (is_windows() or vim.fn.executable(python) == 1) then return python end
end

local function project_python(project)
  project = project or context.for_buffer(nil, root_profile)
  if not project then return vim.fn.exepath 'python3' end

  if vim.env.VIRTUAL_ENV and vim.fs.relpath(project.root, vim.env.VIRTUAL_ENV) then
    local python = python_in(vim.env.VIRTUAL_ENV)
    if python then return python end
  end
  if vim.env.CONDA_PREFIX and vim.fs.relpath(project.root, vim.env.CONDA_PREFIX) then
    local python = conda_python(vim.env.CONDA_PREFIX)
    if python then return python end
  end

  for _, directory in ipairs { '.venv', 'venv', '.env', 'env' } do
    local python = python_in(vim.fs.joinpath(project.root, directory))
    if python then return python end
  end
  return vim.fn.exepath 'python3'
end

local function debugpy_python()
  local root = require('mason-registry').get_package('debugpy'):get_install_path()
  local directory = is_windows() and 'Scripts' or 'bin'
  local executable = is_windows() and 'python.exe' or 'python'
  return vim.fs.joinpath(root, 'venv', directory, executable)
end

dap.register_project('python', {
  lsp_client = 'basedpyright',
  root_profile = root_profile,
  launch_types = { 'python' },
  prepare_launch = function(config, project)
    config.pythonPath = config.pythonPath or project_python(project)
    return config
  end,
})

local function ensure_debugpy()
  if did_setup then return end

  local ok, err = pcall(vim.cmd.packadd, 'nvim-dap-python')
  if not ok then error(('Unable to load nvim-dap-python: %s'):format(err)) end

  local dap_python = require 'dap-python'
  dap_python.setup(debugpy_python())
  -- nvim-dap evaluates configuration functions before nvim-dap-python
  -- enriches them, so this wins over unrelated active environments.
  for _, config in ipairs(require('dap').configurations.python or {}) do
    if config.request == 'launch' and not config.pythonPath then config.pythonPath = project_python end
  end
  dap_python.resolve_python = project_python
  did_setup = true
end

vim.api.nvim_create_user_command('DapPythonTestClass', function()
  ensure_debugpy()
  require('dap-python').test_class { config = { pythonPath = project_python } }
end, { desc = 'Debug Python test class' })

vim.api.nvim_create_user_command('DapPythonTestMethod', function()
  ensure_debugpy()
  require('dap-python').test_method { config = { pythonPath = project_python } }
end, { desc = 'Debug Python test method' })

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('python-dap-setup', { clear = true }),
  pattern = 'python',
  callback = function(event) require('custom.languages.dap').register_buffer_setup(event.buf, ensure_debugpy) end,
})
