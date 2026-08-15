local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')

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
local captured
vim.pack.add = function(spec) captured = spec end
package.loaded['custom.lib.dap'] = nil
local dap = assert(loadfile(nvim_root .. '/lua/custom/lib/dap.lua'))()
vim.pack.add = original_pack_add

check('keeps the shared DAP loader language-neutral', function()
  local sources = vim.tbl_map(function(item) return item.src end, captured)
  assert(not vim.tbl_contains(sources, 'https://github.com/mfussenegger/nvim-dap-python'), 'shared DAP loader must not own Python debugpy')
  assert(type(dap.register_buffer_setup) == 'function', 'shared DAP loader must support buffer-specific debugger setup')
end)

if #failures > 0 then error(string.format('%d DAP configuration check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All DAP configuration checks passed.\n'
