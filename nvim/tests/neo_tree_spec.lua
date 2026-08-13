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

local function wait_for(message, predicate) assert(vim.wait(2000, predicate, 10), message) end

check('refreshes an open filesystem tree after an external change', function()
  vim.opt.packpath:append(vim.fn.stdpath 'data' .. '/site')
  vim.cmd.packadd 'plenary.nvim'
  vim.cmd.packadd 'nui.nvim'
  vim.cmd.packadd 'neo-tree.nvim'

  local original_pack_add = vim.pack.add
  local original_new_fs_event = vim.uv.new_fs_event
  local original_columns = vim.o.columns
  local watcher_callbacks = {}
  local fixture = vim.fn.tempname()

  local function cleanup()
    pcall(function() require('neo-tree.sources.filesystem.lib.fs_watch').stop_watching() end)
    vim.uv.new_fs_event = original_new_fs_event
    vim.pack.add = original_pack_add
    vim.o.columns = original_columns
    vim.fn.delete(fixture, 'rf')
  end

  local ok, err = xpcall(function()
    vim.pack.add = function() end
    vim.o.columns = 160
    vim.uv.new_fs_event = function()
      return {
        start = function(_, path, _, callback)
          watcher_callbacks[vim.fs.normalize(path)] = callback
          return 0
        end,
        stop = function() end,
      }
    end

    assert(vim.fn.mkdir(fixture, 'p') == 1, 'failed to create fixture directory')
    fixture = assert(vim.uv.fs_realpath(fixture), 'failed to resolve fixture directory')
    dofile(nvim_root .. '/lua/kickstart/plugins/neo-tree.lua')

    local neo_tree = require 'neo-tree'
    local command = require 'neo-tree.command'
    local manager = require 'neo-tree.sources.manager'

    neo_tree.ensure_config()
    assert(neo_tree.config.filesystem.use_libuv_file_watcher, 'production config disabled Neo-tree filesystem watching')

    command.execute {
      action = 'focus',
      source = 'filesystem',
      dir = fixture,
    }

    local state = manager.get_state 'filesystem'
    wait_for('Neo-tree did not load the fixture directory', function() return state.tree ~= nil and state.tree:get_node(fixture) ~= nil end)

    local normalized_fixture = vim.fs.normalize(fixture)
    wait_for('Neo-tree did not watch the fixture directory', function() return watcher_callbacks[normalized_fixture] ~= nil end)

    local original_buf = state.bufnr
    local original_win = state.winid
    local copied_file = fixture .. '/copied-over-scp.txt'
    assert(state.tree:get_node(copied_file) == nil, 'external file existed before the test created it')

    local copied_file_descriptor, open_error = vim.uv.fs_open(copied_file, 'w', 420)
    assert(copied_file_descriptor, 'external file creation failed: ' .. (open_error or 'unknown error'))
    local closed, close_error = vim.uv.fs_close(copied_file_descriptor)
    assert(closed, 'external file close failed: ' .. (close_error or 'unknown error'))

    watcher_callbacks[normalized_fixture] 'EMFILE'
    vim.wait(20)
    assert(state.tree:get_node(copied_file) == nil, 'failed watcher unexpectedly refreshed the external file')

    vim.api.nvim_exec_autocmds('FocusGained', {})
    wait_for('FocusGained did not refresh the external file', function() return state.tree:get_node(copied_file) ~= nil end)

    assert(state.tree:get_node(copied_file).type == 'file', 'refreshed node is not a file')
    assert(state.bufnr == original_buf and vim.api.nvim_buf_is_valid(original_buf), 'refresh replaced the Neo-tree buffer')
    assert(state.winid == original_win and vim.api.nvim_win_is_valid(original_win), 'refresh replaced the Neo-tree window')

    wait_for('refreshed file was not rendered in Neo-tree', function()
      local rendered = table.concat(vim.api.nvim_buf_get_lines(original_buf, 0, -1, false), '\n')
      return rendered:find('copied-over-scp.txt', 1, true) ~= nil
    end)
  end, debug.traceback)

  cleanup()
  assert(ok, err)
end)

if #failures > 0 then error(string.format('%d Neo-tree check(s) failed: %s', #failures, table.concat(failures, ', '))) end

io.stdout:write 'All Neo-tree checks passed.\n'
