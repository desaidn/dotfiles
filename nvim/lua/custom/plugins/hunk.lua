--- Hunk stacked review launcher.
--- Both inputs share one Tool Tab and one process per working directory, so
--- exactly one Hunk session matches each repository. This keeps the `--repo .`
--- selector in `hunk session comment add` usable for agent review notes while
--- allowing concurrent reviews in different repositories or worktrees.
--- Requires: hunk (https://github.com/modem-dev/hunk)
local review_base_oid = vim.env.DEVFLOW_REVIEW_BASE_OID
local review_head_oid = vim.env.DEVFLOW_REVIEW_HEAD_OID

local function valid_review_oid(value) return type(value) == 'string' and (#value == 40 or #value == 64) and value:match '^[0-9a-f]+$' ~= nil end

local review_context_present = review_base_oid ~= nil or review_head_oid ~= nil
if review_context_present and (not valid_review_oid(review_base_oid) or not valid_review_oid(review_head_oid) or #review_base_oid ~= #review_head_oid) then
  error('invalid DEVFLOW review context: base and head must be same-length full lowercase hexadecimal object IDs', 0)
end

local working_tree_variant = {
  command = { 'hunk', 'diff', '--watch', '--mode', 'stack' },
  key = '<leader>gd',
  desc = 'Hunk diff',
}

if review_context_present then
  working_tree_variant.command = { 'hunk', 'diff', review_base_oid .. '...' .. review_head_oid, '--watch', '--mode', 'stack' }
  working_tree_variant.ex_command = 'HunkReview'
end

require('custom.lib.terminal_tool').create {
  id = 'hunk',
  -- Hunk's OpenTUI otherwise mistakes the inherited outer tmux for its
  -- immediate terminal and sends graphics probes through Neovim's terminal.
  env = { OPENTUI_GRAPHICS = 'false' },
  variants = {
    working_tree_variant,
    {
      command = { 'hunk', 'diff', '--staged', '--watch', '--mode', 'stack' },
      key = '<leader>gD',
      desc = 'Hunk diff (staged)',
    },
  },
  instances = 'cwd',
}
