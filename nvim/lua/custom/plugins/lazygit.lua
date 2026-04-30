--- Toggleable lazygit in a fullscreen floating window.
--- <leader>g opens lazygit, <leader>g again hides it (preserving state).
--- Quitting lazygit (q) fully cleans up the buffer and window.
--- Requires: lazygit (https://github.com/jesseduffield/lazygit)
local state = { buf = nil, win = nil }

local function float_opts()
  return {
    relative = 'editor',
    width = vim.o.columns,
    height = vim.o.lines - 3,
    row = 1,
    col = 0,
    style = 'minimal',
    border = 'none',
  }
end

local function toggle_lazygit()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_hide(state.win)
    state.win = nil
    vim.g.lazygit_open = false
    return
  end

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    state.win = vim.api.nvim_open_win(state.buf, true, float_opts())
    vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = state.win })
    vim.g.lazygit_open = true
    vim.cmd.startinsert()
    return
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  state.win = vim.api.nvim_open_win(state.buf, true, float_opts())
  vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = state.win })
  vim.g.lazygit_open = true

  vim.fn.jobstart('lazygit', {
    term = true,
    on_exit = function()
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force = true }) end
      state.buf = nil
      state.win = nil
      vim.g.lazygit_open = false
    end,
  })

  vim.keymap.set('t', '<leader>gg', toggle_lazygit, { buffer = state.buf, desc = 'Toggle Lazygit' })
  vim.cmd.startinsert()
end

--- Redirect files opened by lazygit (via --remote-tab) into the main window.
--- The nvim-remote preset creates a partially-initialized buffer in a new tab.
--- We intercept it, clean up, and open the file fresh via :edit.
vim.api.nvim_create_autocmd('TabNewEntered', {
  callback = function()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    if name == '' then return end
    local stale = vim.api.nvim_get_current_buf()
    vim.cmd.tabclose()
    if vim.bo[stale].filetype == '' and vim.api.nvim_buf_is_valid(stale) then vim.api.nvim_buf_delete(stale, { force = true }) end
    vim.api.nvim_win_hide(state.win)
    state.win = nil
    vim.g.lazygit_open = false
    vim.cmd.edit(vim.fn.fnameescape(name))
  end,
})

return {
  'lazygit',
  virtual = true,
  keys = {
    { '<leader>gg', toggle_lazygit, desc = 'Lazygit' },
  },
}
