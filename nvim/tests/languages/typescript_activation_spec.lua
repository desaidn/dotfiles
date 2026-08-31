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

local function create_file(path, lines)
  assert(vim.fn.mkdir(vim.fs.dirname(path), 'p') == 1 or vim.uv.fs_stat(vim.fs.dirname(path)), 'failed to create fixture directory')
  assert(vim.fn.writefile(lines or {}, path) == 0, 'failed to create ' .. path)
end

local fixture = vim.fn.tempname()
local native_root = fixture .. '/typescript-seven'
local native_source = native_root .. '/src/App.tsx'
local legacy_root = fixture .. '/typescript-five'
local legacy_source = legacy_root .. '/src/App.tsx'

create_file(native_root .. '/package-lock.json')
create_file(native_source)
create_file(native_root .. '/node_modules/.bin/tsc', { '#!/bin/sh', 'echo "Version 7.0.2"' })
assert(vim.uv.fs_chmod(native_root .. '/node_modules/.bin/tsc', 493))

create_file(legacy_root .. '/pnpm-lock.yaml')
create_file(legacy_source)
create_file(legacy_root .. '/node_modules/.bin/tsc', { '#!/bin/sh', 'echo "Version 5.9.3"' })
create_file(legacy_root .. '/node_modules/typescript/lib/tsserver.js')
assert(vim.uv.fs_chmod(legacy_root .. '/node_modules/.bin/tsc', 493))

local original_start = vim.lsp.start
local starts = {}
vim.lsp.start = function(config, options)
  starts[#starts + 1] = { config = config, options = options }
  return #starts
end

local setup_ok, setup_error = xpcall(function()
  vim.opt.packpath:prepend(vim.fn.stdpath 'data' .. '/site')
  vim.cmd.packadd 'nvim-lspconfig'

  local servers = require('custom.languages.config').lsp_servers
  for _, name in ipairs { 'tsc', 'ts_ls' } do
    vim.lsp.config(name, servers[name])
  end
  local resolved_legacy = vim.lsp.config.ts_ls
  assert(vim.tbl_contains(resolved_legacy.filetypes, 'typescriptreact'), 'upstream ts_ls TSX filetype must survive merging')
  assert(type(resolved_legacy.on_attach) == 'function', 'upstream TypeScript buffer commands must survive merging')
  assert(resolved_legacy.handlers['_typescript.rename'], 'upstream TypeScript handlers must survive merging')
  assert(
    resolved_legacy.handlers['$/typescriptVersion'] == servers.ts_ls.handlers['$/typescriptVersion'],
    'project TypeScript enforcement must survive merging'
  )
  assert(resolved_legacy.commands['editor.action.showReferences'], 'upstream TypeScript commands must survive merging')
  assert(resolved_legacy.on_init == servers.ts_ls.on_init, 'local formatting policy must survive merging')
  vim.lsp.enable { 'tsc', 'ts_ls' }

  local function assert_route(source, expected_name, expected_root)
    starts = {}
    vim.cmd.edit(vim.fn.fnameescape(source))
    assert(vim.bo.filetype == 'typescriptreact', 'TSX must resolve to typescriptreact')
    assert(vim.wait(1000, function() return #starts > 0 end, 10), 'native LSP activation did not start a semantic client')
    assert(#starts == 1, ('expected one semantic client, got %d: %s'):format(#starts, vim.inspect(starts)))
    assert(starts[1].config.name == expected_name, vim.inspect(starts[1].config))
    assert(starts[1].config.root_dir == vim.fs.normalize(assert(vim.uv.fs_realpath(expected_root))), vim.inspect(starts[1].config.root_dir))
    assert(starts[1].options.bufnr == vim.api.nvim_get_current_buf())
  end

  check('activates only the native client for a TypeScript 7 TSX project', function() assert_route(native_source, 'tsc', native_root) end)

  check('activates only the compatibility client for a pre-TypeScript-7 TSX project', function() assert_route(legacy_source, 'ts_ls', legacy_root) end)
end, debug.traceback)

vim.lsp.start = original_start
vim.lsp.enable({ 'tsc', 'ts_ls' }, false)
vim.fn.delete(fixture, 'rf')

if not setup_ok then
  failures[#failures + 1] = 'initializes native TypeScript activation fixtures'
  io.stderr:write('FAIL initializes native TypeScript activation fixtures\n  ', tostring(setup_error):gsub('\n', '\n  '), '\n')
end

if #failures > 0 then error(string.format('%d TypeScript activation check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All native TypeScript activation checks passed.\n'
