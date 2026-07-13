local M = {}

-- Keep terminal tools inside the host Neovim even under tmux. Native tmux
-- popups are modal, so they cannot preserve host prefix and pane navigation.

local HANDOFF_SOURCE_ENV = 'DOTFILES_EDITOR_HANDOFF_SOURCE'
local HANDOFF_GENERATION_ENV = 'DOTFILES_EDITOR_HANDOFF_GENERATION'
local HANDOFF_DATA_KEY = 'terminal_tool_id'
local HANDOFF_DATA_GENERATION_KEY = 'terminal_tool_generation'
local HANDOFF_ACK_DELAY_MS = 300

local tools = {}
local tool_keys = {}
local host_win = nil

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

local function notify(tool, message, level) vim.notify(string.format('%s: %s', tool.spec.desc, message), level, { title = 'Terminal tool' }) end

local function valid_window(win) return win ~= nil and vim.api.nvim_win_is_valid(win) end

local function valid_tab(tab) return tab ~= nil and vim.api.nvim_tabpage_is_valid(tab) end

local function restore_window(win)
  if valid_window(win) then pcall(vim.api.nvim_set_current_win, win) end
end

local function tab_is_tool(tab)
  for _, registered in pairs(tools) do
    if registered.state.tab == tab and valid_tab(tab) then return true end
  end
  return false
end

local function current_tab_is_tool() return tab_is_tool(vim.api.nvim_get_current_tabpage()) end

local function find_host_window()
  if valid_window(host_win) and not tab_is_tool(vim.api.nvim_win_get_tabpage(host_win)) then return host_win end

  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not tab_is_tool(tab) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if valid_window(win) then
          host_win = win
          return host_win
        end
      end
    end
  end

  local ok = pcall(vim.cmd.tabnew)
  if not ok then return nil end
  host_win = vim.api.nvim_get_current_win()
  return host_win
end

local function focus_host_window()
  local win = find_host_window()
  if not win then return false end
  return pcall(vim.api.nvim_set_current_win, win)
end

local function host_cwd()
  local win = find_host_window()
  if not win then return nil end
  local ok, cwd = pcall(vim.api.nvim_win_call, win, vim.fn.getcwd)
  if not ok then return nil end
  return cwd
end

local function delete_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return true end
  local ok = pcall(vim.api.nvim_buf_delete, buf, { force = true })
  return ok or not vim.api.nvim_buf_is_valid(buf)
end

local function forget_stale_tab(state)
  if state.tab and not valid_tab(state.tab) then
    state.tab = nil
    state.win = nil
  elseif state.win and not valid_window(state.win) then
    state.win = nil
  end
end

local function close_tool_tab(tool)
  local state = tool.state
  forget_stale_tab(state)
  if not state.tab then return true end

  local tab = state.tab
  if vim.api.nvim_get_current_tabpage() == tab and not focus_host_window() then return false end
  local ok = pcall(vim.api.nvim_tabpage_close, tab, false)
  if not ok and valid_tab(tab) then return false end
  state.tab = nil
  state.win = nil
  return true
end

local function clear_generation(tool, generation, buf, retried)
  local state = tool.state
  if state.generation ~= generation or state.buf ~= buf then return false end

  local tab_closed = close_tool_tab(tool)
  local buffer_deleted = delete_buffer(buf)
  if not tab_closed or not buffer_deleted then
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

local function open_tool_tab(tool)
  local state = tool.state
  forget_stale_tab(state)
  local previous_win = vim.api.nvim_get_current_win()
  local created_tab = false

  local ok, err = pcall(function()
    if state.tab then
      vim.api.nvim_set_current_tabpage(state.tab)
      if not valid_window(state.win) then state.win = vim.api.nvim_tabpage_list_wins(state.tab)[1] end
    else
      vim.cmd.tabnew()
      created_tab = true
      state.tab = vim.api.nvim_get_current_tabpage()
      state.win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(state.win, state.buf)
  end)

  if ok then return true end

  if created_tab and valid_tab(state.tab) then pcall(vim.api.nvim_tabpage_close, state.tab, false) end
  state.tab = nil
  state.win = nil
  restore_window(previous_win)
  notify(tool, 'could not open its Tool Tab: ' .. tostring(err), vim.log.levels.ERROR)
  return false
end

local function focus_terminal(tool)
  if not open_tool_tab(tool) then return false end
  return pcall(function()
    vim.api.nvim_set_current_win(tool.state.win)
    vim.cmd.startinsert()
  end)
end

local function stop_generation(tool, preserve_tab)
  local state = tool.state
  local buf = state.buf
  if state.job then pcall(vim.fn.jobstop, state.job) end

  if not preserve_tab and not close_tool_tab(tool) then return false end
  if not delete_buffer(buf) then return false end
  state.buf = nil
  state.job = nil
  state.cwd = nil
  return true
end

local function start_tool(tool, cwd, return_win)
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
  if not open_tool_tab(tool) then
    clear_generation(tool, generation, buf)
    restore_window(return_win)
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

  if not started or job <= 0 then
    clear_generation(tool, generation, buf)
    restore_window(return_win)
    local reason
    if not started then
      reason = 'could not start its job: ' .. tostring(job)
    else
      reason = job == -1 and ('executable not found: ' .. tool.spec.command[1]) or 'Neovim could not start the job'
    end
    notify(tool, reason, vim.log.levels.ERROR)
    return false
  end

  -- A very short-lived job may exit before jobstart returns. Its callback owns
  -- cleanup, so do not restore handles from a generation that already ended.
  if state.generation ~= generation or state.buf ~= buf then
    restore_window(return_win)
    return false
  end
  state.job = job
  local focused, focus_error = focus_terminal(tool)
  if not focused then
    pcall(vim.fn.jobstop, job)
    clear_generation(tool, generation, buf)
    restore_window(return_win)
    notify(tool, 'could not focus its Tool Tab: ' .. tostring(focus_error), vim.log.levels.ERROR)
    return false
  end
  return true
end

local function toggle(tool)
  local state = tool.state
  forget_stale_tab(state)
  local current_win = vim.api.nvim_get_current_win()

  if state.tab and vim.api.nvim_get_current_tabpage() == state.tab then return focus_host_window() end
  if not current_tab_is_tool() then host_win = current_win end

  local cwd = host_cwd()
  if not cwd then
    notify(tool, 'could not determine the Host Window working directory', vim.log.levels.ERROR)
    return false
  end

  if state.buf and not vim.api.nvim_buf_is_valid(state.buf) and not stop_generation(tool, false) then return false end
  if state.buf and state.cwd ~= cwd and not stop_generation(tool, true) then return false end

  if state.buf then
    local focused, focus_error = focus_terminal(tool)
    if not focused then
      notify(tool, 'could not focus its Tool Tab: ' .. tostring(focus_error), vim.log.levels.ERROR)
      restore_window(current_win)
      return false
    end
    return true
  end

  return start_tool(tool, cwd, current_win)
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

local function handoff_tool(data)
  if type(data) ~= 'table' then return nil end
  local tool = tools[data[HANDOFF_DATA_KEY]]
  if not tool then return nil end
  if tostring(tool.state.generation) ~= data[HANDOFF_DATA_GENERATION_KEY] or not tool.state.job then return nil end
  return tool
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

  local handoff = config.handoff or 'return'
  assert(handoff == 'return' or handoff == 'return-and-acknowledge', "terminal tool handoff must be 'return' or 'return-and-acknowledge'")

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
---@field handoff? 'return'|'return-and-acknowledge'

---@param config custom.TerminalToolConfig
function M.create(config)
  local tool = {
    spec = normalize_config(config),
    state = {
      generation = 0,
      buf = nil,
      win = nil,
      tab = nil,
      job = nil,
      cwd = nil,
    },
  }
  tool.toggle = function() return toggle(tool) end

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
---@return integer? win
function M.editor_handoff_window(data)
  if not handoff_tool(data) then return nil end
  return find_host_window()
end

---@param data? table
---@return boolean handled
function M.complete_editor_handoff(data)
  local tool = handoff_tool(data)
  if not tool then return false end
  if not focus_host_window() then
    notify(tool, 'could not return to the Host Window after editor handoff', vim.log.levels.WARN)
    return false
  end
  if tool.spec.handoff == 'return-and-acknowledge' then acknowledge_editor_return(tool) end
  return true
end

return M
