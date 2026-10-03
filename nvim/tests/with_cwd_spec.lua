local script_path = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')
package.path = nvim_root .. '/lua/?.lua;' .. package.path
local with_cwd = require 'custom.lib.with_cwd'
local fixture = vim.fn.tempname()
for _, name in ipairs { 'global', 'tab', 'window', 'project' } do
  assert(vim.fn.mkdir(fixture .. '/' .. name, 'p') == 1)
end
fixture = assert(vim.uv.fs_realpath(fixture))
assert(vim.fn.writefile({}, fixture .. '/project/source.py') == 0)
assert(vim.uv.fs_symlink(fixture .. '/project', fixture .. '/project-alias', { dir = true }))
local previous = vim.fn.getcwd()
vim.o.swapfile = false
vim.api.nvim_buf_set_name(0, fixture .. '/project/source.py')

local function state()
  return {
    effective = vim.fn.getcwd(),
    global = vim.fn.getcwd(-1, -1),
    tab = vim.fn.getcwd(-1, 0),
    window_scope = vim.fn.haslocaldir(),
    tab_scope = vim.fn.haslocaldir(-1, 0),
  }
end

local ok, err = xpcall(function()
  for _, scope in ipairs { 'global', 'tab', 'window', 'both' } do
    vim.cmd.cd(fixture .. '/global')
    if scope == 'tab' or scope == 'both' then vim.cmd.tcd(fixture .. '/tab') end
    if scope == 'window' or scope == 'both' then vim.cmd.lcd(fixture .. '/window') end
    local before = state()
    local result = with_cwd(fixture .. '/project', function()
      assert(vim.fn.getcwd() == fixture .. '/project')
      assert(vim.fn.expand '%:.:r' == 'source', 'relative plugin paths must use the temporary directory')
      return 'result'
    end)
    assert(result == 'result')
    assert(vim.deep_equal(before, state()), vim.inspect { before = before, after = state() })
    local succeeded, failure = pcall(with_cwd, fixture .. '/project', function() error 'expected callback failure' end)
    assert(not succeeded and tostring(failure):find('expected callback failure', 1, true))
    assert(vim.deep_equal(before, state()), 'failed callback changed ' .. scope .. ' directory state')
    io.stdout:write('PASS preserves ', scope, ' directory scope and restores after failure\n')
  end
  with_cwd(fixture .. '/project-alias', function() assert(vim.fn.expand '%:.:r' == 'source', 'a directory alias must resolve the same physical project') end)
  io.stdout:write 'PASS resolves a symlinked project directory for relative paths\n'
end, debug.traceback)
vim.cmd.cd(previous)
vim.fs.rm(fixture, { recursive = true, force = true })
if not ok then error(err) end
io.stdout:write 'All temporary-directory checks passed.\n'
