local M = {}

-- Keep terminal tools inside the host Neovim even under tmux. Native tmux
-- popups are modal, so they cannot preserve host prefix and pane navigation.

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

local function job_env(source, extra_env)
  local env = {}
  for name, value in pairs(extra_env or {}) do
    env[name] = value
  end

  env.DOTFILES_EDITOR_HANDOFF_SOURCE = source
  for _, item in ipairs(editor_env()) do
    env[item[1]] = item[2]
  end
  return env
end

local function window_geometry(win)
  return {
    win = win,
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

local function sanitize_name(name) return name:gsub('[^%w]', '') end

function M.create(config)
  local state = { buf = nil, win = nil, anchor_win = nil, geometry = nil, job = nil }
  local source = assert(config.source, 'terminal tool source is required')
  local name = assert(config.name, 'terminal tool name is required')
  local command = assert(config.command, 'terminal tool command is required')
  local key = assert(config.key, 'terminal tool key is required')
  local hide_command = assert(config.hide_command, 'terminal tool hide command is required')

  local function tool_command()
    if type(command) == 'function' then return command() end
    return vim.deepcopy(command)
  end

  local function close_window()
    if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_hide(state.win) end
    state.win = nil
    state.anchor_win = nil
    state.geometry = nil
  end

  local function acknowledge_editor_return()
    vim.defer_fn(function()
      if state.job then vim.fn.chansend(state.job, '\r') end
    end, config.editor_return_delay_ms or 300)
  end

  local function hide(opts)
    close_window()
    if opts and opts.bang and config.acknowledge_editor_return then acknowledge_editor_return() end
  end

  vim.api.nvim_create_user_command(hide_command, hide, { bang = true })

  local function resize_window()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
    if not state.anchor_win or not vim.api.nvim_win_is_valid(state.anchor_win) then return end

    local geometry = window_geometry(state.anchor_win)
    if state.geometry and state.geometry.width == geometry.width and state.geometry.height == geometry.height then return end

    -- Floating-window dimensions are fixed cell counts, so keep them in sync
    -- with the Neovim window that launched the terminal tool.
    vim.api.nvim_win_set_config(state.win, float_opts(geometry))
    state.geometry = geometry
  end

  local function open_window()
    state.anchor_win = vim.api.nvim_get_current_win()
    state.geometry = window_geometry(state.anchor_win)
    state.win = vim.api.nvim_open_win(state.buf, true, float_opts(state.geometry))
    vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = state.win })
    vim.cmd.startinsert()
  end

  local function toggle()
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
      env = job_env(source, config.env),
      on_exit = function()
        if state.buf and vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force = true }) end
        state.buf = nil
        state.win = nil
        state.anchor_win = nil
        state.geometry = nil
        state.job = nil
      end,
    })

    vim.keymap.set('t', key, toggle, { buf = state.buf, desc = config.terminal_key_desc or config.desc })
    vim.cmd.startinsert()
  end

  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = vim.api.nvim_create_augroup('Dotfiles' .. sanitize_name(name), { clear = true }),
    callback = resize_window,
  })

  return {
    state = state,
    toggle = toggle,
    hide = hide,
  }
end

return M
