return {
  'willothy/flatten.nvim',
  lazy = false,
  priority = 1001,
  opts = {
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
        if source == 'hunk' then pcall(vim.cmd.HunkHide) end
        if source == 'lazygit' then pcall(vim.cmd, 'LazygitHide!') end
      end,
    },
  },
}
