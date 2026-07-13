--- Lazygit launcher.
--- <leader>gg opens lazygit.
--- Requires: lazygit (https://github.com/jesseduffield/lazygit)
require('custom.lib.terminal_tool').create {
  id = 'lazygit',
  command = { 'lazygit' },
  key = '<leader>gg',
  desc = 'Lazygit',
  handoff = 'return-and-acknowledge',
}
