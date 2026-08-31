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

local function create_file(path) assert(vim.fn.writefile({}, path) == 0, 'failed to create ' .. path) end

local fixture = vim.fn.tempname()
local alpha = fixture .. '/alpha/service'
local beta = fixture .. '/beta/service'
local priority = fixture .. '/priority/module'
assert(vim.fn.mkdir(alpha .. '/src', 'p') == 1, 'failed to create alpha fixture')
assert(vim.fn.mkdir(beta .. '/src', 'p') == 1, 'failed to create beta fixture')
assert(vim.fn.mkdir(priority .. '/src', 'p') == 1, 'failed to create priority fixture')
create_file(alpha .. '/pom.xml')
create_file(beta .. '/pom.xml')
create_file(alpha .. '/src/Main.java')
create_file(beta .. '/src/Main.java')
create_file(fixture .. '/priority/.git')
create_file(priority .. '/pom.xml')
create_file(priority .. '/build.gradle.kts')
create_file(priority .. '/src/Main.java')
assert(vim.fn.mkdir(alpha .. '/.vscode', 'p') == 1, 'failed to create launch fixture')
create_file(alpha .. '/.vscode/launch.json')

local context = require 'custom.languages.context'
local java_profile = { markers = { { 'pom.xml', 'build.gradle', 'build.gradle.kts' }, '.git' } }
local alpha_file = alpha .. '/src/Main.java'
local beta_file = beta .. '/src/Main.java'
local alpha_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(alpha_buf, alpha_file)
local beta_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(beta_buf, beta_file)
local alpha_root = vim.fs.normalize(assert(vim.fs.root(vim.api.nvim_buf_get_name(alpha_buf), java_profile.markers)))
local beta_root = vim.fs.normalize(assert(vim.fs.root(vim.api.nvim_buf_get_name(beta_buf), java_profile.markers)))

check('uses the caller marker profile from the named buffer', function()
  assert(
    context.for_buffer(alpha_buf, java_profile).root == alpha_root,
    vim.inspect { expected = alpha_root, actual = context.for_buffer(alpha_buf, java_profile) }
  )
  assert(
    context.for_buffer(beta_buf, java_profile).root == beta_root,
    vim.inspect { expected = beta_root, actual = context.for_buffer(beta_buf, java_profile) }
  )
end)

check('prefers the nearest language marker over a repository fallback', function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buffer, priority .. '/src/Main.java')
  local expected = vim.fs.normalize(assert(vim.fs.root(vim.api.nvim_buf_get_name(buffer), { 'pom.xml' })))
  assert(context.for_buffer(buffer, java_profile).root == expected)
  assert(vim.deep_equal(java_profile.markers[1], { 'pom.xml', 'build.gradle', 'build.gradle.kts' }), 'Java build markers must share priority')
  vim.api.nvim_buf_delete(buffer, { force = true })
end)

check('preserves the named file path alongside its project root', function()
  assert(context.for_buffer(alpha_buf, java_profile).path:match '/alpha/service/src/Main.java$')
  assert(context.for_buffer(beta_buf, java_profile).path:match '/beta/service/src/Main.java$')
end)

check('does not assign unnamed or special buffers to the current directory', function()
  local unnamed = vim.api.nvim_create_buf(true, false)
  local special = vim.api.nvim_create_buf(true, false)
  vim.bo[special].buftype = 'nofile'
  assert(context.for_buffer(unnamed, java_profile) == nil)
  assert(context.for_buffer(special, java_profile) == nil)
end)

check('honors a profile resolver that rejects the buffer', function()
  local rejecting_profile = {
    markers = java_profile.markers,
    resolve = function() return nil end,
  }
  assert(context.for_buffer(alpha_buf, rejecting_profile) == nil, 'resolver rejection must not fall back to marker discovery')
end)

check('creates stable and collision-resistant workspace-data paths', function()
  local alpha_data = context.workspace_data('jdtls', alpha_root)
  local beta_data = context.workspace_data('jdtls', beta_root)
  assert(alpha_data ~= beta_data, 'same-basename projects must not share JDTLS data')
  assert(alpha_data == context.workspace_data('jdtls', alpha_root), 'workspace data path must be stable')
  assert(alpha_data:match '/jdtls/service%-%x+$', alpha_data)
end)

for _, bufnr in ipairs { alpha_buf, beta_buf } do
  vim.api.nvim_buf_delete(bufnr, { force = true })
end
vim.fn.delete(fixture, 'rf')

if #failures > 0 then error(string.format('%d context check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All project-context checks passed.\n'
