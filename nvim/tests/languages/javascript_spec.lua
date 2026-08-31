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
local original_cmd_packadd = vim.cmd.packadd
local original_exepath = vim.fn.exepath
local original_dap = package.loaded.dap
local original_dapui = package.loaded.dapui
local original_shared_dap = package.loaded['custom.languages.dap']

local fake_dap = {
  ABORT = {},
  adapters = {},
  configurations = {},
  providers = { configs = {} },
  listeners = { after = { event_initialized = {} }, before = { event_terminated = {}, event_exited = {} } },
}
local dapui_setup_calls = 0
local js_debug_exepath_calls = 0
local js_debug_available = false
vim.pack.add = function() end
vim.cmd.packadd = function() end
vim.fn.exepath = function(name)
  if name == 'js-debug-adapter' then
    js_debug_exepath_calls = js_debug_exepath_calls + 1
    return js_debug_available and '/mason/bin/js-debug-adapter' or ''
  end
  return original_exepath(name)
end
package.loaded.dap = fake_dap
package.loaded.dapui = { setup = function() dapui_setup_calls = dapui_setup_calls + 1 end }
package.loaded['custom.languages.dap'] = nil

local fixture = vim.fn.tempname()
local project_root = fixture .. '/web-app'
local source = project_root .. '/src/index.js'
assert(vim.fn.mkdir(project_root .. '/src', 'p') == 1)
assert(vim.fn.writefile({}, project_root .. '/package-lock.json') == 0)
assert(vim.fn.writefile({}, source) == 0)
local expected_root = assert(vim.uv.fs_realpath(project_root))
local expected_source = assert(vim.uv.fs_realpath(source))

local javascript = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(javascript, source)
vim.bo[javascript].filetype = 'javascript'
local rust = vim.api.nvim_create_buf(true, false)
vim.bo[rust].filetype = 'rust'

local setup_ok, setup_error = xpcall(function()
  local shared_dap = assert(loadfile(nvim_root .. '/lua/custom/languages/dap.lua'))()
  package.loaded['custom.languages.dap'] = shared_dap
  dofile(nvim_root .. '/lua/custom/languages/adapters/javascript.lua')

  vim.api.nvim_exec_autocmds('FileType', { buffer = javascript })
  vim.api.nvim_exec_autocmds('FileType', { buffer = rust })

  check('registers JavaScript and TypeScript projects without eagerly loading DAP', function()
    local languages = require 'custom.languages.config'
    local expected_types = { 'node', 'chrome', 'msedge', 'pwa-node', 'pwa-chrome', 'pwa-msedge' }
    local root_profile
    for _, filetype in ipairs { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' } do
      local project = languages.dap_by_ft[filetype]
      assert(project, 'missing DAP project for ' .. filetype)
      assert(project.lsp_client == 'tsc')
      assert(vim.deep_equal(project.launch_types, expected_types), vim.inspect(project.launch_types))
      assert(type(project.prepare_launch) == 'function', 'JS/TS launch aliases must be normalized for standalone js-debug')
      assert(project.prepare_launch({ type = 'node' }).type == 'pwa-node')
      assert(project.prepare_launch({ type = 'chrome' }).type == 'pwa-chrome')
      assert(project.prepare_launch({ type = 'msedge' }).type == 'pwa-msedge')
      assert(project.prepare_launch({ type = 'pwa-node' }).type == 'pwa-node')
      root_profile = root_profile or project.root_profile
      assert(project.root_profile == root_profile, 'JS/TS DAP declarations must share one project profile')
    end
    assert(dapui_setup_calls == 0, 'opening a JavaScript buffer must not load DAP')
    assert(js_debug_exepath_calls == 0, 'opening a JavaScript buffer must not resolve js-debug')
    assert(fake_dap.adapters.node == nil, 'js-debug must remain unconfigured before a debug action')
  end)

  check('does not route Deno buffers to the Node and browser debugger', function()
    local deno_source = project_root .. '/packages/deno/mod.ts'
    assert(vim.fn.mkdir(vim.fs.dirname(deno_source), 'p') == 1)
    assert(vim.fn.writefile({}, project_root .. '/packages/deno/deno.json') == 0)
    assert(vim.fn.writefile({}, deno_source) == 0)
    local deno = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(deno, deno_source)
    vim.bo[deno].filetype = 'typescript'

    local languages = require 'custom.languages.config'
    local project = require('custom.languages.context').for_buffer(deno, languages.dap_by_ft.typescript.root_profile)
    vim.api.nvim_buf_delete(deno, { force = true })
    assert(project == nil, 'Deno must not use the Node/browser DAP project profile')
  end)

  check('reports a missing js-debug executable and remains retryable', function()
    local configured, configure_error = pcall(shared_dap.ensure_buffer, javascript)
    assert(not configured, 'a missing js-debug adapter must fail the debug action')
    assert(tostring(configure_error):match 'Mason js%-debug%-adapter is not installed', tostring(configure_error))
    assert(fake_dap.adapters.node == nil, 'failed setup must not leave a partial adapter')
    js_debug_available = true
  end)

  check('initializes one direct js-debug server for every supported launch type', function()
    shared_dap.ensure_buffer(javascript)
    shared_dap.ensure_buffer(javascript)
    assert(js_debug_exepath_calls == 2, 'js-debug executable must be retried once, then cached')

    local adapter = fake_dap.adapters['pwa-node']
    assert(adapter and adapter.type == 'server', vim.inspect(adapter))
    assert(adapter.host == '127.0.0.1')
    assert(adapter.port == '${port}')
    assert(adapter.executable.command == '/mason/bin/js-debug-adapter')
    assert(vim.deep_equal(adapter.executable.args, { '${port}', '127.0.0.1' }))
    for _, name in ipairs { 'pwa-chrome', 'pwa-msedge' } do
      assert(fake_dap.adapters[name] == adapter, name .. ' must share the js-debug server')
    end
    for alias, canonical in pairs { node = 'pwa-node', chrome = 'pwa-chrome', msedge = 'pwa-msedge' } do
      local resolve = fake_dap.adapters[alias]
      assert(type(resolve) == 'function', alias .. ' must normalize before resolving js-debug')
      local resolved
      local launch_config = { type = alias }
      resolve(function(value) resolved = value end, launch_config)
      assert(resolved == adapter, alias .. ' must resolve the shared js-debug server')
      assert(launch_config.type == canonical, alias .. ' must send the canonical js-debug type')
    end

    assert(#fake_dap.configurations.javascript == 1, vim.inspect(fake_dap.configurations.javascript))
    local launch = fake_dap.configurations.javascript[1]
    assert(launch.type == 'pwa-node' and launch.request == 'launch')
    vim.api.nvim_set_current_buf(javascript)
    assert(launch.program() == expected_source)
    assert(launch.cwd() == expected_root)
    assert(fake_dap.configurations.typescript == nil, 'TypeScript execution must remain project-owned')

    local unowned_source = fixture .. '/standalone.js'
    assert(vim.fn.writefile({}, unowned_source) == 0)
    local unowned = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(unowned, unowned_source)
    vim.bo[unowned].filetype = 'javascript'
    vim.api.nvim_set_current_buf(unowned)
    assert(launch.program() == fake_dap.ABORT, 'an unowned JavaScript file must not become a debug target')
    assert(launch.cwd() == fake_dap.ABORT, 'an unowned JavaScript file must not inherit Neovim cwd')
    vim.api.nvim_buf_delete(unowned, { force = true })

    local deno_source = project_root .. '/packages/deno/index.js'
    assert(vim.fn.writefile({}, deno_source) == 0)
    local deno = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(deno, deno_source)
    vim.bo[deno].filetype = 'javascript'
    vim.api.nvim_set_current_buf(deno)
    assert(launch.program() == fake_dap.ABORT, 'a Deno JavaScript file must not become a Node debug target')
    assert(launch.cwd() == fake_dap.ABORT, 'a Deno JavaScript file must not inherit the Node project root')
    vim.api.nvim_buf_delete(deno, { force = true })
  end)
end, debug.traceback)

vim.pack.add = original_pack_add
vim.cmd.packadd = original_cmd_packadd
vim.fn.exepath = original_exepath
package.loaded.dap = original_dap
package.loaded.dapui = original_dapui
package.loaded['custom.languages.dap'] = original_shared_dap
vim.api.nvim_buf_delete(javascript, { force = true })
vim.api.nvim_buf_delete(rust, { force = true })
vim.fn.delete(fixture, 'rf')

if not setup_ok then
  failures[#failures + 1] = 'initializes the JavaScript test fixture'
  io.stderr:write('FAIL initializes the JavaScript test fixture\n  ', tostring(setup_error):gsub('\n', '\n  '), '\n')
end

if #failures > 0 then error(string.format('%d JavaScript check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All JavaScript configuration checks passed.\n'
