-- Shared lazy DAP setup. Language integrations call ensure() before asking
-- nvim-dap to create configurations, while the normal editor path stays lazy.

local gh = require('custom.lib.pack').gh

vim.pack.add({
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',
  gh 'mfussenegger/nvim-dap-python',
}, { load = function() end })

local did_setup = false
local M = {}

local function packadd(name)
  local ok, err = pcall(vim.cmd.packadd, name)
  if not ok then error(('Unable to load %s: %s'):format(name, err)) end
end

function M.ensure()
  if did_setup then return require 'dap' end

  -- Keep DAP off the normal startup path. Debug plugins are registered above,
  -- then loaded and configured by the first debugger action or language server.
  for _, name in ipairs {
    'nvim-dap',
    'nvim-nio',
    'nvim-dap-ui',
    'nvim-dap-python',
  } do
    packadd(name)
  end

  local dap = require 'dap'
  local dapui = require 'dapui'

  dapui.setup {
    icons = { expanded = 'v', collapsed = '>', current_frame = '*' },
    controls = {
      icons = {
        pause = '||',
        play = '>',
        step_into = 'v>',
        step_over = '>>',
        step_out = '<<',
        step_back = '<',
        run_last = '>!',
        terminate = 'x',
        disconnect = '~',
      },
    },
  }

  dap.listeners.after.event_initialized['dapui_config'] = dapui.open
  dap.listeners.before.event_terminated['dapui_config'] = dapui.close
  dap.listeners.before.event_exited['dapui_config'] = dapui.close

  -- Python debugger (debugpy via uv).
  require('dap-python').setup 'uv'

  did_setup = true
  return dap
end

return M
