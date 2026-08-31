local gh = require('custom.lib.pack').gh
local terminal_tool = require 'custom.lib.terminal_tool'

vim.pack.add { gh 'willothy/flatten.nvim' }

local pending_handoff_win

local function alternate_window() return vim.fn.win_getid(vim.fn.winnr '#') end

local function set_window_buffer(win, buf)
  local ok, err = pcall(vim.api.nvim_win_set_buf, win, buf)
  if ok then return end

  -- Neovim may raise E325 after installing a swap-conflicted buffer. Accept
  -- only that completed postcondition so Flatten can finish its handoff.
  if type(err) == 'string' and err:find('Vim:E325:', 1, true) == 1 then
    local observed, current_buf = pcall(vim.api.nvim_win_get_buf, win)
    if observed and current_buf == buf then return end
  end

  error(err, 0)
end

local function take_handoff_window(data)
  local win = pending_handoff_win or terminal_tool.editor_handoff_window(data)
  pending_handoff_win = nil
  return win
end

local function open_in_host_window(opts)
  local target = opts.stdin_buf or opts.files[1]
  local win = take_handoff_window(opts.data) or alternate_window()
  set_window_buffer(win, target.bufnr)
  vim.api.nvim_set_current_win(win)
  return target.bufnr, win
end

local function open_diff_in_host_window(opts)
  local targets = {}
  for _, file in ipairs(opts.files) do
    targets[#targets + 1] = file
  end
  if opts.stdin_buf then table.insert(targets, 1, opts.stdin_buf) end

  local win = take_handoff_window(opts.data)
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd.tabnew()
    win = vim.api.nvim_get_current_win()
  end

  for index, target in ipairs(targets) do
    if index == 1 then
      set_window_buffer(win, target.bufnr)
    else
      win = vim.api.nvim_open_win(target.bufnr, true, { win = 0, vertical = true })
    end
    vim.cmd.diffthis()
  end
  return win, targets[#targets].bufnr
end

require('flatten').setup {
  window = {
    open = open_in_host_window,
    diff = open_diff_in_host_window,
  },
  hooks = {
    guest_data = terminal_tool.editor_handoff_data,
    pre_open = function(opts) pending_handoff_win = terminal_tool.editor_handoff_window(opts.data) end,
    post_open = function(opts) terminal_tool.complete_editor_handoff(opts.data) end,
  },
}
