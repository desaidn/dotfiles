-- Run production options with native buffers/windows, stopping before provisioning.
local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
vim.opt.runtimepath:prepend(root)
local function options()
  local environment = setmetatable({
    require = function(name)
      if name == 'custom.lib.pack' then error 'options loaded' end
      return require(name)
    end,
  }, { __index = _G })
  local ok, err = pcall(setfenv(assert(loadfile(root .. '/init.lua')), environment))
  assert(not ok and tostring(err):find('options loaded', 1, true), err)
end

vim.env.DISPLAY, vim.env.WAYLAND_DISPLAY = nil, nil
vim.env.SSH_TTY, vim.env.TMUX = '/dev/audit', '/tmp/audit,1,0'
options()
assert(vim.g.clipboard == 'tmux', 'remote tmux must override native macOS pasteboard detection')
vim.env.TMUX = nil
options()
assert(vim.g.clipboard.name == 'osc52-copy')
vim.env.SSH_TTY = nil
vim.g.clipboard = nil
options()
assert(vim.g.clipboard == nil, 'local sessions should retain native clipboard detection')

local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(scratch)
assert(not vim.wo.number and not vim.wo.relativenumber)
local file = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(file)
assert(vim.wo.number and vim.wo.relativenumber, 'ordinary file must restore line numbers after a scratch buffer')

vim.cmd 'setlocal nonumber signcolumn=no'
local original_window = vim.api.nvim_get_current_win()
vim.cmd 'vsplit'
vim.api.nvim_set_current_win(original_window)
assert(not vim.wo.number, 'returning to a file must preserve its local line-number setting')
assert(vim.wo.signcolumn == 'no', 'returning to a file must preserve its local sign-column setting')
io.stdout:write 'All native editor option checks passed.\n'
