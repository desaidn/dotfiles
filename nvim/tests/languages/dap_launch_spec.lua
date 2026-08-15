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
local original_dap = package.loaded.dap
local original_dapui = package.loaded.dapui
local original_vscode = package.loaded['dap.ext.vscode']
local original_context = package.loaded['custom.languages.context']
local original_get_clients = vim.lsp.get_clients

local fake_dap = {
  providers = { configs = { ['dap.global'] = function() return {} end, ['dap.launch.json'] = function() return {} end } },
  listeners = { after = { event_initialized = {} }, before = { event_terminated = {}, event_exited = {} } },
}
local launch_path
local launch_name = 'Rust'
local cwd_before = vim.fn.getcwd()
local fixture = vim.fn.tempname()
assert(vim.fn.mkdir(fixture .. '/rust-app/.vscode', 'p') == 1, 'failed to create launch fixture')
assert(vim.fn.writefile({}, fixture .. '/rust-app/.vscode/launch.json') == 0, 'failed to create launch file')
local project_root = vim.fs.normalize(vim.fn.fnamemodify(fixture .. '/rust-app', ':p'))
local rust_buffer = vim.api.nvim_create_buf(true, false)
vim.bo[rust_buffer].filetype = 'rust'
vim.pack.add = function() end
vim.cmd.packadd = function() end
vim.lsp.get_clients = function() return {} end
package.loaded.dap = fake_dap
package.loaded.dapui = { setup = function() end }
package.loaded['dap.ext.vscode'] = {
  getconfigs = function(path)
    launch_path = path
    local rust = {
      name = launch_name,
      type = 'codelldb',
      cwd = '${workspaceFolder}',
      program = '${file}',
      args = { '${relativeFile}', '${workspaceFolderBasename}' },
    }
    setmetatable(rust, { __call = function() return { type = 'codelldb', cwd = '${workspaceFolder}' } end })
    return {
      rust,
      { name = 'Rust default cwd', type = 'codelldb', program = '${file}' },
      { name = 'Python', type = 'python', cwd = '${workspaceFolder}' },
    }
  end,
}
package.loaded['custom.languages.context'] = {
  for_buffer = function(bufnr)
    if bufnr == rust_buffer then return { root = project_root, path = project_root .. '/src/main.rs' } end
    return nil
  end,
}

package.loaded['custom.languages.dap'] = nil
local dap = assert(loadfile(nvim_root .. '/lua/custom/languages/dap.lua'))()
dap.ensure()

check('uses the initiating buffer root for launch.json without changing cwd', function()
  local configs = fake_dap.providers.configs['dap.launch.json'](rust_buffer)
  assert(launch_path == project_root .. '/.vscode/launch.json', tostring(launch_path))
  assert(#configs == 2 and configs[1].type == 'codelldb', vim.inspect(configs))
  assert(configs[1].cwd == project_root, vim.inspect(configs[1]))
  assert(configs[1].program == project_root .. '/src/main.rs', vim.inspect(configs[1]))
  assert(configs[1].args[1] == 'src/main.rs', vim.inspect(configs[1]))
  assert(configs[1].args[2] == 'rust-app', vim.inspect(configs[1]))
  assert(configs[1]().cwd == project_root, 'workspace variables must survive launch.json input expansion')
  assert(configs[2].cwd == project_root, 'project root must be the default launch cwd')
  assert(vim.fn.getcwd() == cwd_before, 'DAP provider must not mutate current working directory')
end)

check('does not fall back to a cwd launch configuration without project context', function()
  local other_buffer = vim.api.nvim_create_buf(true, false)
  vim.bo[other_buffer].filetype = 'rust'
  assert(#fake_dap.providers.configs['dap.launch.json'](other_buffer) == 0)
  vim.api.nvim_buf_delete(other_buffer, { force = true })
end)

check('reads launch configurations again for each debug selection', function()
  launch_name = 'Updated Rust'
  local configs = fake_dap.providers.configs['dap.launch.json'](rust_buffer)
  assert(configs[1].name == 'Updated Rust', vim.inspect(configs))
end)

vim.pack.add = original_pack_add
vim.cmd.packadd = original_cmd_packadd
package.loaded.dap = original_dap
package.loaded.dapui = original_dapui
package.loaded['dap.ext.vscode'] = original_vscode
package.loaded['custom.languages.context'] = original_context
vim.lsp.get_clients = original_get_clients
vim.api.nvim_buf_delete(rust_buffer, { force = true })
vim.fn.delete(fixture, 'rf')

if #failures > 0 then error(string.format('%d DAP launch check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All DAP launch configuration checks passed.\n'
