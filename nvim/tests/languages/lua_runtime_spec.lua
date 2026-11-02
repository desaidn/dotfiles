-- Exercise the real rootless Lua client, without normal startup provisioning.
local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/../..')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/site/pack/core/opt/nvim-lspconfig')

local executable = vim.fn.stdpath 'data' .. '/mason/bin/lua-language-server'
assert(vim.fn.executable(executable) == 1, 'Install lua-language-server with :Mason before running this check')
local fixture = vim.fn.tempname()
assert(vim.fn.mkdir(fixture, 'p') == 1)
local path = fixture .. '/standalone.lua'
assert(vim.fn.writefile({ 'print(vim.api)' }, path) == 0)
local client
local ok, err = xpcall(function()
  vim.lsp.config(
    'lua_ls',
    vim.tbl_deep_extend('force', require('custom.languages.adapters.lua').lsp_servers.lua_ls, {
      cmd = { executable, '--logpath=' .. fixture .. '/log', '--metapath=' .. fixture .. '/meta' },
    })
  )
  vim.lsp.enable 'lua_ls'
  vim.cmd.edit(path)
  vim.bo.filetype = 'lua'
  local buf = vim.api.nvim_get_current_buf()
  assert(
    vim.wait(10000, function()
      client = vim.lsp.get_clients({ bufnr = buf, name = 'lua_ls' })[1]
      return client ~= nil and client.initialized == true
    end),
    'standalone Lua client did not initialize'
  )
  assert(client and client.workspace_folders == nil, 'fixture unexpectedly has a workspace root')
  local settings = client.config.settings.Lua
  assert(settings.runtime == nil, 'standalone Lua received Neovim runtime settings: ' .. vim.inspect(settings.runtime))
  assert(not settings.diagnostics or settings.diagnostics.globals == nil, 'standalone Lua received Neovim globals')
  assert(not settings.workspace or settings.workspace.library == nil, 'standalone Lua received Neovim libraries')
end, debug.traceback)

vim.lsp.enable('lua_ls', false)
if client then
  client:stop(true)
  assert(vim.wait(5000, function() return client:is_stopped() end), 'Lua client did not stop')
end
vim.cmd.bwipeout { bang = true }
vim.fn.delete(fixture, 'rf')
assert(ok, err)
io.stdout:write 'Standalone Lua retains native language-server settings.\n'
