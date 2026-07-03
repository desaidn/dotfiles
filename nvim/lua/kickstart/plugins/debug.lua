-- DAP (Debug Adapter Protocol) setup for Go and Python.
-- Can be extended to other languages — see https://github.com/mfussenegger/nvim-dap

local gh = require('kickstart.pack').gh

vim.pack.add({
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',
  gh 'mason-org/mason.nvim',
  gh 'jay-babu/mason-nvim-dap.nvim',
  gh 'leoluz/nvim-dap-go',
  gh 'mfussenegger/nvim-dap-python',
}, { load = function() end })

local did_setup = false

local function packadd(name)
  local ok, err = pcall(vim.cmd.packadd, name)
  if not ok then error(('Unable to load %s: %s'):format(name, err)) end
end

local function ensure_debug()
  if did_setup then return end

  -- Keep DAP off the normal startup path. Debug plugins are registered above,
  -- then loaded and configured the first time a debug key is used.
  for _, name in ipairs {
    'nvim-dap',
    'nvim-nio',
    'nvim-dap-ui',
    'mason.nvim',
    'mason-nvim-dap.nvim',
    'nvim-dap-go',
    'nvim-dap-python',
  } do
    packadd(name)
  end

  local dap = require 'dap'
  local dapui = require 'dapui'

  -- mason-nvim-dap auto-installs debug adapters. See mason-nvim-dap README for more.
  require('mason-nvim-dap').setup {
    -- Automatically set up debuggers with reasonable defaults
    automatic_installation = true,

    -- Custom handler overrides per adapter (see mason-nvim-dap README)
    handlers = {},

    ensure_installed = {
      'delve',
      'debugpy',
    },
  }

  -- Dap UI setup
  -- See `:help nvim-dap-ui`
  dapui.setup {
    -- Plain ASCII icons for maximum terminal compatibility
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

  -- Go debugger (delve)
  require('dap-go').setup {
    delve = {
      -- On Windows delve must be run attached or it crashes.
      -- See https://github.com/leoluz/nvim-dap-go/blob/main/README.md#configuring
      detached = vim.fn.has 'win32' == 0,
    },
  }

  -- Python debugger (debugpy via uv)
  require('dap-python').setup 'uv'

  did_setup = true
end

local function with_dap(callback)
  ensure_debug()
  callback(require 'dap')
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
  ensure_debug()
  require('dapui').toggle()
end, { desc = 'Debug: See last session result.' })
