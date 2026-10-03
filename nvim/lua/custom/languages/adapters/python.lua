-- Python owns debugpy; the shared DAP module remains language-neutral.

local context = require 'custom.languages.context'

local did_setup = false
local root_profile = {
  markers = { 'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git' },
}
local test_root_profile = {
  -- Equal priority makes the nearest test or project marker determine test cwd.
  markers = { { 'pyrightconfig.json', 'pyproject.toml', 'setup.py', 'setup.cfg', 'pytest.ini', 'manage.py', 'requirements.txt', 'Pipfile', '.git' } },
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

local function environment_file(path, root)
  path = vim.fs.normalize(path)
  if path:sub(1, 1) == '/' or path:match '^%a:/' then return path end
  return vim.fs.normalize(vim.fs.joinpath(root, path))
end

local function prepare_launch(config, project)
  if not config.pythonPath and not config.python then config.pythonPath = project_python(project) end
  local env_file = config.envFile or '.env'
  if type(env_file) ~= 'string' or env_file:find('${', 1, true) then
    -- Resolve native DAP inputs/environment variables before classifying a path
    -- as relative; the project root was captured before configuration selection.
    config.envFile = function()
      local dap = require 'dap'
      local expanded = dap.listeners.on_config['dap.expand_variable'] { envFile = env_file }
      if expanded.envFile == dap.ABORT then return dap.ABORT end
      return environment_file(expanded.envFile or '.env', project.root)
    end
  else
    config.envFile = environment_file(env_file, project.root)
  end
  return config
end

local function ensure_debugpy()
  if did_setup then return end

  local ok, err = pcall(vim.cmd.packadd, 'nvim-dap-python')
  if not ok then error(('Unable to load nvim-dap-python: %s'):format(err)) end

  local dap_python = require 'dap-python'
  dap_python.setup(debugpy_python())
  local dap = require 'dap'
  local shared = require 'custom.languages.dap'
  local global_configs = dap.providers.configs['dap.global']
  dap.providers.configs['dap.global'] = function(bufnr)
    local configs = global_configs(bufnr)
    if vim.bo[bufnr].filetype ~= 'python' then return configs end
    local project = shared.project(bufnr)
    if not project then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path == '' or vim.bo[bufnr].buftype ~= '' then return configs end
      project = { root = vim.fs.dirname(path), path = path }
    end
    -- Providers receive the source buffer before an asynchronous picker can
    -- change it. Copy defaults so future runs still resolve their own project.
    return vim.tbl_map(function(config)
      if config.type ~= 'python' and config.type ~= 'debugpy' then return config end
      return shared.prepare_config(config, project, prepare_launch)
    end, configs)
  end
  dap_python.resolve_python = project_python
  did_setup = true
end

local function project_test_runner(root)
  if vim.uv.fs_stat(root .. '/pytest.ini') then return 'pytest' end
  if vim.uv.fs_stat(root .. '/manage.py') then return 'django' end
  local pyproject = root .. '/pyproject.toml'
  if vim.fn.filereadable(pyproject) == 1 then
    for _, line in ipairs(vim.fn.readfile(pyproject)) do
      if line:find '%[tool.pytest' then return 'pytest' end
    end
  end
  return 'unittest'
end

local function debug_test(action)
  require('custom.languages.dap').ensure()
  ensure_debugpy()
  local environment_project = context.for_buffer(nil, root_profile)
  local project = context.for_buffer(nil, test_root_profile)
  if not project then
    local path = vim.api.nvim_buf_get_name(0)
    if path == '' or vim.bo.buftype ~= '' then return end
    project = { root = vim.fs.dirname(path), path = path }
  end
  local dap_python = require 'dap-python'
  -- A nested test config changes the runner's cwd, not the project environment.
  local python = project_python(environment_project or project)
  -- The plugin builds unittest/Django module names relative to process cwd.
  -- Freeze launch values before returning to the editor's directory.
  require 'custom.lib.with_cwd'(project.root, function()
    local runner = dap_python.test_runner or project_test_runner(project.root)
    if type(runner) == 'function' then runner = runner() end
    dap_python[action] {
      test_runner = runner,
      config = function(config)
        config.cwd, config.pythonPath = project.root, python
        config = prepare_launch(config, project)
        if runner == 'unittest' or runner == 'django' then
          -- expand('%:.') can retain an absolute symlink spelling after chdir.
          local relative = assert(vim.fs.relpath(project.root, project.path))
          local target = vim.fn.fnamemodify(relative, ':r'):gsub('[/\\]', '.')
          local original = vim.fn.expand('%:.:r'):gsub('[/\\]', '.')
          local suffix = config.name == '' and '' or '.' .. config.name
          for index, argument in ipairs(config.args) do
            if argument == original .. suffix then config.args[index] = target .. suffix end
          end
        end
        return config
      end,
    }
  end)
end

-- BasedPyright provides semantic hover while Ruff diagnostics/actions remain.
local function disable_ruff_overlap(client)
  client.server_capabilities.hoverProvider = false
  require('custom.languages.capabilities').disable_formatting(client)
end

local M = {
  lsp_servers = {
    basedpyright = {
      -- Neovim 0.12 pull diagnostics expose every edit as work progress.
      -- Push workspace diagnostics retain cross-file feedback and startup status.
      init_options = { disablePullDiagnostics = true },
      settings = {
        basedpyright = {
          analysis = { diagnosticMode = 'workspace' },
          disableOrganizeImports = true,
        },
      },
    },
    ruff = { on_attach = disable_ruff_overlap },
  },
  mason_tools = { 'basedpyright', 'ruff', 'debugpy' },
  treesitter_parsers = { 'python' },
  formatters_by_ft = { python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' } },
  dap_by_ft = {
    python = {
      lsp_client = 'basedpyright',
      root_profile = root_profile,
      launch_types = { 'python', 'debugpy' },
      prepare_launch = prepare_launch,
    },
  },
}

function M.setup()
  local gh = require('custom.lib.pack').gh
  vim.pack.add({ gh 'mfussenegger/nvim-dap-python' }, { load = function() end })

  vim.api.nvim_create_user_command('DapPythonTestClass', function() debug_test 'test_class' end, { desc = 'Debug Python test class' })

  vim.api.nvim_create_user_command('DapPythonTestMethod', function() debug_test 'test_method' end, { desc = 'Debug Python test method' })

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('python-dap-setup', { clear = true }),
    pattern = 'python',
    callback = function(event) require('custom.languages.dap').register_buffer_setup(event.buf, ensure_debugpy) end,
  })
end

return M
