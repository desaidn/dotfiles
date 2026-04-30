-- Fast fuzzy file finder with frecency-based ranking and built-in memory.
-- Replaces Telescope for file finding and live grep. Telescope is kept for
-- help, diagnostics, LSP symbols, keymaps, buffers, and other pickers.
return {
  'dmtrKovalenko/fff.nvim',
  lazy = false,
  build = function() require('fff.download').download_or_build_binary() end,
  opts = {
    grep = {
      modes = { 'fuzzy', 'plain', 'regex' },
    },
  },
  keys = {
    { '<leader>sf', function() require('fff').find_files() end, desc = '[S]earch [F]iles' },
    { '<leader>sg', function() require('fff').live_grep() end, desc = '[S]earch by [G]rep' },
  },
}
