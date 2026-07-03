--- Hunk working-tree review launcher.
--- <leader>gd opens `hunk diff --watch --mode stack`.
--- Requires: hunk (https://github.com/modem-dev/hunk)
local hunk = require('custom.lib.terminal_tool').create {
  name = 'Hunk',
  source = 'hunk',
  command = { 'hunk', 'diff', '--watch', '--mode', 'stack' },
  key = '<leader>gd',
  desc = 'Hunk diff',
  terminal_key_desc = 'Toggle Hunk diff',
  hide_command = 'HunkHide',
}

vim.keymap.set('n', '<leader>gd', hunk.toggle, { desc = 'Hunk diff' })
