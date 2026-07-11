vim.o.mouse = 'a'
vim.g.mapleader = ' '

local fixture = assert(vim.env.HUNK_RENDER_FIXTURE, 'HUNK_RENDER_FIXTURE is required')
local repo_root = assert(vim.env.DOTFILES_REPO_ROOT, 'DOTFILES_REPO_ROOT is required')
vim.cmd.cd(vim.fn.fnameescape(fixture))
vim.opt.runtimepath:prepend(repo_root .. '/nvim')
package.path = table.concat({
  repo_root .. '/nvim/lua/?.lua',
  repo_root .. '/nvim/lua/?/init.lua',
  package.path,
}, ';')

vim.defer_fn(function()
  require 'custom.plugins.hunk'
  vim.api.nvim_feedkeys(' gd', 'm', false)
end, 100)
