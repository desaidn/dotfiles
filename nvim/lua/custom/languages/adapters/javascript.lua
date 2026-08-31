-- JavaScript and TypeScript share project routing and initialize js-debug only
-- when a buffer invokes the common debugging interface.

local dap = require 'custom.languages.dap'
local context = require 'custom.languages.context'
local languages = require 'custom.languages.config'

local filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' }
local launch_types = languages.dap_by_ft.javascript.launch_types
local prepare_launch = languages.dap_by_ft.javascript.prepare_launch

local did_setup = false

local function current_project()
  local project_config = languages.dap_by_ft[vim.bo.filetype]
  return project_config and context.for_buffer(nil, project_config.root_profile) or nil
end

local function current_program()
  local project = current_project()
  if project then return project.path end
  return require('dap').ABORT
end

local function current_root()
  local project = current_project()
  if project then return project.root end
  return require('dap').ABORT
end

local function ensure_js_debug()
  if did_setup then return end

  local executable = vim.fn.exepath 'js-debug-adapter'
  if executable == '' then error 'Mason js-debug-adapter is not installed or unavailable on PATH' end

  local debugger = require 'dap'
  local adapter = {
    type = 'server',
    host = '127.0.0.1',
    port = '${port}',
    executable = {
      command = executable,
      args = { '${port}', '127.0.0.1' },
    },
  }
  local function resolve_alias(resolve, config)
    prepare_launch(config)
    resolve(adapter)
  end
  for _, launch_type in ipairs(launch_types) do
    local normalized = prepare_launch { type = launch_type }
    debugger.adapters[launch_type] = normalized.type == launch_type and adapter or resolve_alias
  end

  debugger.configurations.javascript = debugger.configurations.javascript or {}
  debugger.configurations.javascript[#debugger.configurations.javascript + 1] = {
    type = 'pwa-node',
    request = 'launch',
    name = 'Launch current JavaScript file',
    program = current_program,
    cwd = current_root,
  }
  did_setup = true
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('javascript-dap-setup', { clear = true }),
  pattern = filetypes,
  callback = function(event) dap.register_buffer_setup(event.buf, ensure_js_debug) end,
})
