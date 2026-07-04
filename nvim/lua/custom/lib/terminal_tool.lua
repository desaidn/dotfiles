local M = {}

local function in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ''
end

local function shell_command(command)
  local parts = {}
  for _, arg in ipairs(command) do
    table.insert(parts, vim.fn.shellescape(arg))
  end
  return table.concat(parts, ' ')
end

local function tmux_target(session)
  return '=' .. session
end

local function tmux_current_pane()
  if vim.env.TMUX_PANE == nil or vim.env.TMUX_PANE == '' then return nil end
  return vim.env.TMUX_PANE
end

local function run_tmux(args)
  local command = { 'tmux' }
  vim.list_extend(command, args)
  local ok, result = pcall(function() return vim.system(command, { text = true }):wait() end)
  if not ok then return false, tostring(result) end

  local output = result.code == 0 and result.stdout or result.stderr
  return result.code == 0, output or ''
end

local function editor_env()
  local editor = vim.env.EDITOR
  if editor == nil or editor == '' then editor = 'nvim' end

  local function value_or(name, fallback)
    local value = vim.env[name]
    if value == nil or value == '' then return fallback end
    return value
  end

  return {
    { 'EDITOR', editor },
    { 'VISUAL', value_or('VISUAL', editor) },
    { 'GIT_EDITOR', value_or('GIT_EDITOR', editor) },
  }
end

local function append_editor_env(command)
  -- Detached tmux sessions inherit tmux's server environment,
  -- which may predate the shell that launched Neovim.
  for _, item in ipairs(editor_env()) do
    local name, value = item[1], item[2]
    if value ~= '' then table.insert(command, name .. '=' .. value) end
  end
end

local function job_env(source)
  local env = { DOTFILES_EDITOR_HANDOFF_SOURCE = source }
  for _, item in ipairs(editor_env()) do
    env[item[1]] = item[2]
  end
  return env
end

local function current_window_geometry()
  local win = vim.api.nvim_get_current_win()
  local position = vim.api.nvim_win_get_position(win)

  return {
    win = win,
    row = position[1],
    col = position[2],
    width = math.max(1, vim.api.nvim_win_get_width(win)),
    height = math.max(1, vim.api.nvim_win_get_height(win)),
  }
end

local function float_opts(geometry)
  return {
    relative = 'win',
    win = geometry.win,
    width = geometry.width,
    height = geometry.height,
    row = 0,
    col = 0,
    style = 'minimal',
    border = 'none',
  }
end

local function tmux_pane_origin()
  local args = { 'display-message', '-p' }
  local target_pane = tmux_current_pane()
  if target_pane then vim.list_extend(args, { '-t', target_pane }) end
  table.insert(args, '#{pane_left} #{pane_top}')

  local ok, output = run_tmux(args)
  if not ok then return nil end

  local left, top = output:match '(%d+)%s+(%d+)'
  if not left or not top then return nil end

  return tonumber(left), tonumber(top)
end

local function tmux_popup_position(geometry)
  local pane_left, pane_top = tmux_pane_origin()
  if not pane_left or not pane_top then return nil end

  -- tmux positions popups in client coordinates; Neovim reports windows
  -- relative to the editor grid inside the current tmux pane.
  return {
    x = pane_left + geometry.col,
    y = pane_top + geometry.row,
  }
end

local function sanitize_name(name)
  return name:gsub('[^%w]', '')
end

local function project_name(cwd)
  local name = sanitize_name(vim.fn.fnamemodify(cwd, ':t'))
  if name ~= '' then return name end
  return 'workspace'
end

function M.create(config)
  local state = { buf = nil, win = nil, tmux_session = nil, job = nil }
  local source = assert(config.source, 'terminal tool source is required')
  local name = assert(config.name, 'terminal tool name is required')
  local command = assert(config.command, 'terminal tool command is required')
  local key = assert(config.key, 'terminal tool key is required')
  local hide_command = assert(config.hide_command, 'terminal tool hide command is required')

  local function tool_command()
    if type(command) == 'function' then return command() end
    return vim.deepcopy(command)
  end

  local function tmux_session_name()
    local cwd = vim.fn.getcwd()
    local seed = cwd .. '\n' .. vim.v.servername
    return project_name(cwd) .. '-' .. source .. '-' .. vim.fn.sha256(seed):sub(1, 12)
  end

  local function close_window()
    if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_hide(state.win) end
    state.win = nil
  end

  local function close_tmux_popup()
    if in_tmux() then vim.fn.jobstart({ 'tmux', 'display-popup', '-C' }, { detach = true }) end
  end

  local function acknowledge_editor_return()
    vim.defer_fn(function()
      if in_tmux() and state.tmux_session then
        run_tmux { 'send-keys', '-t', state.tmux_session, 'Enter' }
        return
      end

      if state.job then vim.fn.chansend(state.job, '\r') end
    end, config.editor_return_delay_ms or 300)
  end

  local function hide(opts)
    close_window()
    close_tmux_popup()
    if opts and opts.bang and config.acknowledge_editor_return then acknowledge_editor_return() end
  end

  vim.api.nvim_create_user_command(hide_command, hide, { bang = true })

  local function open_window()
    state.win = vim.api.nvim_open_win(state.buf, true, float_opts(current_window_geometry()))
    vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = state.win })
    vim.cmd.startinsert()
  end

  local function ensure_tmux_session()
    local session = tmux_session_name()
    state.tmux_session = session

    local exists = run_tmux { 'has-session', '-t', tmux_target(session) }
    if exists then return session end

    local launch = { 'env', 'NVIM=' .. vim.v.servername, 'DOTFILES_EDITOR_HANDOFF_SOURCE=' .. source }
    append_editor_env(launch)
    vim.list_extend(launch, tool_command())

    local started, output = run_tmux {
      'new-session',
      '-d',
      '-s',
      session,
      '-c',
      vim.fn.getcwd(),
      shell_command(launch),
    }

    if not started then
      vim.notify('Unable to start ' .. name .. ' tmux session: ' .. output, vim.log.levels.ERROR)
      return nil
    end

    run_tmux { 'set-option', '-t', session, 'status', 'off' }
    return session
  end

  local function open_tmux_popup()
    local geometry = current_window_geometry()
    local session = ensure_tmux_session()
    if not session then return end

    local popup = {
      'tmux',
      'display-popup',
      '-E',
      '-B',
      '-w',
      tostring(geometry.width),
      '-h',
      tostring(geometry.height),
    }

    local target_pane = tmux_current_pane()
    if target_pane then vim.list_extend(popup, { '-t', target_pane }) end

    local position = tmux_popup_position(geometry)
    if position then
      vim.list_extend(popup, {
        '-x',
        tostring(position.x),
        '-y',
        tostring(position.y),
      })
    end

    vim.list_extend(popup, {
      '-d',
      vim.fn.getcwd(),
      shell_command { 'tmux', 'attach-session', '-t', tmux_target(session) },
    })

    local job = vim.fn.jobstart(popup)
    if job <= 0 then vim.notify('Unable to open ' .. name .. ' tmux popup', vim.log.levels.ERROR) end
  end

  local function toggle()
    if in_tmux() then
      open_tmux_popup()
      return
    end

    if state.win and vim.api.nvim_win_is_valid(state.win) then
      close_window()
      return
    end

    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      open_window()
      return
    end

    state.buf = vim.api.nvim_create_buf(false, true)
    open_window()

    state.job = vim.fn.jobstart(tool_command(), {
      term = true,
      env = job_env(source),
      on_exit = function()
        if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force = true }) end
        state.buf = nil
        state.win = nil
        state.job = nil
      end,
    })

    vim.keymap.set('t', key, toggle, { buf = state.buf, desc = config.terminal_key_desc or config.desc })
    vim.cmd.startinsert()
  end

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('Dotfiles' .. sanitize_name(name), { clear = true }),
    callback = function()
      if state.tmux_session then
        vim.fn.jobstart({ 'tmux', 'kill-session', '-t', tmux_target(state.tmux_session) }, { detach = true })
      end
    end,
  })

  return {
    state = state,
    toggle = toggle,
    hide = hide,
  }
end

return M
