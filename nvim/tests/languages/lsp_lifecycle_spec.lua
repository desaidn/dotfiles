local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local root = vim.fs.normalize(vim.fs.dirname(script) .. '/../..')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
local function ignore_packages() end
vim.pack.add = ignore_packages
package.loaded.mason = { setup = function() end }
package.loaded.fidget = { setup = function() end }
package.loaded['mason-tool-installer'] = { setup = function() end }
package.loaded['blink.cmp'] = { get_lsp_capabilities = function() return {} end }
local function ignore_servers() end
vim.lsp.enable = ignore_servers
require 'custom.languages.lsp'

local buf = vim.api.nvim_get_current_buf()
local get_clients = vim.lsp.get_clients
local clients = {
  [101] = { id = 101, supports_method = function(_, method) return method == 'textDocument/documentHighlight' end },
  [202] = { id = 202, supports_method = function() return false end },
  [303] = { id = 303, supports_method = function(_, method) return method == 'textDocument/documentHighlight' end },
}
local function client_by_id(id) return clients[id] end
local function attached_clients() return vim.tbl_values(clients) end
vim.lsp.get_client_by_id = client_by_id
vim.lsp.get_clients = attached_clients
local function event(name, id) vim.api.nvim_exec_autocmds(name, { buffer = buf, data = { client_id = id } }) end
local function count() return #vim.api.nvim_get_autocmds { group = 'kickstart-lsp-highlight', buffer = buf } end
event('LspAttach', 101)
local initial = count()
assert(initial > 0)
event('LspAttach', 303)
assert(count() == initial, 'multiple clients duplicated highlight callbacks')
event('LspDetach', 202)
assert(count() == initial, 'unrelated detach removed highlighting')
clients[202] = nil
event('LspDetach', 303)
assert(count() == initial, 'another supporting client remains attached')
clients[303] = nil
event('LspDetach', 101)
assert(count() == 0, 'last supporting client should remove highlighting')
vim.lsp.get_clients = get_clients
io.stdout:write 'All LSP highlight lifecycle checks passed.\n'
