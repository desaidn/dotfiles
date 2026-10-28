--- Hunk stacked review launcher.
--- All inputs share one Tool Tab and one process per Git checkout, so
--- exactly one Hunk session matches each repository. This keeps the `--repo .`
--- selector in `hunk session comment add` usable for agent review notes while
--- allowing concurrent reviews in different repositories or worktrees.
--- Requires: hunk (https://github.com/modem-dev/hunk)
local function valid_review_oid(value) return type(value) == 'string' and (#value == 40 or #value == 64) and value:match '^[0-9a-f]+$' ~= nil end

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
    {
      command = function(args)
        local base, head = args[1], args[2]
        if #args ~= 2 or not valid_review_oid(base) or not valid_review_oid(head) or #base ~= #head then
          error('HunkReview requires base and head as two same-length full lowercase hexadecimal commit IDs', 0)
        end
        return { 'hunk', 'diff', base .. '...' .. head, '--watch', '--mode', 'stack' }
      end,
      ex_command = 'HunkReview',
      desc = 'Hunk exact revision review',
    },
  },
  instances = 'repo',
}
