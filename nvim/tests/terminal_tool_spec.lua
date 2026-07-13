local real_vim = vim
local failures = {}
local script_path = real_vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = real_vim.fs.normalize(real_vim.fs.dirname(script_path) .. '/..')
local terminal_tool_path = nvim_root .. '/lua/custom/lib/terminal_tool.lua'
local hunk_path = nvim_root .. '/lua/custom/plugins/hunk.lua'
local lazygit_path = nvim_root .. '/lua/custom/plugins/lazygit.lua'
local flatten_path = nvim_root .. '/lua/custom/plugins/flatten.lua'

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end

  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function fake_vim(options)
  options = options or {}
  local fixture = {
    geometry = { width = 80, height = 24 },
    cwd = options.cwd or '/repo/one',
    current_tab = 1,
    autocmds = {},
    buffers = {},
    tabs = { [1] = { valid = true } },
    windows = { [1] = { valid = true, host = true, tab = 1 } },
    current_win = 1,
    next_buf = 1,
    next_tab = 2,
    next_win = 2,
    next_job = 1,
    job_results = real_vim.deepcopy(options.job_results or {}),
    synchronous_exits = real_vim.deepcopy(options.synchronous_exits or {}),
    job_attempts = {},
    jobs = {},
    mappings = {},
    deferred = {},
    notifications = {},
    sends = {},
  }

  local function deepcopy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, item in pairs(value) do
      copy[deepcopy(key)] = deepcopy(item)
    end
    return copy
  end

  local function mapping_key(mode, lhs, buf) return table.concat({ mode, lhs, tostring(buf or 0) }, '\0') end

  local function create_tab(host)
    local tab = fixture.next_tab
    fixture.next_tab = fixture.next_tab + 1
    local win = fixture.next_win
    fixture.next_win = fixture.next_win + 1
    fixture.tabs[tab] = { valid = true }
    fixture.windows[win] = { valid = true, host = host == true, tab = tab }
    fixture.current_tab = tab
    fixture.current_win = win
    return tab, win
  end

  local function focus_first_valid_tab()
    for tab = 1, fixture.next_tab - 1 do
      if fixture.tabs[tab] and fixture.tabs[tab].valid then
        fixture.current_tab = tab
        for win = 1, fixture.next_win - 1 do
          if fixture.windows[win] and fixture.windows[win].valid and fixture.windows[win].tab == tab then
            fixture.current_win = win
            return
          end
        end
      end
    end
  end

  local fake = {
    env = {
      TMUX = '/tmp/tmux-test/default,1,0',
      TMUX_PANE = '%1',
      EDITOR = 'nvim',
      VISUAL = 'nvim',
      GIT_EDITOR = 'nvim',
    },
    log = { levels = { ERROR = 4, WARN = 3 } },
    cmd = {
      diffthis = function() end,
      startinsert = function() end,
      tabnew = function() create_tab(false) end,
    },
    pack = { add = function() end },
    deepcopy = deepcopy,
    schedule = function(callback) callback() end,
    defer_fn = function(callback, delay) fixture.deferred[#fixture.deferred + 1] = { callback = callback, delay = delay } end,
    notify = function(message, level, notify_options)
      fixture.notifications[#fixture.notifications + 1] = {
        message = message,
        level = level,
        options = deepcopy(notify_options),
      }
    end,
    keymap = {
      set = function(mode, lhs, callback, map_options)
        local buf = map_options and map_options.buf or nil
        fixture.mappings[mapping_key(mode, lhs, buf)] = {
          callback = callback,
          options = deepcopy(map_options or {}),
        }
      end,
    },
    fn = {
      getcwd = function() return fixture.windows[fixture.current_win].cwd or fixture.cwd end,
      chansend = function(job_id, input)
        local job = fixture.jobs[job_id]
        if not job or not job.running then return 0 end
        fixture.sends[#fixture.sends + 1] = { job = job_id, input = input }
        return #input
      end,
      jobstart = function(command, job_options)
        fixture.job_attempts[#fixture.job_attempts + 1] = {
          command = deepcopy(command),
          options = deepcopy(job_options),
        }

        local result = table.remove(fixture.job_results, 1)
        if result and result <= 0 then return result end

        local job_id = fixture.next_job
        fixture.next_job = fixture.next_job + 1
        fixture.jobs[job_id] = {
          command = deepcopy(command),
          options = deepcopy(job_options),
          running = true,
        }
        if table.remove(fixture.synchronous_exits, 1) then
          fixture.jobs[job_id].running = false
          job_options.on_exit(job_id, 0, 'exit')
        end
        return job_id
      end,
      jobstop = function(job_id)
        local job = fixture.jobs[job_id]
        if not job or not job.running then return 0 end
        job.running = false
        return 1
      end,
    },
    api = {
      nvim_get_current_win = function() return fixture.current_win end,
      nvim_get_current_buf = function() return fixture.windows[fixture.current_win].buf end,
      nvim_get_current_tabpage = function() return fixture.current_tab end,
      nvim_list_tabpages = function()
        local tabs = {}
        for tab = 1, fixture.next_tab - 1 do
          if fixture.tabs[tab] and fixture.tabs[tab].valid then tabs[#tabs + 1] = tab end
        end
        return tabs
      end,
      nvim_tabpage_is_valid = function(tab) return fixture.tabs[tab] ~= nil and fixture.tabs[tab].valid end,
      nvim_tabpage_list_wins = function(tab)
        local windows = {}
        for win = 1, fixture.next_win - 1 do
          if fixture.windows[win] and fixture.windows[win].valid and fixture.windows[win].tab == tab then windows[#windows + 1] = win end
        end
        return windows
      end,
      nvim_set_current_tabpage = function(tab)
        assert(fixture.tabs[tab] and fixture.tabs[tab].valid, 'cannot focus an invalid tab')
        fixture.current_tab = tab
        for win = 1, fixture.next_win - 1 do
          if fixture.windows[win] and fixture.windows[win].valid and fixture.windows[win].tab == tab then
            fixture.current_win = win
            return
          end
        end
        error 'tab has no valid window'
      end,
      nvim_tabpage_close = function(tab)
        assert(fixture.tabs[tab] and fixture.tabs[tab].valid, 'cannot close an invalid tab')
        fixture.tabs[tab].valid = false
        for _, window in pairs(fixture.windows) do
          if window.tab == tab then window.valid = false end
        end
        if fixture.current_tab == tab then focus_first_valid_tab() end
      end,
      nvim_set_current_win = function(win)
        assert(fixture.windows[win] and fixture.windows[win].valid, 'cannot focus an invalid window')
        fixture.current_win = win
        fixture.current_tab = fixture.windows[win].tab
      end,
      nvim_win_get_tabpage = function(win) return assert(fixture.windows[win], 'unknown window').tab end,
      nvim_win_call = function(win, callback)
        assert(fixture.windows[win] and fixture.windows[win].valid, 'cannot call in an invalid window')
        local previous_win = fixture.current_win
        local previous_tab = fixture.current_tab
        fixture.current_win = win
        fixture.current_tab = fixture.windows[win].tab
        local result = callback()
        fixture.current_win = previous_win
        fixture.current_tab = previous_tab
        return result
      end,
      nvim_win_get_width = function(win)
        local window = assert(fixture.windows[win], 'unknown window')
        return window.host and fixture.geometry.width or window.config.width
      end,
      nvim_win_get_height = function(win)
        local window = assert(fixture.windows[win], 'unknown window')
        return window.host and fixture.geometry.height or window.config.height
      end,
      nvim_create_buf = function()
        local buf = fixture.next_buf
        fixture.next_buf = fixture.next_buf + 1
        fixture.buffers[buf] = true
        return buf
      end,
      nvim_buf_is_valid = function(buf) return fixture.buffers[buf] == true end,
      nvim_buf_delete = function(buf)
        fixture.buffers[buf] = false
        for _, window in pairs(fixture.windows) do
          if window.valid and window.buf == buf then window.buf = nil end
        end
      end,
      nvim_open_win = function(buf, enter, config)
        assert(fixture.buffers[buf], 'cannot open an invalid buffer')
        local win = fixture.next_win
        fixture.next_win = fixture.next_win + 1
        fixture.windows[win] = { valid = true, buf = buf, config = deepcopy(config), tab = fixture.current_tab }
        if enter then fixture.current_win = win end
        return win
      end,
      nvim_win_is_valid = function(win) return fixture.windows[win] ~= nil and fixture.windows[win].valid end,
      nvim_win_set_buf = function(win, buf)
        assert(fixture.windows[win] and fixture.windows[win].valid, 'cannot set a buffer in an invalid window')
        assert(fixture.buffers[buf], 'cannot show an invalid buffer')
        fixture.windows[win].buf = buf
      end,
      nvim_win_hide = function(win)
        fixture.windows[win].valid = false
        if fixture.current_win == win then fixture.current_win = 1 end
      end,
      nvim_win_set_config = function(win, config) fixture.windows[win].config = deepcopy(config) end,
      nvim_set_option_value = function() end,
      nvim_create_augroup = function() return 1 end,
      nvim_create_autocmd = function(event, autocmd_options)
        for _, name in ipairs(type(event) == 'table' and event or { event }) do
          fixture.autocmds[name] = fixture.autocmds[name] or {}
          fixture.autocmds[name][#fixture.autocmds[name] + 1] = autocmd_options.callback
        end
      end,
    },
  }

  function fixture.fire(event)
    for _, callback in ipairs(fixture.autocmds[event] or {}) do
      callback()
    end
  end

  function fixture.mapping(mode, lhs, buf) return fixture.mappings[mapping_key(mode, lhs, buf)] end

  function fixture.invoke(mode, lhs, buf)
    local mapping = fixture.mapping(mode, lhs, buf)
    assert(mapping, string.format('missing %s-mode mapping for %s', mode, lhs))
    return mapping.callback()
  end

  function fixture.surface()
    for win = fixture.next_win - 1, 2, -1 do
      local window = fixture.windows[win]
      if window and window.valid and not window.host then
        if not window.buf or not fixture.buffers[window.buf] then goto continue end
        return {
          kind = 'Tool Tab',
          win = win,
          buf = window.buf,
          width = window.config and window.config.width or fixture.geometry.width,
          height = window.config and window.config.height or fixture.geometry.height,
        }
      end
      ::continue::
    end
    return nil
  end

  function fixture.invalidate_surface_buffer()
    local surface = assert(fixture.surface(), 'expected a visible terminal surface')
    fixture.buffers[surface.buf] = false
    fixture.windows[surface.win].valid = false
    fixture.current_win = 1
    fixture.current_tab = fixture.windows[1].tab
    return surface.buf
  end

  function fixture.switch_tab() create_tab(true) end

  function fixture.exit_job(job_id)
    local job = assert(fixture.jobs[job_id], 'unknown job')
    job.running = false
    job.options.on_exit(job_id, 0, 'exit')
  end

  function fixture.run_deferred()
    local deferred = fixture.deferred
    fixture.deferred = {}
    for _, item in ipairs(deferred) do
      item.callback()
    end
  end

  function fixture.valid_buffer_count()
    local count = 0
    for _, valid in pairs(fixture.buffers) do
      if valid then count = count + 1 end
    end
    return count
  end

  return fake, fixture
end

local function setup(overrides, fake_options)
  local fake, fixture = fake_vim(fake_options)
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local config = {
    id = 'lazygit',
    command = { 'lazygit' },
    key = '<leader>gg',
    desc = 'Lazygit',
    handoff = 'return-and-acknowledge',
  }
  for name, value in pairs(overrides or {}) do
    config[name] = value
  end

  local result = terminal_tool.create(config)
  return fixture, terminal_tool, result
end

local function use_handoff_env(fixture, job_index)
  local env = fixture.job_attempts[job_index].options.env
  vim.env.DOTFILES_EDITOR_HANDOFF_SOURCE = env.DOTFILES_EDITOR_HANDOFF_SOURCE
  vim.env.DOTFILES_EDITOR_HANDOFF_GENERATION = env.DOTFILES_EDITOR_HANDOFF_GENERATION
end

check('declaration owns mappings without exposing lifecycle state', function()
  local fixture, _, result = setup()
  assert(result == nil, 'create exposed a controller instead of keeping lifecycle state private')
  assert(fixture.mapping('n', '<leader>gg'), 'expected create to install the normal-mode mapping')

  fixture.invoke('n', '<leader>gg')
  local surface = assert(fixture.surface(), 'expected a terminal surface')
  assert(not fixture.mapping('t', '<leader>gg', surface.buf), 'terminal mapping would delay ordinary Space input in the TUI')
end)

check('terminal job persists when its Tool Tab is left and revisited', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  local surface = assert(fixture.surface(), 'expected the first terminal surface')
  assert(#fixture.job_attempts == 1, 'expected one terminal job after opening the tool')

  fixture.invoke('n', '<leader>gg')
  fixture.invoke('n', '<leader>gg')

  assert(#fixture.job_attempts == 1, 'leaving and revisiting the Tool Tab started a second terminal job')
  assert(fixture.surface(), 'expected the Tool Tab to remain available')
end)

check('closing a Tool Tab natively preserves its buffer and job for the next invocation', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  local first = assert(fixture.surface(), 'expected the first Tool Tab')
  local first_tab = fixture.current_tab
  vim.api.nvim_tabpage_close(first_tab, false)

  assert(fixture.buffers[first.buf] and fixture.jobs[1].running, 'native tab closure ended the tool session')
  fixture.invoke('n', '<leader>gg')
  local reopened = assert(fixture.surface(), 'expected the Tool Tab to be recreated')
  assert(reopened.buf == first.buf, 'recreating the Tool Tab replaced its live terminal buffer')
  assert(fixture.current_tab ~= first_tab and #fixture.job_attempts == 1, 'recreating the Tool Tab restarted its job')
end)

check('switching Tool Tabs returns directly to the Host Window', function()
  local fixture, terminal_tool = setup()
  terminal_tool.create {
    id = 'hunk',
    command = { 'hunk' },
    key = '<leader>gd',
    desc = 'Hunk',
  }

  local host_win = fixture.current_win
  local host_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')
  local lazygit = assert(fixture.surface(), 'expected the Lazygit Tool Tab')
  local lazygit_tab = fixture.current_tab
  assert(lazygit_tab ~= host_tab, 'Lazygit replaced the Host Window instead of opening a Tool Tab')

  fixture.invoke('n', '<leader>gd')
  local hunk = assert(fixture.surface(), 'expected the Hunk Tool Tab')
  local hunk_tab = fixture.current_tab
  assert(hunk_tab ~= lazygit_tab, 'Hunk reused the Lazygit Tool Tab')
  assert(fixture.windows[lazygit.win].valid, 'switching tools destroyed the Lazygit Tool Tab')

  fixture.invoke('n', '<leader>gd')
  assert(fixture.current_win == host_win and fixture.current_tab == host_tab, 'hiding Hunk did not return directly to the Host Window')
  assert(fixture.windows[lazygit.win].valid and fixture.windows[hunk.win].valid, 'hiding Hunk destroyed a persistent Tool Tab')
  assert(fixture.jobs[1].running and fixture.jobs[2].running, 'switching Tool Tabs stopped a persistent job')
end)

check('a hidden tool restarts in a new effective working directory', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  local tool_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')
  fixture.cwd = '/repo/two'
  fixture.invoke('n', '<leader>gg')

  assert(#fixture.job_attempts == 2, 'new working directory reused the old repository process')
  assert(fixture.job_attempts[2].options.cwd == '/repo/two', 'replacement process did not start in the new directory')
  assert(fixture.current_tab == tool_tab, 'working-directory restart replaced the Tool Tab')
  assert(not fixture.jobs[1].running, 'old repository process was left running')
end)

check('tool-to-tool invocation derives its working directory from the Host Window', function()
  local fixture, terminal_tool = setup()
  terminal_tool.create {
    id = 'hunk',
    command = { 'hunk' },
    key = '<leader>gd',
    desc = 'Hunk',
  }
  fixture.invoke('n', '<leader>gg')
  fixture.windows[fixture.current_win].cwd = '/tool-local'
  fixture.windows[1].cwd = '/repo/two'

  fixture.invoke('n', '<leader>gd')
  assert(fixture.job_attempts[2].options.cwd == '/repo/two', 'Hunk inherited Lazygit tab state instead of the Host Window cwd')
end)

check('invoking an existing Tool Tab from a new Host Window selects it', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  local tool_tab = fixture.current_tab
  fixture.switch_tab()
  local new_host_win = fixture.current_win
  fixture.invoke('n', '<leader>gg')

  assert(fixture.current_tab == tool_tab, 'invocation did not select the existing Tool Tab')
  assert(#fixture.job_attempts == 1, 'selecting the Tool Tab restarted its terminal job')
  fixture.invoke('n', '<leader>gg')
  assert(fixture.current_win == new_host_win, 'the latest non-tool window did not become the Host Window')
end)

check('tool environment extends the shell-owned editor contract', function()
  local fixture = setup {
    env = { OPENTUI_GRAPHICS = 'false' },
  }
  fixture.invoke('n', '<leader>gg')
  local env = fixture.job_attempts[1].options.env

  assert(env.OPENTUI_GRAPHICS == 'false', 'expected the tool-specific environment variable')
  assert(env.DOTFILES_EDITOR_HANDOFF_SOURCE == 'lazygit', 'expected the tool id as the editor-handoff source')
  assert(env.EDITOR == 'nvim', 'expected the shell-owned editor')
  assert(env.VISUAL == 'nvim' and env.GIT_EDITOR == 'nvim', 'expected the complete shell-owned editor contract')
end)

check('reserved editor environment cannot be overridden', function()
  local ok, err = pcall(function() setup { env = { EDITOR = 'tool-specific-editor' } } end)
  assert(not ok and tostring(err):match 'cannot override EDITOR', 'expected an atomic configuration error for EDITOR')
end)

check('production declarations and flatten adapter share source-agnostic routing', function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local flatten_config
  local module_names = { 'custom.lib.terminal_tool', 'custom.lib.pack', 'flatten' }
  local previous_modules = {}
  for _, name in ipairs(module_names) do
    previous_modules[name] = package.loaded[name]
  end

  package.loaded['custom.lib.terminal_tool'] = terminal_tool
  package.loaded['custom.lib.pack'] = { gh = function(repository) return repository end }
  package.loaded.flatten = { setup = function(config) flatten_config = config end }

  local loaded, load_error = pcall(function()
    dofile(hunk_path)
    dofile(lazygit_path)
    dofile(flatten_path)
  end)
  for _, name in ipairs(module_names) do
    package.loaded[name] = previous_modules[name]
  end
  assert(loaded, load_error)
  assert(flatten_config and flatten_config.hooks, 'production flatten adapter did not register its hooks')

  fixture.invoke('n', '<leader>gd')
  assert(fixture.job_attempts[1].command[1] == 'hunk', 'production Hunk declaration registered the wrong command')
  assert(fixture.job_attempts[1].options.env.OPENTUI_GRAPHICS == 'false', 'production Hunk declaration lost its render fix')
  use_handoff_env(fixture, 1)
  local hunk_data = flatten_config.hooks.guest_data()
  assert(type(flatten_config.window.open) == 'function', 'production flatten adapter did not install Host Window routing')
  local hunk_file = vim.api.nvim_create_buf(true, false)
  flatten_config.hooks.pre_open { data = hunk_data }
  local hunk_buf, hunk_win = flatten_config.window.open { files = { { bufnr = hunk_file } }, data = hunk_data }
  flatten_config.hooks.post_open { data = hunk_data }
  assert(
    hunk_buf == hunk_file and hunk_win == 1 and fixture.current_win == 1 and #fixture.deferred == 0,
    'production Hunk handoff did not return to the Host Window'
  )
  assert(fixture.surface(), 'production Hunk handoff destroyed its Tool Tab')

  fixture.invoke('n', '<leader>gg')
  assert(fixture.job_attempts[2].command[1] == 'lazygit', 'production Lazygit declaration registered the wrong command')
  use_handoff_env(fixture, 2)
  local lazygit_data = flatten_config.hooks.guest_data()
  local lazygit_file = vim.api.nvim_create_buf(true, false)
  flatten_config.hooks.pre_open { data = lazygit_data }
  local lazygit_buf, lazygit_win = flatten_config.window.open { files = { { bufnr = lazygit_file } }, data = lazygit_data }
  flatten_config.hooks.post_open { data = lazygit_data }
  assert(
    lazygit_buf == lazygit_file and lazygit_win == 1 and fixture.current_win == 1 and #fixture.deferred == 1,
    'production Lazygit handoff did not return and schedule acknowledgement'
  )
  assert(fixture.surface(), 'production Lazygit handoff destroyed its Tool Tab')
  fixture.run_deferred()
  assert(#fixture.sends == 1 and fixture.sends[1].job == 2, 'production Lazygit handoff acknowledged the wrong job')
end)

check('production flatten adapter preserves first-file focus and routes diffs to the Host Window', function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local flatten_config
  local module_names = { 'custom.lib.terminal_tool', 'custom.lib.pack', 'flatten' }
  local previous_modules = {}
  for _, name in ipairs(module_names) do
    previous_modules[name] = package.loaded[name]
  end

  package.loaded['custom.lib.terminal_tool'] = terminal_tool
  package.loaded['custom.lib.pack'] = { gh = function(repository) return repository end }
  package.loaded.flatten = { setup = function(config) flatten_config = config end }
  local loaded, load_error = pcall(function()
    dofile(hunk_path)
    dofile(flatten_path)
  end)
  for _, name in ipairs(module_names) do
    package.loaded[name] = previous_modules[name]
  end
  assert(loaded, load_error)

  fixture.invoke('n', '<leader>gd')
  use_handoff_env(fixture, 1)
  local data = flatten_config.hooks.guest_data()
  local first = vim.api.nvim_create_buf(true, false)
  local second = vim.api.nvim_create_buf(true, false)
  flatten_config.hooks.pre_open { data = data }
  local normal_buf, normal_win = flatten_config.window.open {
    files = { { bufnr = first }, { bufnr = second } },
    data = data,
  }
  assert(normal_buf == first and normal_win == 1, 'multi-file handoff did not preserve flatten first-file focus')

  fixture.invoke('n', '<leader>gd')
  flatten_config.hooks.pre_open { data = data }
  local diff_win, diff_buf = flatten_config.window.diff {
    files = { { bufnr = first }, { bufnr = second } },
  }
  assert(diff_buf == second and fixture.windows[diff_win].tab == 1, 'diff-mode handoff did not open in the Host Window tab')
  assert(fixture.current_tab == 1, 'diff-mode handoff left the originating Tool Tab current')
end)

check('editor handoff is source-agnostic and acknowledges only configured tools', function()
  local fixture, terminal_tool = setup()
  fixture.invoke('n', '<leader>gg')
  use_handoff_env(fixture, 1)

  local data = terminal_tool.editor_handoff_data()
  assert(terminal_tool.complete_editor_handoff(data), 'expected the registered source to handle editor return')
  assert(fixture.current_win == 1 and fixture.surface(), 'editor return did not select the Host Window and preserve the Tool Tab')
  assert(#fixture.sends == 0, 'editor acknowledgement ignored its delay')

  fixture.run_deferred()
  assert(#fixture.sends == 1 and fixture.sends[1].input == '\r', 'expected one delayed editor acknowledgement')
  assert(not terminal_tool.complete_editor_handoff {}, 'unknown handoff data should be ignored')
end)

check('return-only editor handoff does not send terminal input', function()
  local fixture, terminal_tool = setup { id = 'hunk', handoff = 'return' }
  fixture.invoke('n', '<leader>gg')
  use_handoff_env(fixture, 1)

  assert(terminal_tool.complete_editor_handoff(terminal_tool.editor_handoff_data()), 'expected Hunk handoff to be handled')
  assert(fixture.current_win == 1 and fixture.surface(), 'return-only handoff did not select the Host Window and preserve the Tool Tab')
  fixture.run_deferred()
  assert(#fixture.sends == 0, 'hide-only handoff sent terminal input')
end)

check('failed job startup rolls back and remains retryable', function()
  for _, job_result in ipairs { -1, 0 } do
    local fixture = setup(nil, { job_results = { job_result } })
    assert(not fixture.invoke('n', '<leader>gg'), 'expected the first launch to report failure')
    assert(fixture.surface() == nil, 'failed startup left a blank float')
    assert(fixture.valid_buffer_count() == 0, 'failed startup leaked its provisional buffer')
    assert(#fixture.notifications == 1, 'missing startup error notification')

    assert(fixture.invoke('n', '<leader>gg'), 'expected a later mapping invocation to retry')
    assert(#fixture.job_attempts == 2 and fixture.surface(), 'startup failure left the declaration unusable')
  end
end)

check('failed tool-to-tool startup preserves the source Tool Tab', function()
  local fixture, terminal_tool = setup(nil, { job_results = { 1, -1 } })
  terminal_tool.create {
    id = 'hunk',
    command = { 'hunk' },
    key = '<leader>gd',
    desc = 'Hunk',
  }
  fixture.invoke('n', '<leader>gg')
  local lazygit_tab = fixture.current_tab

  assert(not fixture.invoke('n', '<leader>gd'), 'expected Hunk startup to fail')
  assert(fixture.current_tab == lazygit_tab, 'failed Hunk startup moved away from the Lazygit Tool Tab')
  assert(fixture.jobs[1].running, 'failed Hunk startup stopped Lazygit')
end)

check('tool exit removes its Tool Tab and returns to the Host Window', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  local tool_tab = fixture.current_tab
  local tool_buf = assert(fixture.surface()).buf

  fixture.exit_job(1)
  assert(not fixture.tabs[tool_tab].valid, 'exited tool left its Tool Tab open')
  assert(not fixture.buffers[tool_buf], 'exited tool left its terminal buffer loaded')
  assert(fixture.current_win == 1, 'exited tool did not return to the Host Window')
end)

check('a missing Host Window recovers to a new ordinary tab', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  local tool_tab = fixture.current_tab
  vim.api.nvim_tabpage_close(1, false)

  fixture.invoke('n', '<leader>gg')
  assert(fixture.current_tab ~= tool_tab, 'the Tool Tab became its own Host Window')
  assert(fixture.windows[fixture.current_win].buf == nil, 'Host Window recovery did not create an empty ordinary window')
  assert(fixture.jobs[1].running, 'Host Window recovery stopped the tool job')
end)

check('a job that exits during startup cannot restore stale handles', function()
  local fixture = setup(nil, { synchronous_exits = { true } })
  assert(not fixture.invoke('n', '<leader>gg'), 'synchronously exited job reported a live terminal')
  assert(fixture.surface() == nil and fixture.valid_buffer_count() == 0, 'synchronously exited job leaked its surface')

  assert(fixture.invoke('n', '<leader>gg'), 'declaration did not recover after the short-lived job')
  assert(#fixture.job_attempts == 2 and fixture.surface(), 'short-lived job restored stale lifecycle handles')
end)

check('an old exit callback cannot clear a replacement generation', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  fixture.invalidate_surface_buffer()
  fixture.invoke('n', '<leader>gg')
  assert(#fixture.job_attempts == 2, 'expected a replacement terminal job')

  fixture.exit_job(1)
  local replacement = assert(fixture.surface(), 'old exit callback hid the replacement surface')
  assert(replacement.buf, 'expected a replacement terminal buffer')
  fixture.invoke('n', '<leader>gg')
  fixture.invoke('n', '<leader>gg')

  assert(#fixture.job_attempts == 2, 'old exit callback caused the replacement to restart')
  assert(fixture.surface(), 'replacement terminal could not reopen')
end)

check('a delayed acknowledgement cannot reach a replacement job', function()
  local fixture, terminal_tool = setup()
  fixture.invoke('n', '<leader>gg')
  use_handoff_env(fixture, 1)
  terminal_tool.complete_editor_handoff(terminal_tool.editor_handoff_data())

  -- Reopen, invalidate the old generation, and launch its replacement before
  -- the delayed acknowledgement fires.
  fixture.invoke('n', '<leader>gg')
  fixture.invalidate_surface_buffer()
  fixture.invoke('n', '<leader>gg')
  fixture.run_deferred()

  assert(#fixture.sends == 0, 'the old acknowledgement sent input to the replacement job')
end)

check('a stale editor handoff cannot redirect a replacement generation', function()
  local fixture, terminal_tool = setup()
  fixture.invoke('n', '<leader>gg')
  use_handoff_env(fixture, 1)
  local stale_data = terminal_tool.editor_handoff_data()

  fixture.invalidate_surface_buffer()
  fixture.invoke('n', '<leader>gg')
  assert(not terminal_tool.complete_editor_handoff(stale_data), 'stale handoff was accepted for a replacement generation')
  assert(fixture.surface(), 'stale handoff hid the replacement surface')
end)

check('host tmux remains upstream for prefix navigation', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')

  for _, attempt in ipairs(fixture.job_attempts) do
    assert(attempt.command[1] ~= 'tmux', 'terminal_tool launched a nested tmux surface')
  end
  assert(fixture.surface() and fixture.surface().kind == 'Tool Tab', 'expected the terminal tool inside host Neovim')
end)

_G.vim = real_vim

if #failures > 0 then
  io.stderr:write(string.format('\n%d terminal_tool regression check%s failed\n', #failures, #failures == 1 and '' or 's'))
  os.exit(1)
end

io.stdout:write '\nterminal_tool regression checks passed\n'
