-- DAP mappings. Shared setup is also used by language integrations that need
-- nvim-dap while their LSP client attaches.

local debug = require 'custom.lib.dap'

local function with_dap(callback)
  callback(debug.ensure_buffer())
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
  debug.ensure_buffer()
  require('dapui').toggle()
end, { desc = 'Debug: See last session result.' })
