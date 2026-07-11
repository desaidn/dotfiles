--- Hunk working-tree review launcher.
--- <leader>gd opens `hunk diff --watch --mode stack`.
--- Requires: hunk (https://github.com/modem-dev/hunk)
local hunk = require('custom.lib.terminal_tool').create {
  name = 'Hunk',
  source = 'hunk',
  command = { 'hunk', 'diff', '--watch', '--mode', 'stack' },
  -- Hunk's OpenTUI otherwise mistakes the inherited outer tmux for its
  -- immediate terminal and sends graphics probes through Neovim's terminal.
  env = { OPENTUI_GRAPHICS = 'false' },
  key = '<leader>gd',
  desc = 'Hunk diff',
  terminal_key_desc = 'Toggle Hunk diff',
  hide_command = 'HunkHide',
}

vim.keymap.set('n', '<leader>gd', hunk.toggle, { desc = 'Hunk diff' })
