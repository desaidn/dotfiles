-- Exercise the real pinned nvim-lint; only package provisioning and eslint_d's
-- external process are substituted. No ESLint daemon or project code runs.
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')
package.path = nvim_root .. '/lua/?.lua;' .. nvim_root .. '/lua/?/init.lua;' .. package.path
local lint_path = vim.fs.joinpath(vim.fn.stdpath 'data', 'site/pack/core/opt/nvim-lint')
assert(vim.uv.fs_stat(lint_path), 'Install the locked nvim-lint package before running lint_spec.lua')
vim.opt.runtimepath:append(lint_path)
vim.o.swapfile = false

local failures = {}
local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
  else
    failures[#failures + 1] = name
    io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
  end
end
local function create_file(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines or {}, path) == 0)
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
fixture = assert(vim.uv.fs_realpath(fixture))
local root = fixture .. '/project'
create_file(root .. '/eslint.config.js')
create_file(root .. '/packages/web/eslint.config.js')
create_file(root .. '/legacy/package.json', { '{"eslintConfig":{"rules":{}}}' })
for _, name in ipairs { 'global', 'tab', 'window', 'unconfigured' } do
  assert(vim.fn.mkdir(fixture .. '/' .. name, 'p') == 1)
end
local executable = fixture .. '/eslint_d'
create_file(executable, { '#!/bin/sh', 'cat >/dev/null', "printf '[]\\n'" })
assert(vim.uv.fs_chmod(executable, 493))
local buffers = {}
local function buffer(path)
  create_file(path, { 'const value = 1;' })
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.bo[bufnr].filetype = 'javascript'
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'const value = 1;' })
  buffers[#buffers + 1] = bufnr
  return bufnr
end
local configured = buffer(root .. '/packages/web/src/configured.js')
local legacy = buffer(root .. '/legacy/src/legacy.js')
local unconfigured = buffer(fixture .. '/unconfigured/plain.js')
local other = buffer(root .. '/other.js')
local wiped = buffer(root .. '/wiped.js')
local original_cwd = vim.fn.getcwd()
local original_pack_add = vim.pack.add
local original_exepath = vim.fn.exepath
local original_spawn = vim.uv.spawn
local original_dap = package.loaded['custom.languages.dap']
local original_lint = package.loaded.lint
local original_test_env = vim.env.DOTFILES_LINT_TEST
local available = false
local spawns = {}
local function ignore_package_additions() end
local function resolve_linter(name)
  if name == 'eslint_d' then return available and executable or '' end
  return original_exepath(name)
end
vim.pack.add = ignore_package_additions
vim.fn.exepath = resolve_linter
vim.uv.spawn = function(command, options, callback)
  spawns[#spawns + 1] = { command = command, options = { cwd = options.cwd, args = vim.deepcopy(options.args), env = vim.deepcopy(options.env) } }
  return original_spawn(command, options, callback)
end
package.loaded['custom.languages.dap'] = { register_buffer_setup = function() end }
package.loaded.lint = nil
vim.env.DOTFILES_LINT_TEST = 'inherited'
local lint = require 'lint'
local function dispatch(event, bufnr) vim.api.nvim_exec_autocmds(event, { group = 'lint', buffer = bufnr }) end
local function settle()
  assert(vim.wait(2000, function() return #lint.get_running() == 0 end, 10), 'fixture linter did not exit')
end
local function state()
  return {
    current = vim.fn.getcwd(),
    global = vim.fn.getcwd(-1, -1),
    tab = vim.fn.getcwd(-1, 0),
    window_scope = vim.fn.haslocaldir(),
    tab_scope = vim.fn.haslocaldir(-1, 0),
  }
end
local setup_ok, setup_error = xpcall(function()
  dofile(nvim_root .. '/lua/custom/languages/adapters/javascript.lua').setup()
  vim.api.nvim_set_current_buf(configured)
  check('discovers eslint_d installed after setup without restarting', function()
    dispatch('BufWritePost', configured)
    assert(#spawns == 0, 'missing executable must not spawn')
    available = true
    dispatch('BufWritePost', configured)
    assert(#spawns == 1, 'newly available executable was not detected')
    settle()
  end)
  check('uses the nearest named config and preserves the inherited environment', function()
    local spawn = spawns[#spawns]
    assert(spawn.command == executable, 'must use the PATH-owned transport')
    assert(spawn.options.cwd == root .. '/packages/web', vim.inspect(spawn))
    assert(vim.list_contains(spawn.options.env, 'ESLINT_D_MISS=ignore'), 'bundled ESLint fallback must be disabled')
    assert(vim.list_contains(spawn.options.env, 'DOTFILES_LINT_TEST=inherited'), 'other environment variables must survive')
    assert(vim.list_contains(spawn.options.args, vim.api.nvim_buf_get_name(configured)))
  end)
  check('selects package.json and unconfigured source directories without inheriting editor cwd', function()
    vim.cmd.cd(fixture .. '/global')
    dispatch('BufWritePost', legacy)
    assert(spawns[#spawns].options.cwd == root .. '/legacy', 'the nearer package.json must beat the parent named config')
    assert(vim.list_contains(spawns[#spawns].options.args, vim.api.nvim_buf_get_name(legacy)))
    dispatch('BufWritePost', unconfigured)
    assert(spawns[#spawns].options.cwd == fixture .. '/unconfigured')
    assert(vim.api.nvim_get_current_buf() == configured, 'linting must preserve the current buffer')
    settle()
  end)
  check('waits for an unconfigured new file directory to exist', function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    buffers[#buffers + 1] = bufnr
    vim.api.nvim_buf_set_name(bufnr, fixture .. '/not-created/source.js')
    vim.bo[bufnr].filetype = 'javascript'
    local before = #spawns
    dispatch('BufEnter', bufnr)
    assert(#spawns == before, 'a missing directory must not become a process cwd')
  end)
  for _, scope in ipairs { 'global', 'window', 'tab', 'both' } do
    check('real nvim-lint preserves ' .. scope .. ' directory scopes', function()
      vim.cmd.cd(fixture .. '/global')
      if scope == 'tab' or scope == 'both' then vim.cmd.tcd(fixture .. '/tab') end
      if scope == 'window' or scope == 'both' then vim.cmd.lcd(fixture .. '/window') end
      local before = state()
      dispatch('BufWritePost', configured)
      assert(vim.deep_equal(before, state()), vim.inspect { before = before, after = state() })
      assert(spawns[#spawns].options.cwd == root .. '/packages/web')
      settle()
    end)
  end
  check('debounces each changed buffer without following the selected buffer', function()
    spawns = {}
    dispatch('TextChanged', configured)
    dispatch('TextChanged', configured)
    dispatch('TextChanged', other)
    dispatch('TextChanged', wiped)
    vim.api.nvim_buf_delete(wiped, { force = true })
    vim.api.nvim_set_current_buf(unconfigured)
    -- Switching buffers legitimately lints the newly entered one immediately.
    spawns = {}
    assert(vim.wait(1000, function() return #spawns >= 2 end, 10))
    settle()
    assert(#spawns == 2, vim.inspect(spawns))
    local sources = {}
    for _, spawn in ipairs(spawns) do
      sources[spawn.options.args[#spawn.options.args]] = true
    end
    assert(sources[vim.api.nvim_buf_get_name(configured)] and sources[vim.api.nvim_buf_get_name(other)])
    assert(vim.api.nvim_get_current_buf() == unconfigured)
  end)
end, debug.traceback)
settle()
vim.api.nvim_del_augroup_by_name 'lint'
vim.pack.add = original_pack_add
vim.fn.exepath = original_exepath
vim.uv.spawn = original_spawn
package.loaded.lint = original_lint
package.loaded['custom.languages.dap'] = original_dap
vim.env.DOTFILES_LINT_TEST = original_test_env
vim.cmd.cd(original_cwd)
for _, bufnr in ipairs(buffers) do
  if vim.api.nvim_buf_is_valid(bufnr) then vim.api.nvim_buf_delete(bufnr, { force = true }) end
end
vim.fs.rm(fixture, { recursive = true, force = true })
if not setup_ok then error(setup_error) end
if #failures > 0 then error(('%d lint check(s) failed: %s'):format(#failures, table.concat(failures, ', '))) end
io.stdout:write 'All lint checks passed.\n'
