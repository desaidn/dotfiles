-- Run the installed Lua language server with this config's actual Neovim settings.
local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')
package.path = nvim_root .. '/lua/?.lua;' .. nvim_root .. '/lua/?/init.lua;' .. package.path

local executable = vim.fn.exepath 'lua-language-server'
if executable == '' then executable = vim.fn.stdpath 'data' .. '/mason/bin/lua-language-server' end
assert(vim.fn.executable(executable) == 1, 'Install lua-language-server with :Mason before running diagnostics')

local server = require('custom.languages.adapters.lua').lsp_servers.lua_ls
local settings = vim.deepcopy(server.settings)
-- Select the Neovim workspace profile even when checking another checkout.
local client = {
  workspace_folders = { { name = vim.fn.stdpath 'config' } },
  config = { settings = settings },
}
-- The callback only reads these workspace/settings fields from a live client.
server.on_init(client --[[@as vim.lsp.Client]])

local temporary = vim.fn.tempname()
assert(vim.fn.mkdir(temporary, 'p') == 1)
local ok, err = xpcall(function()
  local config = temporary .. '/config.json'
  assert(vim.fn.writefile({ vim.json.encode(settings.Lua) }, config) == 0)
  local result = vim
    .system({
      executable,
      '--check=' .. nvim_root,
      '--checklevel=Hint',
      '--check_format=pretty',
      '--configpath=' .. config,
      '--logpath=' .. temporary .. '/log',
      '--metapath=' .. temporary .. '/meta',
    }, { text = true })
    :wait(60000)
  assert(result.code == 0, (result.stdout or '') .. (result.stderr or ''))
end, debug.traceback)
vim.fn.delete(temporary, 'rf')
assert(ok, err)
io.stdout:write 'All Neovim Lua files pass diagnostics through Hint severity.\n'
