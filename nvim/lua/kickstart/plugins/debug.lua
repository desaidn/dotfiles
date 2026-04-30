-- DAP (Debug Adapter Protocol) setup for Go and Python.
-- Can be extended to other languages — see https://github.com/mfussenegger/nvim-dap

return {
  'mfussenegger/nvim-dap',
  dependencies = {
    -- Creates a beautiful debugger UI
    'rcarriga/nvim-dap-ui',

    -- Required dependency for nvim-dap-ui
    'nvim-neotest/nvim-nio',

    -- Installs the debug adapters for you
    'mason-org/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',

    -- Add your own debuggers here
    'leoluz/nvim-dap-go',
    'mfussenegger/nvim-dap-python',
  },
  keys = {
    -- Basic debugging keymaps
    { '<F5>', function() require('dap').continue() end, desc = 'Debug: Start/Continue' },
    { '<F1>', function() require('dap').step_into() end, desc = 'Debug: Step Into' },
    { '<F2>', function() require('dap').step_over() end, desc = 'Debug: Step Over' },
    { '<F3>', function() require('dap').step_out() end, desc = 'Debug: Step Out' },
    { '<leader>b', function() require('dap').toggle_breakpoint() end, desc = 'Debug: Toggle Breakpoint' },
    { '<leader>B', function() require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, desc = 'Debug: Set Breakpoint' },
    -- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
    { '<F7>', function() require('dapui').toggle() end, desc = 'Debug: See last session result.' },
  },
  config = function()
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
  end,
}
