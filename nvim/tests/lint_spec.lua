local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end

  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function create_file(path)
  assert(vim.fn.writefile({}, path) == 0, 'failed to create ' .. path)
end

local fixture = vim.fn.tempname()
assert(vim.fn.mkdir(fixture .. '/packages/assets/app/constants', 'p') == 1, 'failed to create fixture')
local package_root = fixture .. '/packages/assets'
local expected_package_root = assert(vim.uv.fs_realpath(package_root), 'failed to resolve fixture root')
local file_path = package_root .. '/app/constants/experiences.tsx'
local unconfigured_file = vim.fn.tempname() .. '.tsx'
create_file(fixture .. '/eslint.config.js')
create_file(package_root .. '/eslint.config.js')
create_file(file_path)
create_file(unconfigured_file)

local original_pack_add = vim.pack.add
local original_executable = vim.fn.executable
local original_lint = package.loaded.lint
local captured

local fake_lint = {
  linters_by_ft = {},
  try_lint = function(_, opts) captured = opts end,
}

vim.pack.add = function() end
vim.fn.executable = function(name) return name == 'eslint_d' and 1 or 0 end
package.loaded.lint = fake_lint

local setup_ok, setup_error = xpcall(function()
  dofile(nvim_root .. '/lua/kickstart/plugins/lint.lua')

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, file_path)
  vim.bo[bufnr].filetype = 'typescriptreact'
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = bufnr })

  check('passes the nearest ESLint config directory as linter cwd', function()
    assert(captured ~= nil, 'lint.try_lint was not called')
    assert(captured.cwd == expected_package_root, ('expected %s, got %s'):format(expected_package_root, tostring(captured.cwd)))
  end)

  local unconfigured_bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(unconfigured_bufnr, unconfigured_file)
  vim.bo[unconfigured_bufnr].filetype = 'typescriptreact'
  vim.api.nvim_set_current_buf(unconfigured_bufnr)
  captured = false
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = unconfigured_bufnr })

  check('falls back to nvim-lint cwd when no ESLint config exists', function()
    assert(captured ~= nil, 'lint.try_lint was not called')
    assert(captured.cwd == nil, 'expected no cwd override for an unconfigured buffer')
  end)
end, debug.traceback)

vim.pack.add = original_pack_add
vim.fn.executable = original_executable
package.loaded.lint = original_lint
vim.api.nvim_buf_delete(0, { force = true })
vim.fn.delete(fixture, 'rf')
vim.fn.delete(unconfigured_file)

if not setup_ok then
  failures[#failures + 1] = 'initializes the lint test fixture'
  io.stderr:write('FAIL initializes the lint test fixture\n  ', tostring(setup_error):gsub('\n', '\n  '), '\n')
end

if #failures > 0 then error(string.format('%d lint check(s) failed: %s', #failures, table.concat(failures, ', '))) end

io.stdout:write 'All lint checks passed.\n'
