local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')
local flatten_path = nvim_root .. '/lua/custom/plugins/flatten.lua'

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local fixture = vim.fn.tempname()
local swap_directory = fixture .. '/swap'
local target = fixture .. '/collision.lua'
local owner_init = fixture .. '/owner-init.lua'
local owner_ready = fixture .. '/owner-ready'
local owner

local function write(path, lines) assert(vim.fn.writefile(lines, path) == 0, 'failed to write ' .. path) end

local function cleanup()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == target then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
  end
  if owner and not owner:is_closing() then
    owner:kill 'sigterm'
    owner:wait(1000)
  end
  vim.fn.delete(fixture, 'rf')
end

local function run()
  assert(vim.fn.mkdir(swap_directory, 'p') == 1, 'failed to create the swap fixture')
  write(target, { 'return "live swap collision"' })
  write(owner_init, {
    ('vim.opt.directory = { %q }'):format(swap_directory .. '//'),
    'vim.api.nvim_create_autocmd("BufEnter", {',
    '  once = true,',
    '  callback = function()',
    '    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return \\"unsaved owner state\\"" })',
    '    vim.schedule(function()',
    ('      vim.fn.writefile({ tostring(vim.fn.getpid()), vim.fn.swapname(vim.api.nvim_get_current_buf()) }, %q)'):format(owner_ready),
    '    end)',
    '  end,',
    '})',
  })

  local owner_errors = {}
  owner = vim.system({ vim.v.progpath, '--headless', '-i', 'NONE', '-u', owner_init, target }, {
    text = true,
    stderr = function(err, data)
      if err then owner_errors[#owner_errors + 1] = err end
      if data and data ~= '' then owner_errors[#owner_errors + 1] = data end
    end,
  })
  assert(owner.pid > 0, 'failed to start the swap-owning Neovim')
  assert(
    vim.wait(5000, function() return vim.uv.fs_stat(owner_ready) ~= nil end, 10),
    'swap-owning Neovim did not become ready: ' .. table.concat(owner_errors, '\n')
  )
  assert(not owner:is_closing(), 'swap-owning Neovim exited before the handoff')
  local owner_state = vim.fn.readfile(owner_ready)
  assert(owner_state[2] and owner_state[2] ~= '', 'swap-owning Neovim did not create a swapfile')
  assert(vim.uv.fs_stat(owner_state[2]), 'swap-owning Neovim reported a missing swapfile: ' .. owner_state[2])

  vim.opt.directory = { swap_directory .. '//' }
  vim.o.updatecount = 200
  local flatten_root = vim.fn.stdpath 'data' .. '/site/pack/core/opt/flatten.nvim'
  assert(vim.uv.fs_stat(flatten_root), 'flatten.nvim is not installed at ' .. flatten_root)
  vim.opt.runtimepath:append(flatten_root)

  local pack_add = vim.pack.add
  vim.pack.add = function() end
  local loaded, load_error = pcall(dofile, flatten_path)
  vim.pack.add = pack_add
  assert(loaded, load_error)

  local target_win = vim.api.nvim_get_current_win()
  vim.cmd.vnew()
  local starting_win = vim.api.nvim_get_current_win()
  assert(starting_win ~= target_win, 'test requires distinct current and alternate windows')

  local handoff_ok, handoff_error = pcall(require('flatten.core').edit_files, {
    files = { target },
    response_pipe = '',
    guest_cwd = fixture,
    stdin = {},
    quickfix = {},
    force_block = false,
    argv = { 'nvim', target },
    data = {},
  })

  local target_buffer = vim.fn.bufnr(target)
  local target_installed = target_buffer > 0 and vim.api.nvim_win_get_buf(target_win) == target_buffer
  local target_focused = vim.api.nvim_get_current_win() == target_win
  assert(
    handoff_ok and target_installed and target_focused,
    ('production handoff escaped a live swap collision (error=%s, target_installed=%s, target_focused=%s)'):format(
      tostring(handoff_error),
      tostring(target_installed),
      tostring(target_focused)
    )
  )
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
  io.stderr:write('FAIL production Flatten handoff completes across a live swap collision\n', err, '\n')
  os.exit(1)
end

io.stdout:write 'PASS production Flatten handoff completes across a live swap collision\n'
