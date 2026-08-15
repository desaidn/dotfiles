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

local languages = require 'custom.languages.config'
local original_start = vim.lsp.rpc.start
local original_jvm_args = vim.env.JDTLS_JVM_ARGS
local captured = {}
vim.lsp.rpc.start = function(command, _, options)
  captured[#captured + 1] = { command = command, options = options }
  return 'started'
end
vim.env.JDTLS_JVM_ARGS = '-Xmx2G -javaagent:/tmp/lombok.jar'

local command = languages.lsp_servers.jdtls.cmd
command({}, { root_dir = '/work/alpha/service', cmd_cwd = '/work/alpha/service', cmd_env = { TEST = '1' }, detached = true })
command({}, { root_dir = '/work/beta/service' })

check('uses distinct durable data directories for same-basename Java roots', function()
  local alpha = captured[1].command
  local beta = captured[2].command
  assert(alpha[1] == 'jdtls')
  assert(alpha[2] == '-data')
  assert(alpha[3] ~= beta[3], 'same-basename Java roots must not share JDTLS data')
  assert(alpha[3]:match '/jdtls/service%-%x+$', alpha[3])
end)

check('preserves nvim-lspconfig JDTLS process options and JVM arguments', function()
  local first = captured[1]
  assert(first.command[4] == '--jvm-arg=-Xmx2G')
  assert(first.command[5] == '--jvm-arg=-javaagent:/tmp/lombok.jar')
  assert(first.options.cwd == '/work/alpha/service')
  assert(first.options.env.TEST == '1')
  assert(first.options.detached == true)
end)

vim.lsp.rpc.start = original_start
vim.env.JDTLS_JVM_ARGS = original_jvm_args

if #failures > 0 then error(string.format('%d JDTLS configuration check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All JDTLS configuration checks passed.\n'
