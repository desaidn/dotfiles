local failures = {}

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end

  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function fake_vim()
  local fixture = {
    geometry = { row = 0, col = 0, width = 80, height = 24 },
    autocmds = {},
    float_config = nil,
    jobs = {},
  }

  local function deepcopy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, item in pairs(value) do
      copy[deepcopy(key)] = deepcopy(item)
    end
    return copy
  end

  local fake = {
    env = {
      TMUX = '/tmp/tmux-test/default,1,0',
      TMUX_PANE = '%1',
      EDITOR = 'nvim',
      VISUAL = 'nvim',
      GIT_EDITOR = 'nvim',
    },
    cmd = { startinsert = function() end },
    keymap = { set = function() end },
    deepcopy = deepcopy,
    defer_fn = function(callback) callback() end,
    fn = {
      jobstart = function(command, options)
        fixture.jobs[#fixture.jobs + 1] = deepcopy(command)
        fixture.job_options = fixture.job_options or {}
        fixture.job_options[#fixture.job_options + 1] = deepcopy(options)
        return #fixture.jobs
      end,
    },
    api = {
      nvim_get_current_win = function() return 1 end,
      nvim_win_get_width = function() return fixture.geometry.width end,
      nvim_win_get_height = function() return fixture.geometry.height end,
      nvim_create_buf = function() return 1 end,
      nvim_buf_is_valid = function() return true end,
      nvim_buf_delete = function() end,
      nvim_open_win = function(_, _, config)
        fixture.float_config = deepcopy(config)
        return 2
      end,
      nvim_win_is_valid = function() return fixture.float_config ~= nil end,
      nvim_win_hide = function() fixture.float_config = nil end,
      nvim_win_set_config = function(_, config) fixture.float_config = deepcopy(config) end,
      nvim_set_option_value = function() end,
      nvim_create_user_command = function() end,
      nvim_create_augroup = function() return 1 end,
      nvim_create_autocmd = function(event, options)
        for _, name in ipairs(type(event) == 'table' and event or { event }) do
          fixture.autocmds[name] = fixture.autocmds[name] or {}
          fixture.autocmds[name][#fixture.autocmds[name] + 1] = options.callback
        end
      end,
    },
  }

  function fixture.fire(event)
    for _, callback in ipairs(fixture.autocmds[event] or {}) do
      callback()
    end
  end

  function fixture.popups()
    local result = {}
    for _, command in ipairs(fixture.jobs) do
      if command[1] == 'tmux' and command[2] == 'display-popup' then result[#result + 1] = command end
    end
    return result
  end

  function fixture.surface()
    if fixture.float_config then
      return {
        kind = 'Neovim float',
        width = fixture.float_config.width,
        height = fixture.float_config.height,
      }
    end

    local popup = fixture.popups()[#fixture.popups()]
    if not popup then return nil end

    local values = {}
    for index, value in ipairs(popup) do
      values[value] = popup[index + 1]
    end
    return {
      kind = 'tmux popup',
      width = tonumber(values['-w']),
      height = tonumber(values['-h']),
    }
  end

  return fake, fixture
end

local function launch(overrides)
  local fake, fixture = fake_vim()
  _G.vim = fake
  local terminal_tool = dofile 'nvim/lua/custom/lib/terminal_tool.lua'
  local config = {
    name = 'Lazygit',
    source = 'lazygit',
    command = { 'lazygit' },
    key = '<leader>gg',
    desc = 'Lazygit',
    hide_command = 'LazygitHide',
  }
  for name, value in pairs(overrides or {}) do
    config[name] = value
  end

  local tool = terminal_tool.create(config)
  tool.toggle()
  return fixture, tool
end

check('terminal surface tracks a host resize while running under tmux', function()
  for _, event in ipairs { 'VimResized', 'WinResized' } do
    local fixture = launch()
    local before = fixture.surface()
    assert(before, 'expected a terminal surface when the tool opens')
    assert(before.width == 80 and before.height == 24, 'expected the initial surface to match the 80x24 host')

    fixture.geometry.width = 120
    fixture.geometry.height = 40
    fixture.fire(event)

    local after = fixture.surface()
    assert(
      after and after.width == 120 and after.height == 40,
      string.format(
        '%s: host changed from 80x24 to 120x40, but the live %s remained %sx%s',
        event,
        after and after.kind or 'surface',
        tostring(after and after.width),
        tostring(after and after.height)
      )
    )
  end
end)

check('terminal job persists when its float is hidden and reopened', function()
  local fixture, tool = launch()
  assert(#fixture.jobs == 1, 'expected one terminal job after opening the tool')

  tool.toggle()
  tool.toggle()

  assert(#fixture.jobs == 1, 'hiding and reopening the float started a second terminal job')
  assert(fixture.surface() and fixture.surface().kind == 'Neovim float', 'expected the terminal float to reopen')
end)

check('tool-specific environment extends the shell-owned editor contract', function()
  local fixture = launch {
    env = {
      OPENTUI_GRAPHICS = 'false',
      EDITOR = 'tool-specific-editor',
    },
  }
  local env = fixture.job_options[1].env

  assert(env.OPENTUI_GRAPHICS == 'false', 'expected the tool-specific environment variable')
  assert(env.DOTFILES_EDITOR_HANDOFF_SOURCE == 'lazygit', 'expected the editor-handoff source marker')
  assert(env.EDITOR == 'nvim', 'tool-specific environment replaced the shell-owned editor contract')
  assert(env.VISUAL == 'nvim' and env.GIT_EDITOR == 'nvim', 'expected the complete shell-owned editor contract')
end)

check('host tmux remains upstream for prefix navigation', function()
  local fixture = launch()
  local popups = fixture.popups()
  assert(#popups == 0, 'tmux `display-popup` is modal and prevents host prefix and pane navigation')

  local surface = fixture.surface()
  assert(surface and surface.kind == 'Neovim float', 'expected the terminal tool to stay inside the host Neovim pane')
end)

if #failures > 0 then
  io.stderr:write(string.format('\n%d terminal_tool regression check%s failed\n', #failures, #failures == 1 and '' or 's'))
  os.exit(1)
end

io.stdout:write '\nterminal_tool regression checks passed\n'
