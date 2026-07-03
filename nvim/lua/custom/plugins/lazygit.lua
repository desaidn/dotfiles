--- Lazygit launcher.
--- <leader>gg opens lazygit.
--- Requires: lazygit (https://github.com/jesseduffield/lazygit)
local lazygit = require('custom.lib.terminal_tool').create {
  name = 'Lazygit',
  source = 'lazygit',
  command = { 'lazygit' },
  key = '<leader>gg',
  desc = 'Lazygit',
  terminal_key_desc = 'Toggle Lazygit',
  hide_command = 'LazygitHide',
  acknowledge_editor_return = true,
}

vim.keymap.set('n', '<leader>gg', lazygit.toggle, { desc = 'Lazygit' })
