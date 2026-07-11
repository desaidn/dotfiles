local M = {}

-- Keep terminal tools inside the host Neovim even under tmux. Native tmux
-- popups are modal, so they cannot preserve host prefix and pane navigation.

local HANDOFF_SOURCE_ENV = 'DOTFILES_EDITOR_HANDOFF_SOURCE'
local HANDOFF_GENERATION_ENV = 'DOTFILES_EDITOR_HANDOFF_GENERATION'
local HANDOFF_DATA_KEY = 'terminal_tool_id'
local HANDOFF_DATA_GENERATION_KEY = 'terminal_tool_generation'
local HANDOFF_ACK_DELAY_MS = 300
local RESIZE_GROUP = 'DotfilesTerminalTools'

local tools = {}
local tool_keys = {}
local resize_events_registered = false

local function editor_env()
  local editor = vim.env.EDITOR
  if editor == nil or editor == '' then editor = 'nvim' end

  local function value_or(name, fallback)
    local value = vim.env[name]
    if value == nil or value == '' then return fallback end
    return value
  end

  return {
    EDITOR = editor,
    VISUAL = value_or('VISUAL', editor),
    GIT_EDITOR = value_or('GIT_EDITOR', editor),
  }
end

local function job_env(id, generation, extra_env)
  local env = vim.deepcopy(extra_env or {})
  env[HANDOFF_SOURCE_ENV] = id
  env[HANDOFF_GENERATION_ENV] = tostring(generation)

  for name, value in pairs(editor_env()) do
    env[name] = value
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

local function notify(tool, message, level) vim.notify(string.format('%s: %s', tool.spec.desc, message), level, { title = 'Terminal tool' }) end

local function clear_window(tool)
  local state = tool.state
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local ok = pcall(vim.api.nvim_win_hide, state.win)
    if not ok and vim.api.nvim_win_is_valid(state.win) then return false end
  end
  state.win = nil
  state.anchor_win = nil
  state.geometry = nil
  return true
end

local function delete_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return true end
  local ok = pcall(vim.api.nvim_buf_delete, buf, { force = true })
  return ok or not vim.api.nvim_buf_is_valid(buf)
end

local function clear_generation(tool, generation, buf, retried)
  local state = tool.state
  if state.generation ~= generation or state.buf ~= buf then return false end

  local window_cleared = clear_window(tool)
  local buffer_deleted = delete_buffer(buf)
  if not window_cleared or not buffer_deleted then
    if not retried then
      vim.schedule(function() clear_generation(tool, generation, buf, true) end)
    else
      notify(tool, 'could not clean up its finished process', vim.log.levels.WARN)
    end
    return false
  end

  state.buf = nil
  state.job = nil
  state.cwd = nil
  return true
end

local function open_window(tool)
  local state = tool.state
  local ok, err = pcall(function()
    state.anchor_win = vim.api.nvim_get_current_win()
    state.geometry = window_geometry(state.anchor_win)
    state.win = vim.api.nvim_open_win(state.buf, true, float_opts(state.geometry))
    vim.api.nvim_set_option_value('winhl', 'NormalFloat:Normal', { win = state.win })
  end)

  if ok then return true end

  clear_window(tool)
  notify(tool, 'could not open its window: ' .. tostring(err), vim.log.levels.ERROR)
  return false
end

local function focus_terminal(tool)
  return pcall(function()
    vim.api.nvim_set_current_win(tool.state.win)
    vim.cmd.startinsert()
  end)
end

local function resize_window(tool)
  local state = tool.state
  if not state.win then return end
  if not vim.api.nvim_win_is_valid(state.win) then
    clear_window(tool)
    return
  end
  if not state.anchor_win or not vim.api.nvim_win_is_valid(state.anchor_win) then
    clear_window(tool)
    return
  end

  local geometry_ok, geometry = pcall(window_geometry, state.anchor_win)
  if not geometry_ok then
    clear_window(tool)
    notify(tool, 'could not read its window size: ' .. tostring(geometry), vim.log.levels.WARN)
    return
  end
  if state.geometry and state.geometry.width == geometry.width and state.geometry.height == geometry.height then return end

  -- Floating-window dimensions are fixed cell counts, so keep them in sync
  -- with the Neovim window that launched the terminal tool.
  local ok, err = pcall(vim.api.nvim_win_set_config, state.win, float_opts(geometry))
  if not ok then
    clear_window(tool)
    notify(tool, 'could not resize its window: ' .. tostring(err), vim.log.levels.WARN)
    return
  end
  state.geometry = geometry
end

local function ensure_resize_events()
  if resize_events_registered then return end

  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = vim.api.nvim_create_augroup(RESIZE_GROUP, { clear = true }),
    callback = function()
      for _, tool in pairs(tools) do
        resize_window(tool)
      end
    end,
  })
  resize_events_registered = true
end

local function stop_generation(tool)
  local state = tool.state
  local generation = state.generation
  local buf = state.buf
  if state.job then pcall(vim.fn.jobstop, state.job) end
  if state.buf == buf and not clear_generation(tool, generation, buf) then return false end
  return true
end

local function start_tool(tool, cwd)
  local state = tool.state
  state.generation = state.generation + 1
  local generation = state.generation

  local ok, buf_or_error = pcall(vim.api.nvim_create_buf, false, true)
  if not ok then
    notify(tool, 'could not create its terminal buffer: ' .. tostring(buf_or_error), vim.log.levels.ERROR)
    return false
  end

  local buf = buf_or_error
  state.buf = buf
  state.cwd = cwd
  if not open_window(tool) then
    clear_generation(tool, generation, buf)
    return false
  end

  local started, job = pcall(vim.api.nvim_win_call, state.win, function()
    return vim.fn.jobstart(vim.deepcopy(tool.spec.command), {
      term = true,
      cwd = cwd,
      env = job_env(tool.spec.id, generation, tool.spec.env),
      on_exit = function()
        vim.schedule(function() clear_generation(tool, generation, buf) end)
      end,
    })
  end)

  if not started then
    clear_generation(tool, generation, buf)
    notify(tool, 'could not start its job: ' .. tostring(job), vim.log.levels.ERROR)
    return false
  end

  if job <= 0 then
    clear_generation(tool, generation, buf)
    local reason = job == -1 and ('executable not found: ' .. tool.spec.command[1]) or 'Neovim could not start the job'
    notify(tool, reason, vim.log.levels.ERROR)
    return false
  end

  -- A very short-lived job may exit before jobstart returns. Its callback owns
  -- cleanup, so do not restore handles from a generation that already ended.
  if state.generation ~= generation or state.buf ~= buf then return false end
  state.job = job
  local focused, focus_error = focus_terminal(tool)
  if not focused then
    pcall(vim.fn.jobstop, job)
    clear_generation(tool, generation, buf)
    notify(tool, 'could not focus its terminal window: ' .. tostring(focus_error), vim.log.levels.ERROR)
    return false
  end
  return true
end

local function window_is_in_current_tab(win)
  local ok, tab = pcall(vim.api.nvim_win_get_tabpage, win)
  return ok and tab == vim.api.nvim_get_current_tabpage()
end

local function toggle(tool)
  local state = tool.state
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    if window_is_in_current_tab(state.win) then return clear_window(tool) end
    if not clear_window(tool) then return false end
  end

  if state.win and not clear_window(tool) then return false end
  if state.buf and not vim.api.nvim_buf_is_valid(state.buf) and not stop_generation(tool) then return false end

  local cwd = vim.fn.getcwd()
  if state.buf and state.cwd ~= cwd and not stop_generation(tool) then return false end

  if state.buf then
    if not open_window(tool) then return false end
    local focused, focus_error = focus_terminal(tool)
    if not focused then
      clear_window(tool)
      notify(tool, 'could not focus its terminal window: ' .. tostring(focus_error), vim.log.levels.ERROR)
      return false
    end
    return true
  end

  return start_tool(tool, cwd)
end

local function acknowledge_editor_return(tool)
  local state = tool.state
  local generation = state.generation
  local job = state.job
  if not job then return end

  vim.defer_fn(function()
    if state.generation ~= generation or state.job ~= job then return end

    local ok, sent = pcall(vim.fn.chansend, job, '\r')
    if not ok or sent == 0 then notify(tool, 'could not acknowledge editor return', vim.log.levels.WARN) end
  end, HANDOFF_ACK_DELAY_MS)
end

local function complete_handoff(tool)
  if not clear_window(tool) then
    notify(tool, 'could not hide after editor return', vim.log.levels.WARN)
    return false
  end
  if tool.spec.handoff == 'hide-and-acknowledge' then acknowledge_editor_return(tool) end
  return true
end

local function assert_nonempty_string(value, message)
  assert(type(value) == 'string' and value ~= '', message)
  return value
end

local function normalize_config(config)
  assert(type(config) == 'table', 'terminal tool config must be a table')

  local id = assert_nonempty_string(config.id, 'terminal tool id is required')
  assert(id:match '^[%w_-]+$', 'terminal tool id may contain only letters, numbers, underscores, and hyphens')
  assert(tools[id] == nil, 'terminal tool id is already registered: ' .. id)

  local key = assert_nonempty_string(config.key, 'terminal tool key is required')
  assert(tool_keys[key] == nil, string.format('terminal tool key %s is already registered by %s', key, tool_keys[key] or ''))

  local command = config.command
  assert(type(command) == 'table' and #command > 0, 'terminal tool command must be a non-empty argv table')
  for index, value in ipairs(command) do
    assert_nonempty_string(value, string.format('terminal tool command argument %d must be a non-empty string', index))
  end

  local handoff = config.handoff or 'hide'
  assert(handoff == 'hide' or handoff == 'hide-and-acknowledge', "terminal tool handoff must be 'hide' or 'hide-and-acknowledge'")

  local env = config.env or {}
  assert(type(env) == 'table', 'terminal tool env must be a table')
  local reserved_env = {
    [HANDOFF_SOURCE_ENV] = true,
    [HANDOFF_GENERATION_ENV] = true,
    EDITOR = true,
    VISUAL = true,
    GIT_EDITOR = true,
  }
  for name, value in pairs(env) do
    assert_nonempty_string(name, 'terminal tool environment names must be non-empty strings')
    assert(type(value) == 'string', 'terminal tool environment values must be strings')
    assert(not reserved_env[name], 'terminal tool env cannot override ' .. name)
  end

  return {
    id = id,
    key = key,
    desc = assert_nonempty_string(config.desc, 'terminal tool desc is required'),
    command = vim.deepcopy(command),
    env = vim.deepcopy(env),
    handoff = handoff,
  }
end

---@class custom.TerminalToolConfig
---@field id string
---@field command string[]
---@field key string
---@field desc string
---@field env? table<string, string>
---@field handoff? 'hide'|'hide-and-acknowledge'

---@param config custom.TerminalToolConfig
function M.create(config)
  local tool = {
    spec = normalize_config(config),
    state = {
      generation = 0,
      buf = nil,
      win = nil,
      anchor_win = nil,
      geometry = nil,
      job = nil,
      cwd = nil,
    },
  }
  tool.toggle = function() return toggle(tool) end

  ensure_resize_events()
  vim.keymap.set('n', tool.spec.key, tool.toggle, { desc = tool.spec.desc })
  tools[tool.spec.id] = tool
  tool_keys[tool.spec.key] = tool.spec.id
end

---@return table
function M.editor_handoff_data()
  local id = vim.env[HANDOFF_SOURCE_ENV]
  local generation = vim.env[HANDOFF_GENERATION_ENV]
  if id == nil or id == '' or generation == nil or generation == '' then return {} end
  return {
    [HANDOFF_DATA_KEY] = id,
    [HANDOFF_DATA_GENERATION_KEY] = generation,
  }
end

---@param data? table
---@return boolean handled
function M.complete_editor_handoff(data)
  if type(data) ~= 'table' then return false end
  local tool = tools[data[HANDOFF_DATA_KEY]]
  if not tool then return false end
  if tostring(tool.state.generation) ~= data[HANDOFF_DATA_GENERATION_KEY] or not tool.state.job then return false end

  return complete_handoff(tool)
end

return M
