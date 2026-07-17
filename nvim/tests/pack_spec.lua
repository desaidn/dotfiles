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

local function run_treesitter_hook(kind)
  local call = {}
  local function task()
    return { wait = function(_, timeout) call.wait_timeout = timeout end }
  end

  package.loaded['nvim-treesitter'] = {
    install = function(requested)
      call.operation = 'install'
      call.languages = requested
      return task()
    end,
    update = function(requested)
      call.operation = 'update'
      call.languages = requested
      return task()
    end,
  }

  require('custom.lib.pack').setup()
  vim.api.nvim_exec_autocmds('PackChanged', {
    data = {
      active = true,
      kind = kind,
      path = '/tmp/nvim-treesitter',
      spec = { name = 'nvim-treesitter' },
    },
  })
  return call
end

local function assert_treesitter_call(kind, expected_operation)
  local call = run_treesitter_hook(kind)
  assert(call.operation == expected_operation, string.format('expected %s(), got %s()', expected_operation, tostring(call.operation)))
  assert(vim.deep_equal(call.languages, require('custom.languages').treesitter_parsers), expected_operation .. ' did not receive the configured parser set')
  assert(call.wait_timeout == 60000, string.format('expected a 60000 ms wait, got %s', tostring(call.wait_timeout)))
end

check('updates compatible parsers and queries after nvim-treesitter updates', function() assert_treesitter_call('update', 'update') end)

check('installs configured parsers and queries with nvim-treesitter', function() assert_treesitter_call('install', 'install') end)

if #failures > 0 then error(string.format('%d package hook check(s) failed: %s', #failures, table.concat(failures, ', '))) end

io.stdout:write 'All package hook checks passed.\n'
