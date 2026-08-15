-- Shared lazy DAP lifecycle and language-neutral debugger controls.

local gh = require('custom.lib.pack').gh

vim.pack.add({
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',
}, { load = function() end })

local did_setup = false
local buffer_setups = {}
local M = {}

local function packadd(name)
  local ok, err = pcall(vim.cmd.packadd, name)
  if not ok then error(('Unable to load %s: %s'):format(name, err)) end
end

function M.ensure()
  if did_setup then return require 'dap' end
  for _, name in ipairs { 'nvim-dap', 'nvim-nio', 'nvim-dap-ui' } do packadd(name) end

  local dap = require 'dap'
  local dapui = require 'dapui'
  dapui.setup { icons = { expanded = 'v', collapsed = '>', current_frame = '*' } }
  dap.listeners.after.event_initialized.dapui_config = dapui.open
  dap.listeners.before.event_terminated.dapui_config = dapui.close
  dap.listeners.before.event_exited.dapui_config = dapui.close
  did_setup = true
  return dap
end

function M.register_buffer_setup(bufnr, setup) buffer_setups[bufnr] = setup end

function M.ensure_buffer(bufnr)
  local dap = M.ensure()
  local setup = buffer_setups[bufnr or vim.api.nvim_get_current_buf()]
  if setup then setup() end
  return dap
end

local function with_dap(callback)
  callback(M.ensure_buffer())
end

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
