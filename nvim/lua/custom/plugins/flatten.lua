local gh = require('custom.lib.pack').gh
local terminal_tool = require 'custom.lib.terminal_tool'

vim.pack.add { gh 'willothy/flatten.nvim' }

require('flatten').setup {
  window = {
    open = 'alternate',
  },
  hooks = {
    guest_data = terminal_tool.editor_handoff_data,
    post_open = function(opts) terminal_tool.complete_editor_handoff(opts.data) end,
  },
}
