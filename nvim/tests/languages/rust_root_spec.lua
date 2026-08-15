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

local fixture = vim.fn.tempname()
assert(vim.fn.mkdir(fixture .. '/workspace/member/src', 'p') == 1, 'failed to create Cargo workspace fixture')
assert(vim.fn.mkdir(fixture .. '/standalone/src', 'p') == 1, 'failed to create standalone Cargo fixture')
assert(vim.fn.writefile({ '[workspace]' }, fixture .. '/workspace/Cargo.toml') == 0, 'failed to create workspace manifest')
assert(vim.fn.writefile({}, fixture .. '/workspace/member/Cargo.toml') == 0, 'failed to create member manifest')
assert(vim.fn.writefile({}, fixture .. '/workspace/member/src/main.rs') == 0, 'failed to create Rust source')
assert(vim.fn.writefile({}, fixture .. '/standalone/Cargo.toml') == 0, 'failed to create standalone manifest')
assert(vim.fn.writefile({}, fixture .. '/standalone/src/main.rs') == 0, 'failed to create standalone Rust source')

local buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buffer, fixture .. '/workspace/member/src/main.rs')
local workspace_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.api.nvim_buf_get_name(buffer))))
local languages = require 'custom.languages.config'
local context = require 'custom.languages.context'

check('finds a Cargo workspace root without starting a blocking Cargo process', function()
  local project = context.for_buffer(buffer, languages.dap_by_ft.rust.root_profile)
  assert(project.root == workspace_root, vim.inspect(project))
end)

check('keeps a standalone Cargo crate when no workspace manifest exists above it', function()
  local standalone = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(standalone, fixture .. '/standalone/src/main.rs')
  local project = context.for_buffer(standalone, languages.dap_by_ft.rust.root_profile)
  assert(project.root == vim.fs.dirname(vim.fs.dirname(vim.api.nvim_buf_get_name(standalone))), vim.inspect(project))
  vim.api.nvim_buf_delete(standalone, { force = true })
end)

vim.api.nvim_buf_delete(buffer, { force = true })
vim.fn.delete(fixture, 'rf')

if #failures > 0 then error(string.format('%d Rust root check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Rust root checks passed.\n'
