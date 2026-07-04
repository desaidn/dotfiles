local gh = require('custom.lib.pack').gh

vim.pack.add { gh 'willothy/flatten.nvim' }

require('flatten').setup {
  window = {
    open = 'alternate',
  },
  hooks = {
    guest_data = function()
      return {
        editor_handoff_source = vim.env.DOTFILES_EDITOR_HANDOFF_SOURCE,
      }
    end,
    post_open = function(opts)
      local source = opts.data and opts.data.editor_handoff_source
      if source == 'hunk' then pcall(function() vim.cmd.HunkHide() end) end
      if source == 'lazygit' then pcall(function() vim.cmd 'LazygitHide!' end) end
    end,
  },
}
