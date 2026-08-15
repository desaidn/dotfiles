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
local original_dap = package.loaded['custom.languages.dap']
local original_dap_python = package.preload['dap-python']
local captured
local buffer_setups = {}
local setup_calls = 0
local pack_root = vim.fn.tempname()
local original_packpath = vim.o.packpath

vim.pack.add = function(spec) captured = spec end
package.loaded['custom.languages.dap'] = {
  register_buffer_setup = function(bufnr, setup) buffer_setups[bufnr] = setup end,
}
package.preload['dap-python'] = function()
  return { setup = function(adapter) assert(adapter == 'uv'); setup_calls = setup_calls + 1 end }
end
vim.fn.mkdir(pack_root .. '/pack/test/opt/nvim-dap-python', 'p')
vim.o.packpath = pack_root .. ',' .. original_packpath

local ok, err = xpcall(function() dofile(nvim_root .. '/lua/custom/languages/adapters/python.lua') end, debug.traceback)
vim.pack.add = original_pack_add

check('registers debugpy only for Python buffers and initializes it once', function()
  assert(ok, err)
  assert(captured and captured[1] == 'https://github.com/mfussenegger/nvim-dap-python', 'missing nvim-dap-python package')

  local python = vim.api.nvim_create_buf(false, true)
  local rust = vim.api.nvim_create_buf(false, true)
  vim.bo[python].filetype = 'python'

  assert(type(buffer_setups[python]) == 'function', 'Python buffer did not register debugpy setup')
  assert(buffer_setups[rust] == nil, 'non-Python buffer registered debugpy setup')
  assert(setup_calls == 0, 'opening a Python buffer must not initialize debugpy')

  buffer_setups[python]()
  buffer_setups[python]()
  assert(setup_calls == 1, 'debugpy must initialize once for Python debug actions')
end)

vim.o.packpath = original_packpath
vim.fn.delete(pack_root, 'rf')
package.loaded['custom.languages.dap'] = original_dap
package.preload['dap-python'] = original_dap_python
if #failures > 0 then error(string.format('%d Python configuration check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Python configuration checks passed.\n'
