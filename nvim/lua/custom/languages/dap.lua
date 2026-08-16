-- Shared lazy DAP lifecycle and language-neutral debugger controls.

local gh = require('custom.lib.pack').gh
local context = require 'custom.languages.context'
local languages = require 'custom.languages.config'

vim.pack.add({
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',
}, { load = function() end })

local did_setup = false
local buffer_setups = {}
local M = {}

local function configuration_variables(project)
  local relative_file = vim.fs.relpath(project.root, project.path) or project.path
  return {
    ['${file}'] = project.path,
    ['${fileBasename}'] = vim.fs.basename(project.path),
    ['${fileBasenameNoExtension}'] = vim.fn.fnamemodify(vim.fs.basename(project.path), ':r'),
    ['${fileDirname}'] = vim.fs.dirname(project.path),
    ['${fileExtname}'] = vim.fn.fnamemodify(project.path, ':e'),
    ['${relativeFile}'] = relative_file,
    ['${relativeFileDirname}'] = vim.fs.dirname(relative_file),
    ['${fileDirnameBasename}'] = vim.fs.basename(vim.fs.dirname(project.path)),
    ['${workspaceFolder}'] = project.root,
    ['${workspaceFolderBasename}'] = vim.fs.basename(project.root),
  }
end

local function replace_configuration_variables(value, variables)
  if type(value) == 'string' then
    for placeholder, replacement in pairs(variables) do
      value = value:gsub(vim.pesc(placeholder), function() return replacement end)
    end
    return value
  end
  if type(value) ~= 'table' then return value end

  local replaced = {}
  for key, child in pairs(value) do
    replaced[replace_configuration_variables(key, variables)] = replace_configuration_variables(child, variables)
  end
  return setmetatable(replaced, getmetatable(value))
end

local function with_configuration_values(config, variables, root)
  -- nvim-dap represents launch configurations with `inputs` as callable tables.
  -- Preserve that deferred expansion while freezing this buffer's values.
  local transformed = replace_configuration_variables(vim.deepcopy(config), variables)
  transformed.cwd = transformed.cwd or root
  local metatable = getmetatable(config)
  if not metatable or type(metatable.__call) ~= 'function' then return transformed end

  local transformed_metatable = vim.deepcopy(metatable)
  transformed_metatable.__call = function(_, ...)
    local expanded = replace_configuration_variables(vim.deepcopy(config(...)), variables)
    expanded.cwd = expanded.cwd or root
    return expanded
  end
  return setmetatable(transformed, transformed_metatable)
end

local function project_root_from_client(bufnr, client_name)
  for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr, name = client_name }) do
    if client.config.root_dir then return vim.fs.normalize(client.config.root_dir) end
  end
end

local function dap_project(bufnr, dap_config)
  local project = context.for_buffer(bufnr, dap_config.root_profile)
  if not project then return nil end

  local lsp_root = project_root_from_client(bufnr, dap_config.lsp_client)
  if lsp_root and vim.fs.relpath(lsp_root, project.path) then project.root = lsp_root end
  return project
end

local function project_launch_configs(bufnr)
  if type(bufnr) ~= 'number' or not vim.api.nvim_buf_is_valid(bufnr) then return {} end

  local filetype = vim.bo[bufnr].filetype
  local dap_config = languages.dap_by_ft[filetype]
  if not dap_config then return {} end

  local project = dap_project(bufnr, dap_config)
  if not project then return {} end
  local launch_json = vim.fs.joinpath(project.root, '.vscode', 'launch.json')
  if not vim.uv.fs_stat(launch_json) then return {} end

  local ok, configs = pcall(require('dap.ext.vscode').getconfigs, launch_json)
  if not ok then
    vim.notify_once(("Can't get configurations from %s:\n%s"):format(launch_json, configs), vim.log.levels.WARN, { title = 'DAP' })
    return {}
  end

  local filtered = {}
  for _, config in ipairs(configs) do
    if vim.tbl_contains(dap_config.launch_types, config.type) then
      filtered[#filtered + 1] = with_configuration_values(config, configuration_variables(project), project.root)
    end
  end
  return filtered
end

local function packadd(name)
  local ok, err = pcall(vim.cmd.packadd, name)
  if not ok then error(('Unable to load %s: %s'):format(name, err)) end
end

function M.ensure()
  if did_setup then return require 'dap' end
  for _, name in ipairs { 'nvim-dap', 'nvim-nio', 'nvim-dap-ui' } do
    packadd(name)
  end

  local dap = require 'dap'
  local dapui = require 'dapui'
  dapui.setup { icons = { expanded = 'v', collapsed = '>', current_frame = '*' } }
  dap.listeners.after.event_initialized.dapui_config = dapui.open
  dap.listeners.before.event_terminated.dapui_config = dapui.close
  dap.listeners.before.event_exited.dapui_config = dapui.close
  dap.providers.configs['dap.launch.json'] = project_launch_configs
  did_setup = true
  return dap
end

function M.register_buffer_setup(bufnr, setup) buffer_setups[bufnr] = setup end

function M.register_project(filetype, config)
  assert(type(filetype) == 'string' and filetype ~= '', 'DAP project filetype is required')
  assert(type(config) == 'table', 'DAP project configuration is required')
  languages.dap_by_ft[filetype] = config
end

function M.ensure_buffer(bufnr)
  local dap = M.ensure()
  local setup = buffer_setups[bufnr or vim.api.nvim_get_current_buf()]
  if setup then setup() end
  return dap
end

local function with_dap(callback) callback(M.ensure_buffer()) end

-- Basic debugging keymaps
vim.keymap.set('n', '<F5>', function()
  with_dap(function(dap) dap.continue() end)
end, { desc = 'Debug: Start/Continue' })

vim.keymap.set('n', '<F1>', function()
  with_dap(function(dap) dap.step_into() end)
end, { desc = 'Debug: Step Into' })

vim.keymap.set('n', '<F2>', function()
  with_dap(function(dap) dap.step_over() end)
end, { desc = 'Debug: Step Over' })

vim.keymap.set('n', '<F3>', function()
  with_dap(function(dap) dap.step_out() end)
end, { desc = 'Debug: Step Out' })

vim.keymap.set('n', '<leader>b', function()
  with_dap(function(dap) dap.toggle_breakpoint() end)
end, { desc = 'Debug: Toggle Breakpoint' })

vim.keymap.set('n', '<leader>B', function()
  with_dap(function(dap) dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ') end)
end, { desc = 'Debug: Set Breakpoint' })

-- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
vim.keymap.set('n', '<F7>', function()
  M.ensure_buffer()
  require('dapui').toggle()
end, { desc = 'Debug: See last session result.' })

return M
