-- Fast fuzzy file finder with frecency-based ranking and built-in memory.
-- Replaces Telescope for file finding and live grep. Telescope is kept for
-- help, diagnostics, LSP symbols, keymaps, buffers, and other pickers.

local gh = require('kickstart.pack').gh

vim.pack.add { gh 'dmtrKovalenko/fff.nvim' }

require('fff').setup {
  hl = {
    matched = 'Search',
    grep_match = 'Search',
  },
  grep = {
    modes = { 'fuzzy', 'plain', 'regex' },
  },
}

vim.keymap.set('n', '<leader>sf', function() require('fff').find_files() end, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>sg', function() require('fff').live_grep() end, { desc = '[S]earch by [G]rep' })
