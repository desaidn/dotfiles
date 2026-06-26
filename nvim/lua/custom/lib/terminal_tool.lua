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

local function run_tmux(args)
  local command = { 'tmux' }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  return vim.v.shell_error == 0, output
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

local function float_opts()
  return {
    relative = 'editor',
    width = vim.o.columns,
    height = vim.o.lines - 3,
    row = 1,
    col = 0,
    style = 'minimal',
    border = 'none',
  }
end

local function sanitize_name(name)
  return name:gsub('[^%w]', '')
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
    local seed = vim.fn.getcwd() .. '\n' .. vim.v.servername
    return 'dotfiles-' .. source .. '-' .. vim.fn.sha256(seed):sub(1, 12)
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
    state.win = vim.api.nvim_open_win(state.buf, true, float_opts())
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
    local session = ensure_tmux_session()
    if not session then return end

    local popup = {
      'tmux',
      'display-popup',
      '-E',
      '-B',
      '-w',
      '100%',
      '-h',
      '100%',
      '-d',
      vim.fn.getcwd(),
      shell_command { 'tmux', 'attach-session', '-t', tmux_target(session) },
    }

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

    vim.keymap.set('t', key, toggle, { buffer = state.buf, desc = config.terminal_key_desc or config.desc })
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
