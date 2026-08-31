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
  local vim_did_enter = options.vim_did_enter
  if vim_did_enter == nil then vim_did_enter = 1 end
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
    buffer_results = real_vim.deepcopy(options.buffer_results or {}),
    synchronous_exits = real_vim.deepcopy(options.synchronous_exits or {}),
    mapping_results = real_vim.deepcopy(options.mapping_results or {}),
    command_results = real_vim.deepcopy(options.command_results or {}),
    job_attempts = {},
    jobs = {},
    waits = {},
    mappings = {},
    user_commands = real_vim.deepcopy(options.user_commands or {}),
    scheduled = {},
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
    v = { vim_did_enter = vim_did_enter },
    cmd = {
      diffthis = function() end,
      startinsert = function() end,
      tabnew = function() create_tab(false) end,
    },
    fs = {
      normalize = function(path) return path end,
    },
    uv = {
      fs_realpath = function(path) return (options.realpaths or {})[path] or path end,
    },
    pack = { add = function() end },
    deepcopy = deepcopy,
    schedule = function(callback)
      if options.queue_schedules then
        fixture.scheduled[#fixture.scheduled + 1] = callback
      else
        callback()
      end
    end,
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
        if table.remove(fixture.mapping_results, 1) == false then error 'injected mapping registration failure' end
        local buf = map_options and map_options.buf or nil
        fixture.mappings[mapping_key(mode, lhs, buf)] = {
          callback = callback,
          options = deepcopy(map_options or {}),
        }
      end,
      del = function(mode, lhs, map_options)
        local buf = map_options and map_options.buffer or nil
        fixture.mappings[mapping_key(mode, lhs, buf)] = nil
      end,
    },
    fn = {
      getcwd = function() return fixture.windows[fixture.current_win].cwd or fixture.cwd end,
      maparg = function(lhs, mode, abbreviation, dictionary)
        assert(abbreviation == false and dictionary == true, 'the fake only supports dictionary mapping lookup')
        local mapping = fixture.mappings[mapping_key(mode, lhs, nil)]
        if mapping == nil then return {} end
        return {
          callback = mapping.callback,
          desc = mapping.options.desc,
          lhs = lhs,
          mode = mode,
        }
      end,
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
      jobwait = function(job_ids, timeout)
        fixture.waits[#fixture.waits + 1] = {
          jobs = deepcopy(job_ids),
          timeout = timeout,
        }
        local statuses = {}
        for _, job_id in ipairs(job_ids) do
          local job = fixture.jobs[job_id]
          statuses[#statuses + 1] = job and not job.running and 0 or -1
        end
        return statuses
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
      nvim_tabpage_close = function(tab, _)
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
        local result = table.remove(fixture.buffer_results, 1)
        if result == false then error 'provisional buffer failure' end
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
      nvim_get_commands = function(command_options)
        assert(command_options.builtin == false, 'the fake only supports querying user commands')
        return deepcopy(fixture.user_commands)
      end,
      nvim_create_user_command = function(name, callback, command_options)
        assert(name:match '^[A-Z][A-Za-z0-9]*$' and name ~= 'Next', 'invalid user command name: ' .. name)
        if table.remove(fixture.command_results, 1) == false then error 'injected command registration failure' end
        assert(command_options.force ~= false or fixture.user_commands[name] == nil, 'user command already exists: ' .. name)
        fixture.user_commands[name] = {
          callback = callback,
          options = deepcopy(command_options or {}),
        }
      end,
      nvim_del_user_command = function(name)
        assert(fixture.user_commands[name] ~= nil, 'user command does not exist: ' .. name)
        fixture.user_commands[name] = nil
      end,
    },
  }

  function fixture.fire(event)
    if event == 'UIEnter' then fake.v.vim_did_enter = 1 end
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

  function fixture.invoke_command(name)
    local command = assert(fixture.user_commands[name], 'missing user command :' .. name)
    return command.callback {}
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

  function fixture.run_scheduled()
    local scheduled = fixture.scheduled
    fixture.scheduled = {}
    for _, callback in ipairs(scheduled) do
      callback()
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
  vim.env.DOTFILES_EDITOR_HANDOFF_INSTANCE = env.DOTFILES_EDITOR_HANDOFF_INSTANCE
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

check('a variant Ex command and key invoke the exact same toggle', function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local result = terminal_tool.create {
    id = 'hunk',
    variants = {
      { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
      { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk diff (staged)' },
    },
  }
  local mapping = assert(fixture.mapping('n', '<leader>gd'), 'expected create to install the normal-mode mapping')
  local command = assert(fixture.user_commands.HunkReview, 'expected create to install the Ex command')

  assert(result == nil, 'create exposed a controller after registering an Ex command')
  assert(mapping.callback == command.callback, 'the Ex command and key were wired to different toggle callbacks')
  assert(command.options.force == false, 'the Ex command could overwrite a command registered after preflight')
  fixture.invoke_command 'HunkReview'
  assert(#fixture.job_attempts == 1, 'the Ex command did not launch the declared tool')
  assert(table.concat(fixture.job_attempts[1].command, ' ') == 'hunk diff', 'the Ex command launched the wrong argv')
end)

check('a startup Ex command waits for the UI and coalesces repeated requests', function()
  -- VimEnter sets vim_did_enter before the builtin TUI emits UIEnter.
  local fake, fixture = fake_vim { vim_did_enter = 0, queue_schedules = true }
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  terminal_tool.create {
    id = 'hunk',
    variants = {
      { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
      { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk diff (staged)' },
    },
  }
  local mapping = assert(fixture.mapping('n', '<leader>gd'), 'expected create to install the normal-mode mapping')
  local command = assert(fixture.user_commands.HunkReview, 'expected create to install the Ex command')

  assert(mapping.callback == command.callback, 'startup handling split the shared key and Ex-command callback')
  fake.v.vim_did_enter = 1
  fixture.invoke_command 'HunkReview'
  fixture.invoke_command 'HunkReview'
  assert(#fixture.job_attempts == 0, 'the startup Ex command launched before Neovim entered the UI')

  fixture.fire 'UIEnter'
  assert(#fixture.job_attempts == 0, 'the startup Ex command launched inside UIEnter instead of on the next scheduled tick')
  fixture.invoke_command 'HunkReview'
  assert(#fixture.job_attempts == 0, 'a request bypassed the pending launch between UIEnter and the scheduled tick')
  fixture.run_scheduled()

  assert(#fixture.job_attempts == 1, 'repeated startup requests did not coalesce to one launch')
  assert(table.concat(fixture.job_attempts[1].command, ' ') == 'hunk diff', 'the deferred Ex command launched the wrong argv')
  assert(fixture.current_win ~= 1, 'repeated startup requests toggled the Tool Tab closed after launch')
end)

check('variant Ex commands must be usable Neovim user-command names', function()
  for _, ex_command in ipairs { 'hunkReview', 'Hunk_Review', 'Hunk Review', 'Next' } do
    local fake, fixture = fake_vim()
    _G.vim = fake
    local terminal_tool = dofile(terminal_tool_path)
    local ok, err = pcall(
      function()
        terminal_tool.create {
          id = 'hunk',
          variants = {
            { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = ex_command },
            { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged' },
          },
        }
      end
    )

    assert(not ok and tostring(err):match 'Ex command', ex_command .. ' did not fail with an Ex-command declaration error')
    assert(fixture.mapping('n', '<leader>gd') == nil, ex_command .. ' left a partial mapping')
    assert(fixture.user_commands[ex_command] == nil, ex_command .. ' left a partial command')
  end
end)

check('variant Ex commands are unique within a declaration', function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
          { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged', ex_command = 'HunkReview' },
        },
      }
    end
  )

  assert(not ok and tostring(err):match 'more than once', 'a repeated Ex command did not fail during preflight')
  assert(fixture.mapping('n', '<leader>gd') == nil and fixture.mapping('n', '<leader>gD') == nil, 'a repeated Ex command left mappings')
  assert(fixture.user_commands.HunkReview == nil, 'a repeated Ex command was registered')
end)

check('variant Ex commands cannot claim an existing Neovim command', function()
  local existing_callback = function() return 'existing' end
  local fake, fixture = fake_vim {
    user_commands = { HunkReview = { callback = existing_callback, options = {} } },
  }
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
          { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged' },
        },
      }
    end
  )

  assert(not ok and tostring(err):match 'already registered', 'an existing Neovim command did not block the declaration')
  assert(fixture.user_commands.HunkReview.callback == existing_callback, 'the existing Neovim command was overwritten')
  assert(fixture.mapping('n', '<leader>gd') == nil and fixture.mapping('n', '<leader>gD') == nil, 'the rejected declaration left mappings')
end)

check("a variant Ex command cannot collide with another tool's command", function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  terminal_tool.create {
    id = 'hunk',
    variants = {
      { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
      { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged' },
    },
  }

  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'other',
        variants = {
          { command = { 'other', 'review' }, key = '<leader>or', desc = 'Other review', ex_command = 'HunkReview' },
          { command = { 'other', 'status' }, key = '<leader>os', desc = 'Other status' },
        },
      }
    end
  )

  assert(not ok and tostring(err):match 'already registered by hunk', 'a cross-tool Ex command collision was not attributed to its owner')
  assert(fixture.mapping('n', '<leader>or') == nil and fixture.mapping('n', '<leader>os') == nil, 'the rejected second tool left mappings')
  assert(fixture.user_commands.HunkReview.callback == fixture.mapping('n', '<leader>gd').callback, 'the first tool lost its command')
end)

check('registration failures leave no partial Ex commands or mappings', function()
  local failure_options = {
    { command_results = { true, false } },
    { mapping_results = { true, false } },
  }

  for _, options in ipairs(failure_options) do
    local fake, fixture = fake_vim(options)
    _G.vim = fake
    local terminal_tool = dofile(terminal_tool_path)
    local ok = pcall(
      function()
        terminal_tool.create {
          id = 'hunk',
          variants = {
            { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
            { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged', ex_command = 'HunkStagedReview' },
          },
        }
      end
    )

    assert(not ok, 'the injected registration failure unexpectedly succeeded')
    assert(next(fixture.user_commands) == nil, 'a failed declaration left a partial Ex command')
    assert(fixture.mapping('n', '<leader>gd') == nil and fixture.mapping('n', '<leader>gD') == nil, 'a failed declaration left a partial mapping')

    local retry_ok, retry_error = pcall(
      function()
        terminal_tool.create {
          id = 'hunk',
          variants = {
            { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
            { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged', ex_command = 'HunkStagedReview' },
          },
        }
      end
    )
    assert(retry_ok, 'a failed declaration could not be retried: ' .. tostring(retry_error))
  end
end)

check('terminal job persists when its Tool Tab is left and revisited', function()
  local fixture = setup()
  fixture.invoke('n', '<leader>gg')
  assert(fixture.surface(), 'expected the first terminal surface')
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

check('a singleton restarts when effective cwd aliases change', function()
  local fixture = setup(nil, { realpaths = { ['/repo/link'] = '/repo/one' } })
  fixture.invoke('n', '<leader>gg')
  local tool_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')
  fixture.cwd = '/repo/link'
  fixture.invoke('n', '<leader>gg')

  assert(#fixture.job_attempts == 2, 'singleton alias change did not preserve raw-cwd restart behavior')
  assert(fixture.job_attempts[2].options.cwd == '/repo/link', 'singleton launched from a canonical path instead of its effective cwd')
  assert(fixture.current_tab == tool_tab, 'singleton alias restart replaced its Tool Tab')
  assert(not fixture.jobs[1].running, 'singleton alias restart left its old process running')
end)

check('a per-cwd declaration keeps one live Tool Tab per Host Window directory', function()
  local fixture = setup { instances = 'cwd' }
  fixture.invoke('n', '<leader>gg')
  local first = assert(fixture.surface(), 'expected the first per-cwd Tool Tab')
  local first_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')

  fixture.switch_tab()
  local second_host = fixture.current_win
  fixture.windows[second_host].cwd = '/repo/two'
  fixture.invoke('n', '<leader>gg')
  local second_tab = fixture.current_tab

  assert(second_tab ~= first_tab, 'the second cwd replaced the first Tool Tab')
  assert(#fixture.job_attempts == 2, 'the second cwd did not start its own terminal job')
  assert(fixture.job_attempts[1].options.cwd == '/repo/one', 'the first instance started in the wrong cwd')
  assert(fixture.job_attempts[2].options.cwd == '/repo/two', 'the second instance started in the wrong cwd')
  assert(fixture.jobs[1].running and fixture.jobs[2].running, 'starting the second cwd stopped a live instance')

  fixture.invoke('n', '<leader>gg')
  vim.api.nvim_set_current_win(1)
  fixture.invoke('n', '<leader>gg')

  assert(fixture.current_tab == first_tab, 'returning to the first cwd did not select its Tool Tab')
  assert(fixture.windows[fixture.current_win].buf == first.buf, 'returning to the first cwd selected the wrong terminal buffer')
  assert(#fixture.job_attempts == 2, 'returning to the first cwd restarted its terminal job')
end)

check('per-cwd instances collapse filesystem aliases to one canonical directory', function()
  local fixture = setup({ instances = 'cwd' }, { realpaths = { ['/repo/link'] = '/repo/one' } })
  fixture.invoke('n', '<leader>gg')
  local first_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')

  fixture.switch_tab()
  fixture.windows[fixture.current_win].cwd = '/repo/link'
  fixture.invoke('n', '<leader>gg')

  assert(fixture.current_tab == first_tab, 'a filesystem alias created a duplicate Tool Tab')
  assert(#fixture.job_attempts == 1 and fixture.jobs[1].running, 'a filesystem alias restarted the canonical instance')
end)

check('closing one per-cwd Tool Tab preserves both live jobs and can recreate only that tab', function()
  local fixture = setup { instances = 'cwd' }
  fixture.invoke('n', '<leader>gg')
  local first_tab = fixture.current_tab
  local first_buf = fixture.windows[fixture.current_win].buf
  fixture.invoke('n', '<leader>gg')

  fixture.switch_tab()
  local second_host = fixture.current_win
  fixture.windows[second_host].cwd = '/repo/two'
  fixture.invoke('n', '<leader>gg')
  local second_tab = fixture.current_tab
  local second_buf = fixture.windows[fixture.current_win].buf
  fixture.invoke('n', '<leader>gg')

  vim.api.nvim_tabpage_close(first_tab, false)
  vim.api.nvim_set_current_win(1)
  fixture.invoke('n', '<leader>gg')

  assert(fixture.current_tab ~= first_tab, 'the natively closed Tool Tab was not recreated')
  assert(fixture.windows[fixture.current_win].buf == first_buf, 'recreating one cwd replaced its terminal buffer')
  assert(fixture.tabs[second_tab].valid, 'recreating one cwd closed the other Tool Tab')
  assert(fixture.buffers[second_buf], 'the other cwd lost its buffer')
  assert(#fixture.job_attempts == 2 and fixture.jobs[1].running and fixture.jobs[2].running, 'recreating one tab restarted or stopped a job')
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

local function setup_variants(overrides, fake_options)
  local fake, fixture = fake_vim(fake_options)
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local config = {
    id = 'hunk',
    env = { OPENTUI_GRAPHICS = 'false' },
    variants = {
      { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' },
      { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk diff (staged)' },
    },
  }
  for name, value in pairs(overrides or {}) do
    config[name] = value
  end

  terminal_tool.create(config)
  return fixture, terminal_tool
end

local function launched(fixture, index) return table.concat(fixture.job_attempts[index].command, ' ') end

local function load_production_hunk(review_env)
  local fake, fixture = fake_vim()
  for name, value in pairs(review_env or {}) do
    fake.env[name] = value
  end
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local previous = package.loaded['custom.lib.terminal_tool']
  package.loaded['custom.lib.terminal_tool'] = terminal_tool
  local loaded, load_error = pcall(dofile, hunk_path)
  package.loaded['custom.lib.terminal_tool'] = previous
  return fixture, loaded, load_error
end

check('input variants share one Tool Tab and one process slot', function()
  local fixture = setup_variants()
  fixture.invoke('n', '<leader>gd')
  local worktree = assert(fixture.surface(), 'expected the Hunk Tool Tab')
  local tool_tab = fixture.current_tab
  assert(launched(fixture, 1) == 'hunk diff', 'working-tree variant launched the wrong command')

  fixture.invoke('n', '<leader>gD')
  assert(#fixture.job_attempts == 2, 'selecting the staged variant did not restart the tool')
  assert(launched(fixture, 2) == 'hunk diff --staged', 'staged variant launched the wrong command')
  assert(fixture.current_tab == tool_tab, 'switching variants replaced the Tool Tab')
  assert(not fixture.jobs[1].running, 'switching variants left the previous process running')
  assert(not fixture.buffers[worktree.buf], 'switching variants leaked the previous terminal buffer')
  assert(fixture.surface(), 'switching variants lost the terminal surface')

  fixture.invoke('n', '<leader>gd')
  assert(launched(fixture, 3) == 'hunk diff', 'switching back did not restore the working-tree command')
end)

check('each variant key toggles only its own running input', function()
  local fixture = setup_variants()
  fixture.invoke('n', '<leader>gd')
  local host_win = 1

  -- The other variant's key selects its input rather than hiding the tab.
  fixture.invoke('n', '<leader>gD')
  assert(fixture.current_tab ~= fixture.windows[host_win].tab, 'the staged key hid the Tool Tab instead of selecting its input')

  fixture.invoke('n', '<leader>gD')
  assert(fixture.current_win == host_win, 'the running variant key did not return to the Host Window')
  assert(#fixture.job_attempts == 2, 'hiding the Tool Tab restarted the tool')

  fixture.invoke('n', '<leader>gD')
  assert(#fixture.job_attempts == 2, 'reselecting the running variant restarted its process')
end)

check('variants share the tool environment and handoff identity', function()
  local fixture, terminal_tool = setup_variants()
  fixture.invoke('n', '<leader>gD')
  local env = fixture.job_attempts[1].options.env

  assert(env.OPENTUI_GRAPHICS == 'false', 'staged variant lost the shared tool environment')
  assert(env.DOTFILES_EDITOR_HANDOFF_SOURCE == 'hunk', 'variants did not share one editor-handoff source')
  use_handoff_env(fixture, 1)
  assert(terminal_tool.complete_editor_handoff(terminal_tool.editor_handoff_data()), 'staged variant could not complete editor handoff')
  assert(fixture.surface(), 'staged variant handoff destroyed its Tool Tab')
end)

check('every variant honors one shared handoff policy', function()
  local fixture, terminal_tool = setup_variants { handoff = 'return-and-acknowledge' }
  fixture.invoke('n', '<leader>gD')
  use_handoff_env(fixture, 1)

  assert(terminal_tool.complete_editor_handoff(terminal_tool.editor_handoff_data()), 'expected the staged variant handoff to be handled')
  fixture.run_deferred()
  assert(#fixture.sends == 1, 'a non-first variant silently lost the shared acknowledgement policy')
end)

check('each variant key carries its own description', function()
  local fixture = setup_variants()
  local worktree = assert(fixture.mapping('n', '<leader>gd'), 'expected the working-tree mapping')
  local staged = assert(fixture.mapping('n', '<leader>gD'), 'expected the staged mapping')

  assert(worktree.options.desc == 'Hunk diff', 'working-tree key lost its own which-key description')
  assert(staged.options.desc == 'Hunk diff (staged)', 'staged key did not get its own which-key description')
end)

check('a failed launch names the requested input, not the running one', function()
  -- Rollback clears the running variant before the message is built, so a
  -- lifecycle-derived label would misattribute the failure.
  local fixture = setup_variants(nil, { job_results = { -1 } })
  assert(not fixture.invoke('n', '<leader>gD'), 'expected the staged launch to fail')
  assert(
    fixture.notifications[1].message:match '^Hunk diff %(staged%)',
    'failed staged launch was attributed to another input: ' .. fixture.notifications[1].message
  )

  local running = setup_variants()
  running.invoke('n', '<leader>gD')
  running.invoke('n', '<leader>gD')
  vim.fn.getcwd = function() error 'no working directory' end
  assert(not running.invoke('n', '<leader>gd'), 'expected the working-tree request to fail')
  assert(
    running.notifications[#running.notifications].message:match '^Hunk diff:',
    'failure named the previously running input instead of the requested one: ' .. running.notifications[#running.notifications].message
  )
end)

check('a failed variant switch tears down cleanly and stays retryable', function()
  local fixture = setup_variants(nil, { job_results = { 1, -1 } })
  fixture.invoke('n', '<leader>gd')
  assert(fixture.surface(), 'expected the working-tree Tool Tab')

  assert(not fixture.invoke('n', '<leader>gD'), 'expected the staged switch to fail')
  assert(not fixture.jobs[1].running, 'failed switch left the replaced process running')
  assert(fixture.valid_buffer_count() == 0, 'failed switch leaked a terminal buffer')
  assert(fixture.current_win == 1, 'failed switch did not return to the Host Window')

  assert(fixture.invoke('n', '<leader>gD'), 'failed switch left the tool unusable')
  assert(launched(fixture, 3) == 'hunk diff --staged', 'retry after a failed switch launched the wrong input')
end)

check('a variant selected from another tool inherits the Host Window directory', function()
  local fixture, terminal_tool = setup_variants()
  terminal_tool.create { id = 'lazygit', command = { 'lazygit' }, key = '<leader>gg', desc = 'Lazygit' }
  fixture.invoke('n', '<leader>gg')
  fixture.windows[fixture.current_win].cwd = '/tool-local'
  fixture.windows[1].cwd = '/repo/two'

  fixture.invoke('n', '<leader>gD')
  assert(fixture.job_attempts[2].options.cwd == '/repo/two', 'a variant inherited another tool tab state instead of the Host Window cwd')
  assert(fixture.jobs[1].running, 'selecting a variant stopped an unrelated tool')
end)

check('a variant switch recovers from an invalidated terminal buffer', function()
  local fixture = setup_variants()
  fixture.invoke('n', '<leader>gd')
  fixture.invalidate_surface_buffer()

  assert(fixture.invoke('n', '<leader>gD'), 'expected the staged variant to recover the tool')
  assert(launched(fixture, 2) == 'hunk diff --staged', 'recovery launched the wrong input')
  assert(fixture.surface(), 'recovery did not produce a terminal surface')
end)

check('a gap or named entry in variants is rejected instead of dropping an input', function()
  local fake = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local worktree = { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' }
  local staged = { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged' }

  local named_ok, named_err = pcall(function() terminal_tool.create { id = 'hunk', variants = { worktree, staged_input = staged } } end)
  assert(not named_ok and tostring(named_err):match 'gapless', 'a named variants entry was silently dropped')

  local gap_ok, gap_err = pcall(function() terminal_tool.create { id = 'hunk2', variants = { [1] = worktree, [3] = staged } } end)
  assert(not gap_ok and tostring(gap_err):match 'gapless', 'a gap in variants silently dropped an input')
end)

check('a one-element variants list and duplicate commands are rejected', function()
  local fake = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)

  local single_ok, single_err = pcall(
    function() terminal_tool.create { id = 'hunk', variants = { { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' } } } end
  )
  assert(not single_ok and tostring(single_err):match 'top%-level command', 'a one-element variants list duplicated the single-command shape')

  local duplicate_ok, duplicate_err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk2',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' },
          { command = { 'hunk', 'diff' }, key = '<leader>gD', desc = 'Hunk again' },
        },
      }
    end
  )
  assert(not duplicate_ok and tostring(duplicate_err):match 'same command', 'two variants declared an identical command')
end)

check('a declaration without a command or variants fails clearly', function()
  local fake = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local ok, err = pcall(function() terminal_tool.create { id = 'hunk', key = '<leader>gd', desc = 'Hunk' } end)
  assert(not ok and tostring(err):match 'command or a variants list', "a typo'd variants field produced a misleading error: " .. tostring(err))
end)

check("a variant key cannot collide with another tool's key", function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  terminal_tool.create { id = 'lazygit', command = { 'lazygit' }, key = '<leader>gg', desc = 'Lazygit' }

  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' },
          { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gg', desc = 'Hunk staged' },
        },
      }
    end
  )
  assert(not ok and tostring(err):match 'already registered', 'expected a configuration error for a cross-tool key collision')

  -- A rejected declaration must not reserve the keys it had already mapped.
  local retry_ok = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' },
          { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged' },
        },
      }
    end
  )
  assert(retry_ok, 'a rejected declaration left its keys registered and blocked a corrected retry')
  assert(fixture.invoke('n', '<leader>gD'), 'the corrected declaration could not launch')
end)

check('a declaration cannot overwrite an existing Neovim mapping', function()
  local fake, fixture = fake_vim()
  local existing_callback = function() return 'existing mapping' end
  fake.keymap.set('n', '<leader>gd', existing_callback, { desc = 'Existing mapping' })
  local existing_mapping = fixture.mapping('n', '<leader>gd')
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)

  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff', ex_command = 'HunkReview' },
          { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gD', desc = 'Hunk staged' },
        },
      }
    end
  )

  assert(not ok and tostring(err):match 'already mapped', 'an existing Neovim mapping did not block the declaration')
  local preserved = fixture.mapping('n', '<leader>gd')
  assert(preserved == existing_mapping, 'the rejected declaration replaced the existing mapping record')
  assert(preserved.callback == existing_callback, 'the rejected declaration changed the existing mapping callback')
  assert(preserved.options.desc == 'Existing mapping', 'the rejected declaration changed the existing mapping options')
  assert(fixture.user_commands.HunkReview == nil, 'a mapping collision left a partial Ex command')
end)

check('a declaration cannot repeat a variant key', function()
  local fake = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        variants = {
          { command = { 'hunk', 'diff' }, key = '<leader>gd', desc = 'Hunk diff' },
          { command = { 'hunk', 'diff', '--staged' }, key = '<leader>gd', desc = 'Hunk staged' },
        },
      }
    end
  )
  assert(not ok and tostring(err):match 'more than once', 'expected a configuration error for a repeated variant key')
end)

check('variants cannot be mixed with a top-level command', function()
  local fake = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local ok, err = pcall(
    function()
      terminal_tool.create {
        id = 'hunk',
        command = { 'hunk' },
        key = '<leader>gd',
        desc = 'Hunk',
        variants = { { command = { 'hunk', 'diff' }, key = '<leader>gD', desc = 'Hunk diff' } },
      }
    end
  )
  assert(not ok and tostring(err):match 'do not also declare them', 'expected an atomic error for an ambiguous declaration')
end)

check('a variant restarts in a new effective working directory', function()
  local fixture = setup_variants()
  fixture.invoke('n', '<leader>gD')
  fixture.invoke('n', '<leader>gD')
  fixture.cwd = '/repo/two'
  fixture.invoke('n', '<leader>gD')

  assert(#fixture.job_attempts == 2, 'new working directory reused the old staged process')
  assert(fixture.job_attempts[2].command[3] == '--staged', 'working-directory restart lost the selected variant')
  assert(fixture.job_attempts[2].options.cwd == '/repo/two', 'replacement process did not start in the new directory')
end)

check('production Hunk declaration owns both review inputs', function()
  local fixture, loaded, load_error = load_production_hunk()
  assert(loaded, load_error)

  fixture.invoke('n', '<leader>gd')
  assert(table.concat(fixture.job_attempts[1].command, ' ') == 'hunk diff --watch --mode stack', 'production working-tree review lost its watch or layout')
  assert(fixture.user_commands.HunkReview == nil, 'ordinary Hunk context unexpectedly registered :HunkReview')

  fixture.invoke('n', '<leader>gD')
  assert(table.concat(fixture.job_attempts[2].command, ' ') == 'hunk diff --staged --watch --mode stack', 'production staged review lost its watch or layout')
  assert(fixture.job_attempts[2].options.env.OPENTUI_GRAPHICS == 'false', 'production staged review lost its render fix')
end)

check('production Hunk review context exposes the aggregate Change Set through one toggle', function()
  for _, oid_length in ipairs { 40, 64 } do
    local base_oid = string.rep('a', oid_length)
    local head_oid = string.rep('b', oid_length)
    local fixture, loaded, load_error = load_production_hunk {
      DEVFLOW_REVIEW_BASE_OID = base_oid,
      DEVFLOW_REVIEW_HEAD_OID = head_oid,
    }
    assert(loaded, load_error)

    local mapping = assert(fixture.mapping('n', '<leader>gd'), 'review context lost the Hunk diff key')
    local command = assert(fixture.user_commands.HunkReview, 'review context did not register :HunkReview')
    assert(mapping.callback == command.callback, ':HunkReview and <leader>gd do not share one toggle callback')

    fixture.invoke_command 'HunkReview'
    assert(
      table.concat(fixture.job_attempts[1].command, ' ') == 'hunk diff ' .. base_oid .. '...' .. head_oid .. ' --watch --mode stack',
      ':HunkReview did not launch the immutable aggregate diff'
    )
  end
end)

check('production Hunk fails closed for incomplete or malformed review identity', function()
  local valid_oid = string.rep('a', 40)
  local invalid_contexts = {
    { name = 'base only', base = valid_oid },
    { name = 'head only', head = valid_oid },
    { name = 'empty values', base = '', head = '' },
    { name = 'short base', base = string.rep('a', 39), head = valid_oid },
    { name = 'long head', base = valid_oid, head = string.rep('b', 65) },
    { name = 'SHA-1 base with SHA-256 head', base = valid_oid, head = string.rep('b', 64) },
    { name = 'SHA-256 base with SHA-1 head', base = string.rep('a', 64), head = valid_oid },
    { name = 'uppercase base', base = string.rep('A', 40), head = valid_oid },
    { name = 'non-hex head', base = valid_oid, head = string.rep('g', 40) },
  }

  for _, context in ipairs(invalid_contexts) do
    local fixture, loaded, load_error = load_production_hunk {
      DEVFLOW_REVIEW_BASE_OID = context.base,
      DEVFLOW_REVIEW_HEAD_OID = context.head,
    }

    assert(not loaded, context.name .. ' review context unexpectedly loaded Hunk')
    assert(tostring(load_error):match 'DEVFLOW review context', context.name .. ' failed without a clear review-context error')
    assert(fixture.mapping('n', '<leader>gd') == nil, context.name .. ' registered a Hunk mapping before failing')
    assert(fixture.user_commands.HunkReview == nil, context.name .. ' registered :HunkReview before failing')
  end
end)

check('tool environment extends the shell-owned editor contract', function()
  local fixture = setup {
    env = { OPENTUI_GRAPHICS = 'false' },
  }
  fixture.invoke('n', '<leader>gg')
  local env = fixture.job_attempts[1].options.env

  assert(env.OPENTUI_GRAPHICS == 'false', 'expected the tool-specific environment variable')
  assert(env.DOTFILES_EDITOR_HANDOFF_SOURCE == 'lazygit', 'expected the tool id as the editor-handoff source')
  assert(env.DOTFILES_EDITOR_HANDOFF_INSTANCE == '1', 'expected an opaque tool-instance marker')
  assert(env.DOTFILES_EDITOR_HANDOFF_GENERATION == '1', 'expected the tool-instance generation')
  assert(env.EDITOR == 'nvim', 'expected the shell-owned editor')
  assert(env.VISUAL == 'nvim' and env.GIT_EDITOR == 'nvim', 'expected the complete shell-owned editor contract')
end)

check('reserved editor environment cannot be overridden', function()
  local ok, err = pcall(function() setup { env = { EDITOR = 'tool-specific-editor' } } end)
  assert(not ok and tostring(err):match 'cannot override EDITOR', 'expected an atomic configuration error for EDITOR')
end)

check('instance policy rejects unsupported cardinality', function()
  local ok, err = pcall(function() setup { instances = 'repository-picker' } end)
  assert(not ok and tostring(err):match "instances must be 'singleton' or 'cwd'", 'expected an atomic instance-policy error')
end)

check('production Hunk keeps a live session for each Host Window directory', function()
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile(terminal_tool_path)
  local module_names = { 'custom.lib.terminal_tool', 'custom.lib.pack' }
  local previous_modules = {}
  for _, name in ipairs(module_names) do
    previous_modules[name] = package.loaded[name]
  end
  package.loaded['custom.lib.terminal_tool'] = terminal_tool
  package.loaded['custom.lib.pack'] = { gh = function(repository) return repository end }

  local loaded, load_error = pcall(dofile, hunk_path)
  for _, name in ipairs(module_names) do
    package.loaded[name] = previous_modules[name]
  end
  assert(loaded, load_error)

  fixture.invoke('n', '<leader>gd')
  local first_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gd')
  fixture.switch_tab()
  fixture.windows[fixture.current_win].cwd = '/repo/two'
  fixture.invoke('n', '<leader>gd')

  assert(fixture.current_tab ~= first_tab, 'production Hunk reused its first repository Tool Tab')
  assert(#fixture.job_attempts == 2, 'production Hunk did not start one job per repository')
  assert(fixture.jobs[1].running and fixture.jobs[2].running, 'production Hunk stopped the first repository session')
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

check('per-cwd editor handoff identifies and acknowledges the exact originating job', function()
  local fixture, terminal_tool = setup { instances = 'cwd' }
  fixture.invoke('n', '<leader>gg')
  use_handoff_env(fixture, 1)
  local first_data = terminal_tool.editor_handoff_data()
  fixture.invoke('n', '<leader>gg')

  fixture.switch_tab()
  local latest_host = fixture.current_win
  fixture.windows[latest_host].cwd = '/repo/two'
  fixture.invoke('n', '<leader>gg')
  use_handoff_env(fixture, 2)
  local second_data = terminal_tool.editor_handoff_data()

  assert(terminal_tool.complete_editor_handoff(first_data), 'the first cwd handoff was not recognized while the second was active')
  assert(fixture.current_win == latest_host, 'the first cwd handoff ignored the global latest Host Window')
  assert(terminal_tool.complete_editor_handoff(second_data), 'the second cwd handoff was not recognized')
  fixture.run_deferred()

  assert(#fixture.sends == 2, 'expected one acknowledgement for each originating instance')
  assert(fixture.sends[1].job == 1 and fixture.sends[2].job == 2, 'handoff acknowledgement crossed per-cwd jobs')
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

check('a failed singleton restart keeps its Tool Tab registered and retryable', function()
  local fixture = setup(nil, { buffer_results = { true, false } })
  fixture.invoke('n', '<leader>gg')
  local tool_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')
  fixture.cwd = '/repo/two'

  assert(not fixture.invoke('n', '<leader>gg'), 'expected replacement buffer allocation to fail')
  assert(fixture.tabs[tool_tab].valid, 'failed singleton restart orphaned or closed its Tool Tab')
  assert(fixture.current_win == 1, 'failed singleton restart did not restore the Host Window')
  assert(fixture.invoke('n', '<leader>gg'), 'failed singleton restart was not retryable')
  assert(fixture.current_tab == tool_tab, 'retry created a second Tool Tab instead of reusing the registered tab')
  assert(#fixture.job_attempts == 2, 'retry did not start exactly one replacement job')
end)

check('a failed per-cwd startup preserves another live instance and is independently retryable', function()
  local fixture = setup({ instances = 'cwd' }, { job_results = { 1, -1 } })
  fixture.invoke('n', '<leader>gg')
  local first_tab = fixture.current_tab
  fixture.invoke('n', '<leader>gg')

  fixture.switch_tab()
  local second_host = fixture.current_win
  fixture.windows[second_host].cwd = '/repo/two'
  assert(not fixture.invoke('n', '<leader>gg'), 'expected the second cwd startup to fail')
  assert(fixture.current_win == second_host, 'failed second startup did not restore its invoking Host Window')
  assert(fixture.tabs[first_tab].valid and fixture.jobs[1].running, 'failed second startup damaged the first instance')

  assert(fixture.invoke('n', '<leader>gg'), 'the failed cwd was not independently retryable')
  assert(#fixture.job_attempts == 3 and fixture.jobs[2].running, 'retry did not start only the failed cwd')
  assert(fixture.tabs[first_tab].valid and fixture.jobs[1].running, 'retry damaged the first instance')
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

check('editor exit stops and briefly waits for every terminal tool job', function()
  local fixture, terminal_tool = setup()
  terminal_tool.create {
    id = 'hunk',
    command = { 'hunk' },
    key = '<leader>gd',
    desc = 'Hunk',
  }

  fixture.invoke('n', '<leader>gg')
  fixture.invoke('n', '<leader>gd')
  assert(fixture.jobs[1].running and fixture.jobs[2].running, 'expected both terminal tools to be running')

  fixture.fire 'VimLeavePre'

  assert(not fixture.jobs[1].running, 'editor exit left Lazygit running')
  assert(not fixture.jobs[2].running, 'editor exit left Hunk running')
  local wait = assert(fixture.waits[1], 'editor exit did not wait for the stopped jobs')
  assert(#fixture.waits == 1 and #wait.jobs == 2, 'editor exit did not wait once for every stopped job')
  local waited = {}
  for _, job in ipairs(wait.jobs) do
    waited[job] = true
  end
  assert(waited[1] and waited[2], 'editor exit waited for the wrong jobs')
  assert(wait.timeout > 0 and wait.timeout <= 1000, 'editor exit used an unbounded shutdown wait')
end)

check('editor exit stops every live per-cwd instance', function()
  local fixture = setup { instances = 'cwd' }
  fixture.invoke('n', '<leader>gg')
  fixture.invoke('n', '<leader>gg')
  fixture.switch_tab()
  fixture.windows[fixture.current_win].cwd = '/repo/two'
  fixture.invoke('n', '<leader>gg')
  assert(fixture.jobs[1].running and fixture.jobs[2].running, 'expected both cwd instances to be running')

  fixture.fire 'VimLeavePre'

  assert(not fixture.jobs[1].running and not fixture.jobs[2].running, 'editor exit left a cwd instance running')
  local wait = assert(fixture.waits[1], 'editor exit did not wait for the cwd instances')
  assert(#fixture.waits == 1 and #wait.jobs == 2, 'editor exit did not wait once for every cwd instance')
end)

check('one per-cwd exit removes only that instance and invalidates its opaque handoff token', function()
  local fixture, terminal_tool = setup { instances = 'cwd' }
  fixture.invoke('n', '<leader>gg')
  local first_tab = fixture.current_tab
  use_handoff_env(fixture, 1)
  local exited_data = terminal_tool.editor_handoff_data()
  local exited_token = fixture.job_attempts[1].options.env.DOTFILES_EDITOR_HANDOFF_INSTANCE
  fixture.invoke('n', '<leader>gg')

  fixture.switch_tab()
  fixture.windows[fixture.current_win].cwd = '/repo/two'
  fixture.invoke('n', '<leader>gg')
  local second_tab = fixture.current_tab
  fixture.exit_job(1)

  assert(not fixture.tabs[first_tab].valid, 'exited cwd left its Tool Tab open')
  assert(fixture.tabs[second_tab].valid and fixture.jobs[2].running, 'exited cwd damaged the other instance')
  fixture.invoke('n', '<leader>gg')
  vim.api.nvim_set_current_win(1)
  fixture.invoke('n', '<leader>gg')

  local replacement_token = fixture.job_attempts[3].options.env.DOTFILES_EDITOR_HANDOFF_INSTANCE
  assert(replacement_token ~= exited_token, 'a replacement cwd reused the exited instance token')
  assert(not terminal_tool.complete_editor_handoff(exited_data), 'an exited instance handoff redirected its replacement')
  assert(fixture.tabs[second_tab].valid and fixture.jobs[2].running, 'stale handoff damaged the other live instance')
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
