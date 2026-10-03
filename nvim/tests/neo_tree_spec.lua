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

vim.opt.packpath:append(vim.fn.stdpath 'data' .. '/site')
vim.cmd.packadd 'plenary.nvim'
vim.cmd.packadd 'nui.nvim'
vim.cmd.packadd 'neo-tree.nvim'

local original_clipboard = vim.g.clipboard
local original_pack_add = vim.pack.add
local original_new_fs_event = vim.uv.new_fs_event
local original_columns = vim.o.columns
local watcher_callbacks = {}
local clipboard = { lines = {}, regtype = 'v' }
local fixture = vim.fn.tempname()

local function create_file(path)
  local descriptor, open_error = vim.uv.fs_open(path, 'w', 420)
  assert(descriptor, 'file creation failed: ' .. (open_error or 'unknown error'))
  local closed, close_error = vim.uv.fs_close(descriptor)
  assert(closed, 'file close failed: ' .. (close_error or 'unknown error'))
end

local function cleanup()
  pcall(function() require('neo-tree.sources.filesystem.lib.fs_watch').stop_watching() end)
  vim.uv.new_fs_event = original_new_fs_event
  vim.pack.add = original_pack_add
  vim.g.clipboard = original_clipboard
  vim.o.columns = original_columns
  vim.fn.delete(fixture, 'rf')
end

local setup_ok, setup_error = xpcall(function()
  vim.g.mapleader = ' '
  vim.g.clipboard = {
    name = 'neo-tree-test',
    copy = {
      ['+'] = function(lines, regtype)
        clipboard.lines = vim.deepcopy(lines)
        clipboard.regtype = regtype
      end,
      ['*'] = function() end,
    },
    paste = {
      ['+'] = function() return { clipboard.lines, clipboard.regtype } end,
      ['*'] = function() return { {}, 'v' } end,
    },
    cache_enabled = 0,
  }
  local function ignore_package_additions(_, _) end
  vim.pack.add = ignore_package_additions
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
  local selected_directory = fixture .. '/selected-directory'
  local selected_file = fixture .. '/selected-file.txt'
  local nested_file = selected_directory .. '/nested-file.txt'
  assert(vim.fn.mkdir(selected_directory, 'p') == 1, 'failed to create selected directory')
  create_file(selected_file)
  create_file(nested_file)
  local git_init = vim.system({ 'git', 'init', '--quiet', fixture }, { text = true }):wait()
  assert(git_init.code == 0, git_init.stderr)

  dofile(nvim_root .. '/lua/kickstart/plugins/neo-tree.lua')

  local neo_tree = require 'neo-tree'
  local command = require 'neo-tree.command'
  local manager = require 'neo-tree.sources.manager'
  local renderer = require 'neo-tree.ui.renderer'

  neo_tree.ensure_config()
  assert(neo_tree.config.filesystem.use_libuv_file_watcher, 'production config disabled Neo-tree filesystem watching')

  command.execute {
    action = 'focus',
    source = 'filesystem',
    dir = fixture,
  }

  local state = manager.get_state 'filesystem'
  wait_for(
    'Neo-tree did not load the fixture directory',
    function() return state.tree ~= nil and state.tree:get_node(selected_directory) ~= nil and state.tree:get_node(selected_file) ~= nil end
  )

  local function invoke_mapping(lhs, node_path, expected, source_state)
    source_state = source_state or state
    assert(renderer.focus_node(source_state, node_path), 'failed to select ' .. node_path)
    local mapping = vim.fn.maparg(lhs, 'n', false, true)
    assert(mapping.buffer == 1 and mapping.callback ~= nil, lhs .. ' is not a buffer-local Neo-tree mapping')
    vim.fn.setreg('+', 'not-copied')
    vim.api.nvim_feedkeys(vim.keycode(lhs), 'mx', false)
    assert(vim.fn.getreg '+' == expected, ('%s copied %q instead of %q'):format(lhs, vim.fn.getreg '+', expected))
  end

  check('copies absolute paths for selected files and directories', function()
    invoke_mapping('<leader>pa', selected_file, selected_file)
    invoke_mapping('<leader>pa', selected_directory, selected_directory)
  end)

  check('copies tree-relative paths for selected files and directories', function()
    invoke_mapping('<leader>pr', selected_file, 'selected-file.txt')
    invoke_mapping('<leader>pr', selected_directory, 'selected-directory')
  end)

  check('refreshes an open filesystem tree after an external change', function()
    local normalized_fixture = vim.fs.normalize(fixture)
    wait_for('Neo-tree did not watch the fixture directory', function() return watcher_callbacks[normalized_fixture] ~= nil end)

    local original_buf = state.bufnr
    local original_win = state.winid
    local copied_file = fixture .. '/copied-over-scp.txt'
    assert(state.tree:get_node(copied_file) == nil, 'external file existed before the test created it')
    create_file(copied_file)

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
  end)

  check('opening a file keeps the originating tab and focuses the file', function()
    vim.cmd.tabnew()
    local tab = vim.api.nvim_get_current_tabpage()
    command.execute { action = 'focus', source = 'filesystem', dir = fixture }
    local second = manager.get_state 'filesystem'
    wait_for('second explorer did not load', function() return second.tree and second.tree:get_node(selected_file) ~= nil end)
    assert(renderer.focus_node(second, selected_file))
    require('neo-tree.sources.filesystem.commands').open(second)
    vim.wait(100)
    assert(vim.api.nvim_get_current_tabpage() == tab, 'opening a file jumped to another tab')
    assert(vim.api.nvim_buf_get_name(0) == selected_file, 'opening a file should retain upstream editor focus')
  end)

  for _, source in ipairs { 'buffers', 'git_status' } do
    check('copies selected file, directory, and root paths in ' .. source, function()
      for _, path in ipairs { selected_file, nested_file } do
        local buf = vim.fn.bufadd(path)
        vim.fn.bufload(buf)
        vim.bo[buf].buflisted = true
      end
      command.execute { action = 'focus', source = source, dir = fixture }
      local source_state = manager.get_state(source)
      wait_for(
        source .. ' did not load the fixture',
        function() return source_state.tree and source_state.tree:get_node(selected_file) and source_state.tree:get_node(selected_directory) end
      )
      invoke_mapping('<leader>pa', selected_file, selected_file, source_state)
      invoke_mapping('<leader>pr', selected_file, 'selected-file.txt', source_state)
      invoke_mapping('<leader>pa', selected_directory, selected_directory, source_state)
      invoke_mapping('<leader>pr', selected_directory, 'selected-directory', source_state)
      invoke_mapping('<leader>pr', fixture, '.', source_state)
    end)
  end

  check('leaves the clipboard unchanged for unnamed buffers and terminal groups', function()
    local unnamed = vim.api.nvim_create_buf(true, false)
    local terminal = vim.api.nvim_create_buf(true, false)
    local terminal_name = 'term://' .. fixture .. '//123:test-terminal'
    vim.api.nvim_buf_set_name(terminal, terminal_name)
    command.execute { action = 'focus', source = 'buffers', dir = fixture }
    local source_state = manager.get_state 'buffers'
    wait_for(
      'buffers source did not load virtual nodes',
      function() return source_state.tree and source_state.tree:get_node(tostring(unnamed)) and source_state.tree:get_node 'Terminals' end
    )
    for _, node in ipairs { tostring(unnamed), 'Terminals', terminal_name } do
      invoke_mapping('<leader>pa', node, 'not-copied', source_state)
      invoke_mapping('<leader>pr', node, 'not-copied', source_state)
    end
    vim.api.nvim_buf_delete(unnamed, { force = true })
    vim.api.nvim_buf_delete(terminal, { force = true })
  end)

  check('preserves the clipboard while a directory refresh displays an outside-root file', function()
    command.execute { action = 'focus', source = 'filesystem', dir = fixture }
    local source_state = manager.get_state 'filesystem'
    wait_for(
      'filesystem did not return to the original root',
      function() return source_state.path == fixture and source_state.tree and source_state.tree:get_node(selected_file) end
    )
    assert(renderer.focus_node(source_state, selected_file))
    assert(source_state.bind_to_cwd and source_state.async_directory_scan == 'auto', 'expected native cwd binding and asynchronous refresh')

    local original_tab_cwd = vim.fn.getcwd(-1, 0)
    local original_opendir = vim.uv.fs_opendir
    local hold_results = true
    local pending = {}
    -- Delay real directory results so the previous tree stays visible during refresh.
    local function delayed_opendir(path, callback, entries)
      if path ~= selected_directory or type(callback) ~= 'function' then return original_opendir(path, callback, entries) end
      return original_opendir(path, function(err, directory)
        local function deliver() callback(err, directory) end
        if hold_results then
          pending[#pending + 1] = deliver
        else
          deliver()
        end
      end, entries)
    end
    vim.uv.fs_opendir = delayed_opendir
    local ok, err = pcall(function()
      vim.cmd.tcd(selected_directory)
      wait_for('directory refresh did not reach its delayed scan', function() return source_state.path == selected_directory and #pending > 0 end)
      local node = source_state.tree:get_node(selected_file)
      assert(node and node.path == selected_file, 'refresh did not retain the previously rendered file')
      assert(vim.fs.relpath(source_state.path, node.path) == nil, 'selected file is not outside the new root')
      invoke_mapping('<leader>pr', selected_file, 'not-copied', source_state)
    end)

    hold_results = false
    vim.uv.fs_opendir = original_opendir
    for _, callback in ipairs(pending) do
      vim.schedule(callback)
    end
    local drained, drain_error = pcall(function()
      if source_state.path ~= selected_directory then return end
      wait_for(
        'directory refresh did not finish after releasing its scan',
        function() return source_state.tree and source_state.tree:get_node(nested_file) and not source_state.tree:get_node(selected_file) end
      )
    end)
    local restored, restore_error = pcall(vim.cmd.tcd, original_tab_cwd)
    assert(restored, restore_error)
    assert(drained, drain_error)
    assert(ok, err)
  end)
end, debug.traceback)

cleanup()

if not setup_ok then
  failures[#failures + 1] = 'initializes the Neo-tree test fixture'
  io.stderr:write('FAIL initializes the Neo-tree test fixture\n  ', tostring(setup_error):gsub('\n', '\n  '), '\n')
end

if #failures > 0 then error(string.format('%d Neo-tree check(s) failed: %s', #failures, table.concat(failures, ', '))) end

io.stdout:write 'All Neo-tree checks passed.\n'
