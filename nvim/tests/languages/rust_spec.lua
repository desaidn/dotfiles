local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')

package.path = table.concat({ nvim_root .. '/lua/?.lua', nvim_root .. '/lua/?/init.lua', package.path }, ';')

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end
  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local original_pack_add = vim.pack.add
local original_config = vim.g.rustaceanvim
local original_dap = package.loaded['custom.languages.dap']
local captured
vim.pack.add = function(spec) captured = spec end

local ok, err = xpcall(function() dofile(nvim_root .. '/lua/custom/languages/adapters/rust.lua') end, debug.traceback)
vim.pack.add = original_pack_add

check('loads rustaceanvim v9 before Rust buffers attach', function()
  assert(ok, err)
  assert(captured and captured[1].src == 'https://github.com/mrcjkb/rustaceanvim', 'missing rustaceanvim package')
  assert(vim.g.rustaceanvim.server.default_settings['rust-analyzer'].cargo.features ~= 'all', 'Rust must not enable all Cargo features globally')
  assert(vim.g.rustaceanvim.server.default_settings['rust-analyzer'].check.command == 'clippy', 'Rust diagnostics must use Clippy')
end)

check('loads DAP before rustaceanvim creates CodeLLDB configurations', function()
  local ensured = false
  package.loaded['custom.languages.dap'] = { ensure = function() ensured = true end }
  vim.g.rustaceanvim.server.on_attach(nil, 0)
  assert(ensured, 'Rust on_attach did not initialize the shared DAP stack')
end)

check('does not claim Rust-only keymaps over the common language interface', function()
  vim.g.rustaceanvim.server.on_attach(nil, 0)
  local forbidden = {
    (vim.g.mapleader or '\\') .. 'rr',
    (vim.g.mapleader or '\\') .. 'rt',
    (vim.g.mapleader or '\\') .. 'rd',
    (vim.g.mapleader or '\\') .. 'rm',
    'K',
  }
  local mappings = vim.api.nvim_buf_get_keymap(0, 'n')
  for _, lhs in ipairs(forbidden) do
    assert(not vim.tbl_contains(vim.tbl_map(function(map) return map.lhs end, mappings), lhs), ('Rust must not claim %s'):format(lhs))
  end
end)

vim.g.rustaceanvim = original_config
package.loaded['custom.languages.dap'] = original_dap
if #failures > 0 then error(string.format('%d Rust configuration check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Rust configuration checks passed.\n'
