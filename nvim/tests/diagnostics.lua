-- Check Neovim configuration and repository test Lua with their workspace settings.
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
  for index, workspace in ipairs {
    { root = nvim_root, config = config },
    -- Let LuaLS load tests/.luarc.json, just as it does when editing the harness.
    { root = vim.fs.dirname(nvim_root) .. '/tests' },
  } do
    local command = {
      executable,
      '--check=' .. workspace.root,
      '--checklevel=Hint',
      '--check_format=pretty',
      '--logpath=' .. temporary .. '/log-' .. index,
      '--metapath=' .. temporary .. '/meta-' .. index,
    }
    if workspace.config then command[#command + 1] = '--configpath=' .. workspace.config end
    local result = vim.system(command, { cwd = workspace.root, text = true }):wait(60000)
    assert(result.code == 0, workspace.root .. '\n' .. (result.stdout or '') .. (result.stderr or ''))
  end
end, debug.traceback)
vim.fn.delete(temporary, 'rf')
assert(ok, err)
io.stdout:write 'All Neovim and repository test Lua files pass diagnostics through Hint severity.\n'
