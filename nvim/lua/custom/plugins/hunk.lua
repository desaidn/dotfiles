--- Hunk stacked review launcher.
--- Both inputs share one Tool Tab and one process so exactly one Hunk session
--- matches the repository, which is what keeps the `--repo .` selector in
--- `hunk session comment add` usable for agent review notes.
--- Requires: hunk (https://github.com/modem-dev/hunk)
require('custom.lib.terminal_tool').create {
  id = 'hunk',
  -- Hunk's OpenTUI otherwise mistakes the inherited outer tmux for its
  -- immediate terminal and sends graphics probes through Neovim's terminal.
  env = { OPENTUI_GRAPHICS = 'false' },
  variants = {
    {
      command = { 'hunk', 'diff', '--watch', '--mode', 'stack' },
      key = '<leader>gd',
      desc = 'Hunk diff',
    },
    {
      command = { 'hunk', 'diff', '--staged', '--watch', '--mode', 'stack' },
      key = '<leader>gD',
      desc = 'Hunk diff (staged)',
    },
  },
}
