-- Git gutter signs, inline blame, and hunk management keymaps.
-- See `:help gitsigns`

local gh = require('kickstart.pack').gh

vim.pack.add { gh 'lewis6991/gitsigns.nvim' }

require('gitsigns').setup {
  signs = {
    add = { text = '+' },
    change = { text = '~' },
    delete = { text = '_' },
    topdelete = { text = '‾' },
    changedelete = { text = '~' },
  },
  current_line_blame = true,
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = 'eol',
    delay = 200,
    ignore_whitespace = false,
  },
  on_attach = function(bufnr)
    local gitsigns = require 'gitsigns'

    local function map(mode, l, r, opts)
      opts = opts or {}
      opts.buf = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    -- Navigation
    map('n', ']c', function()
      if vim.wo.diff then
        vim.cmd.normal { ']c', bang = true }
      else
        gitsigns.nav_hunk 'next'
      end
    end, { desc = 'Jump to next git [c]hange' })

    map('n', '[c', function()
      if vim.wo.diff then
        vim.cmd.normal { '[c', bang = true }
      else
        gitsigns.nav_hunk 'prev'
      end
    end, { desc = 'Jump to previous git [c]hange' })

    -- Actions
    -- Visual mode
    map('v', '<leader>ga', function() gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' } end, { desc = 'git [a]dd hunk' })
    map('v', '<leader>gr', function() gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' } end, { desc = 'git [r]eset hunk' })
    -- Normal mode
    map('n', '<leader>ga', gitsigns.stage_hunk, { desc = 'git [a]dd hunk' })
    map('n', '<leader>gr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk' })
    map('n', '<leader>gu', gitsigns.undo_stage_hunk, { desc = 'git [u]ndo stage hunk' })
    map('n', '<leader>gp', gitsigns.preview_hunk, { desc = 'git [p]review hunk' })
    -- Toggles
    map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git [B]lame line' })
    map('n', '<leader>td', function()
      gitsigns.toggle_deleted()
      gitsigns.toggle_word_diff()
    end, { desc = '[T]oggle git inline [D]iff' })
  end,
}
