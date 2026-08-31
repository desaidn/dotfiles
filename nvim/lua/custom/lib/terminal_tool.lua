local M = {}

-- Keep terminal tools inside the host Neovim even under tmux. Native tmux
-- popups are modal, so they cannot preserve host prefix and pane navigation.

local HANDOFF_SOURCE_ENV = 'DOTFILES_EDITOR_HANDOFF_SOURCE'
local HANDOFF_INSTANCE_ENV = 'DOTFILES_EDITOR_HANDOFF_INSTANCE'
local HANDOFF_GENERATION_ENV = 'DOTFILES_EDITOR_HANDOFF_GENERATION'
local HANDOFF_DATA_KEY = 'terminal_tool_id'
local HANDOFF_DATA_INSTANCE_KEY = 'terminal_tool_instance'
local HANDOFF_DATA_GENERATION_KEY = 'terminal_tool_generation'
local HANDOFF_ACK_DELAY_MS = 300
local SHUTDOWN_WAIT_MS = 1000
local SINGLETON_INSTANCE_KEY = {}

local tools = {}
local tool_keys = {}
local tool_commands = {}
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

local function job_env(id, instance, generation, extra_env)
  local env = vim.deepcopy(extra_env or {})
  env[HANDOFF_SOURCE_ENV] = id
  env[HANDOFF_INSTANCE_ENV] = instance.token
  env[HANDOFF_GENERATION_ENV] = tostring(generation)

  for name, value in pairs(editor_env()) do
    env[name] = value
  end
  return env
end

-- Failures about a requested input pass their own variant, because rollback
-- clears the running one before the message is built.
local function notify(tool, message, level, variant)
  local named = variant or tool.spec.variants[1]
  vim.notify(string.format('%s: %s', named and named.desc or tool.spec.desc, message), level, { title = 'Terminal tool' })
end

local function valid_window(win) return win ~= nil and vim.api.nvim_win_is_valid(win) end

local function valid_tab(tab) return tab ~= nil and vim.api.nvim_tabpage_is_valid(tab) end

local function restore_window(win)
  if valid_window(win) then pcall(vim.api.nvim_set_current_win, win) end
end

local function canonical_cwd(cwd)
  if vim.uv and vim.uv.fs_realpath then
    local ok, resolved = pcall(vim.uv.fs_realpath, cwd)
    if ok and resolved and resolved ~= '' then cwd = resolved end
  end
  if vim.fs and vim.fs.normalize then
    local ok, normalized = pcall(vim.fs.normalize, cwd)
    if ok and normalized and normalized ~= '' then cwd = normalized end
  end
  return cwd
end

local function instance_for_tab(tool, tab)
  for _, instance in pairs(tool.instances) do
    if instance.tab == tab and valid_tab(tab) then return instance end
  end
  return nil
end

local function tab_is_tool(tab)
  for _, registered in pairs(tools) do
    if instance_for_tab(registered, tab) then return true end
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

local function close_tool_tab(tool, instance)
  forget_stale_tab(instance)
  if not instance.tab then return true end

  local tab = instance.tab
  if vim.api.nvim_get_current_tabpage() == tab and not focus_host_window() then return false end
  local ok = pcall(vim.api.nvim_tabpage_close, tab, false)
  if not ok and valid_tab(tab) then return false end
  instance.tab = nil
  instance.win = nil
  return true
end

local function unregister_instance(tool, instance)
  if tool.instances[instance.key] == instance then tool.instances[instance.key] = nil end
  if tool.instances_by_token[instance.token] == instance then tool.instances_by_token[instance.token] = nil end
end

local function current_generation(tool, instance, generation)
  return tool.instances[instance.key] == instance and tool.instances_by_token[instance.token] == instance and instance.generation == generation
end

local function clear_generation(tool, instance, generation, buf, retried)
  if not current_generation(tool, instance, generation) or instance.buf ~= buf then return false end

  local tab_closed = close_tool_tab(tool, instance)
  local buffer_deleted = delete_buffer(buf)
  if not tab_closed or not buffer_deleted then
    if not retried then
      vim.schedule(function() clear_generation(tool, instance, generation, buf, true) end)
    else
      notify(tool, 'could not clean up its finished process', vim.log.levels.WARN)
    end
    return false
  end

  instance.buf = nil
  instance.job = nil
  instance.cwd = nil
  instance.variant = nil
  unregister_instance(tool, instance)
  return true
end

local function open_tool_tab(tool, instance)
  forget_stale_tab(instance)
  local previous_win = vim.api.nvim_get_current_win()
  local created_tab = false

  local ok, err = pcall(function()
    if instance.tab then
      vim.api.nvim_set_current_tabpage(instance.tab)
      if not valid_window(instance.win) then instance.win = vim.api.nvim_tabpage_list_wins(instance.tab)[1] end
    else
      vim.cmd.tabnew()
      created_tab = true
      instance.tab = vim.api.nvim_get_current_tabpage()
      instance.win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_win_set_buf(instance.win, instance.buf)
  end)

  if ok then return true end

  if created_tab and valid_tab(instance.tab) then pcall(vim.api.nvim_tabpage_close, instance.tab, false) end
  instance.tab = nil
  instance.win = nil
  restore_window(previous_win)
  notify(tool, 'could not open its Tool Tab: ' .. tostring(err), vim.log.levels.ERROR)
  return false
end

local function focus_terminal(tool, instance)
  if not open_tool_tab(tool, instance) then return false end
  return pcall(function()
    vim.api.nvim_set_current_win(instance.win)
    vim.cmd.startinsert()
  end)
end

local function stop_generation(tool, instance, preserve_tab)
  local buf = instance.buf
  if instance.job then pcall(vim.fn.jobstop, instance.job) end

  if not preserve_tab and not close_tool_tab(tool, instance) then return false end
  if not delete_buffer(buf) then return false end
  instance.buf = nil
  instance.job = nil
  instance.cwd = nil
  instance.variant = nil
  return true
end

local function stop_all_jobs()
  local stopping = {}
  for _, tool in pairs(tools) do
    for _, instance in pairs(tool.instances) do
      local job = instance.job
      if job then
        local ok, stopped = pcall(vim.fn.jobstop, job)
        if ok and stopped == 1 then stopping[#stopping + 1] = job end
      end
    end
  end

  if #stopping > 0 then pcall(vim.fn.jobwait, stopping, SHUTDOWN_WAIT_MS) end
end

local lifecycle_group = vim.api.nvim_create_augroup('custom-terminal-tool-lifecycle', { clear = true })
local ui_entered = vim.v.vim_did_enter == 1
vim.api.nvim_create_autocmd('UIEnter', {
  group = lifecycle_group,
  once = true,
  callback = function() ui_entered = true end,
  desc = 'Record terminal UI initialization',
})
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = lifecycle_group,
  callback = stop_all_jobs,
  desc = 'Stop terminal tools before Neovim exits',
})

local function after_ui_enter(callback)
  local pending = false

  return function()
    if pending then return true end
    if ui_entered then return callback() end

    pending = true
    vim.api.nvim_create_autocmd('UIEnter', {
      group = lifecycle_group,
      once = true,
      callback = function()
        -- Neovim settles terminal capabilities during startup. Waiting until
        -- after UIEnter keeps +cmd launches identical to interactive mappings.
        vim.schedule(function()
          pending = false
          callback()
        end)
      end,
      desc = 'Start terminal tool after UI initialization',
    })
    return true
  end
end

local function start_tool(tool, instance, variant, cwd, return_win)
  instance.generation = instance.generation + 1
  local generation = instance.generation

  local ok, buf_or_error = pcall(vim.api.nvim_create_buf, false, true)
  if not ok then
    if not instance.tab then unregister_instance(tool, instance) end
    restore_window(return_win)
    notify(tool, 'could not create its terminal buffer: ' .. tostring(buf_or_error), vim.log.levels.ERROR, variant)
    return false
  end

  local buf = buf_or_error
  instance.buf = buf
  instance.cwd = cwd
  instance.variant = variant
  if not open_tool_tab(tool, instance) then
    clear_generation(tool, instance, generation, buf)
    restore_window(return_win)
    return false
  end

  local started, job = pcall(vim.api.nvim_win_call, instance.win, function()
    return vim.fn.jobstart(vim.deepcopy(variant.command), {
      term = true,
      cwd = cwd,
      env = job_env(tool.spec.id, instance, generation, tool.spec.env),
      on_exit = function()
        vim.schedule(function() clear_generation(tool, instance, generation, buf) end)
      end,
    })
  end)

  if not started or job <= 0 then
    clear_generation(tool, instance, generation, buf)
    restore_window(return_win)
    local reason
    if not started then
      reason = 'could not start its job: ' .. tostring(job)
    else
      reason = job == -1 and ('executable not found: ' .. variant.command[1]) or 'Neovim could not start the job'
    end
    notify(tool, reason, vim.log.levels.ERROR, variant)
    return false
  end

  -- A very short-lived job may exit before jobstart returns. Its callback owns
  -- cleanup, so do not restore handles from a generation that already ended.
  if not current_generation(tool, instance, generation) or instance.buf ~= buf then
    restore_window(return_win)
    return false
  end
  instance.job = job
  local focused, focus_error = focus_terminal(tool, instance)
  if not focused then
    pcall(vim.fn.jobstop, job)
    clear_generation(tool, instance, generation, buf)
    restore_window(return_win)
    notify(tool, 'could not focus its Tool Tab: ' .. tostring(focus_error), vim.log.levels.ERROR, variant)
    return false
  end
  return true
end

local function new_instance(tool, key)
  tool.next_instance_token = tool.next_instance_token + 1
  local instance = {
    key = key,
    token = tostring(tool.next_instance_token),
    generation = 0,
    buf = nil,
    win = nil,
    tab = nil,
    job = nil,
    cwd = nil,
    variant = nil,
  }
  tool.instances[key] = instance
  tool.instances_by_token[instance.token] = instance
  return instance
end

local function instance_key(tool, cwd)
  if tool.spec.instances == 'cwd' then return canonical_cwd(cwd) end
  return SINGLETON_INSTANCE_KEY
end

local function toggle(tool, variant)
  local current_win = vim.api.nvim_get_current_win()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local current_instance = instance_for_tab(tool, current_tab)

  -- Only the running variant's own key hides the Tool Tab. Another variant's
  -- key retargets this instance instead of toggling it closed.
  if current_instance and current_instance.variant == variant then return focus_host_window() end
  if not current_tab_is_tool() then host_win = current_win end

  local cwd = host_cwd()
  if not cwd then
    notify(tool, 'could not determine the Host Window working directory', vim.log.levels.ERROR, variant)
    return false
  end

  local key = instance_key(tool, cwd)
  local instance = tool.instances[key] or new_instance(tool, key)
  forget_stale_tab(instance)

  if instance.buf and not vim.api.nvim_buf_is_valid(instance.buf) and not stop_generation(tool, instance, false) then return false end
  local changed_cwd = tool.spec.instances == 'singleton' and instance.cwd ~= cwd
  if instance.buf and (changed_cwd or instance.variant ~= variant) and not stop_generation(tool, instance, true) then return false end

  if instance.buf then
    local focused, focus_error = focus_terminal(tool, instance)
    if not focused then
      notify(tool, 'could not focus its Tool Tab: ' .. tostring(focus_error), vim.log.levels.ERROR, variant)
      restore_window(current_win)
      return false
    end
    return true
  end

  local launch_cwd = tool.spec.instances == 'cwd' and key or cwd
  return start_tool(tool, instance, variant, launch_cwd, current_win)
end

local function acknowledge_editor_return(tool, instance)
  local generation = instance.generation
  local job = instance.job
  if not job then return end

  vim.defer_fn(function()
    if not current_generation(tool, instance, generation) or instance.job ~= job then return end

    local ok, sent = pcall(vim.fn.chansend, job, '\r')
    if not ok or sent == 0 then notify(tool, 'could not acknowledge editor return', vim.log.levels.WARN) end
  end, HANDOFF_ACK_DELAY_MS)
end

local function handoff_instance(data)
  if type(data) ~= 'table' then return nil, nil end
  local tool = tools[data[HANDOFF_DATA_KEY]]
  if not tool then return nil, nil end
  local instance = tool.instances_by_token[data[HANDOFF_DATA_INSTANCE_KEY]]
  if not instance then return nil, nil end
  if tostring(instance.generation) ~= data[HANDOFF_DATA_GENERATION_KEY] or not instance.job then return nil, nil end
  return tool, instance
end

local function assert_nonempty_string(value, message)
  assert(type(value) == 'string' and value ~= '', message)
  return value
end

local function normalize_variant(variant, declared_keys, declared_ex_commands, existing_ex_commands)
  local key = assert_nonempty_string(variant.key, 'terminal tool key is required')
  assert(tool_keys[key] == nil, string.format('terminal tool key %s is already registered by %s', key, tool_keys[key] or ''))
  assert(not declared_keys[key], 'terminal tool declares key more than once: ' .. key)
  -- maparg applies <leader> and key-notation semantics exactly as
  -- vim.keymap.set does; the keymap-list APIs expose only normalized lhs text.
  local existing_mapping = vim.fn.maparg(key, 'n', false, true)
  assert(type(existing_mapping) == 'table' and next(existing_mapping) == nil, 'terminal tool key is already mapped by Neovim: ' .. key)
  declared_keys[key] = true

  local command = variant.command
  assert(type(command) == 'table' and #command > 0, 'terminal tool command must be a non-empty argv table')
  for index, value in ipairs(command) do
    assert_nonempty_string(value, string.format('terminal tool command argument %d must be a non-empty string', index))
  end

  local ex_command = variant.ex_command
  if ex_command ~= nil then
    assert_nonempty_string(ex_command, 'terminal tool Ex command must be a non-empty string')
    assert(
      ex_command:match '^[A-Z][A-Za-z0-9]*$' and ex_command ~= 'Next',
      'terminal tool Ex command must start with an uppercase ASCII letter and contain only ASCII letters or digits'
    )
    assert(not declared_ex_commands[ex_command], 'terminal tool declares Ex command more than once: ' .. ex_command)
    assert(
      tool_commands[ex_command] == nil,
      string.format('terminal tool Ex command %s is already registered by %s', ex_command, tool_commands[ex_command] or '')
    )
    assert(existing_ex_commands[ex_command] == nil, 'terminal tool Ex command is already registered by Neovim: ' .. ex_command)
    declared_ex_commands[ex_command] = true
  end

  return {
    key = key,
    desc = assert_nonempty_string(variant.desc, 'terminal tool desc is required'),
    command = vim.deepcopy(command),
    ex_command = ex_command,
  }
end

local function normalize_config(config)
  assert(type(config) == 'table', 'terminal tool config must be a table')

  local id = assert_nonempty_string(config.id, 'terminal tool id is required')
  assert(id:match '^[%w_-]+$', 'terminal tool id may contain only letters, numbers, underscores, and hyphens')
  assert(tools[id] == nil, 'terminal tool id is already registered: ' .. id)

  -- A tool declares either one command or several input variants that share its
  -- single Tool Tab, process slot, and handoff policy.
  local declared_variants = config.variants
  if declared_variants == nil then
    assert(config.command ~= nil, 'terminal tool requires a command or a variants list')
    declared_variants = { { key = config.key, desc = config.desc, command = config.command } }
  else
    assert(type(declared_variants) == 'table', 'terminal tool variants must be a list')
    assert(
      config.key == nil and config.command == nil and config.desc == nil,
      'terminal tool variants own key, command, and desc; do not also declare them at the top level'
    )
    -- A gap or string key would make ipairs stop early and silently drop an input.
    local counted = 0
    for _ in pairs(declared_variants) do
      counted = counted + 1
    end
    assert(counted == #declared_variants, 'terminal tool variants must be a gapless list without named entries')
    assert(#declared_variants > 1, 'declare a single input with a top-level command instead of a one-element variants list')
  end

  local declared_keys = {}
  local declared_ex_commands = {}
  local declared_commands = {}
  local existing_ex_commands = vim.api.nvim_get_commands { builtin = false }
  local variants = {}
  for _, variant in ipairs(declared_variants) do
    assert(type(variant) == 'table', 'each terminal tool variant must be a table')
    local normalized = normalize_variant(variant, declared_keys, declared_ex_commands, existing_ex_commands)
    local argv = table.concat(normalized.command, '\0')
    assert(not declared_commands[argv], 'terminal tool declares the same command more than once: ' .. table.concat(normalized.command, ' '))
    declared_commands[argv] = true
    variants[#variants + 1] = normalized
  end

  local handoff = config.handoff or 'return'
  assert(handoff == 'return' or handoff == 'return-and-acknowledge', "terminal tool handoff must be 'return' or 'return-and-acknowledge'")

  local instances = config.instances or 'singleton'
  assert(instances == 'singleton' or instances == 'cwd', "terminal tool instances must be 'singleton' or 'cwd'")

  local env = config.env or {}
  assert(type(env) == 'table', 'terminal tool env must be a table')
  local reserved_env = {
    [HANDOFF_SOURCE_ENV] = true,
    [HANDOFF_INSTANCE_ENV] = true,
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
    desc = variants[1].desc,
    variants = variants,
    env = vim.deepcopy(env),
    handoff = handoff,
    instances = instances,
  }
end

---@class custom.TerminalToolVariant
---@field command string[]
---@field key string
---@field desc string
---@field ex_command? string

---@class custom.TerminalToolConfig
---@field id string
---@field command? string[] single-command shape; mutually exclusive with variants
---@field key? string
---@field desc? string
---@field variants? custom.TerminalToolVariant[] input variants sharing one Tool Tab
---@field env? table<string, string>
---@field handoff? 'return'|'return-and-acknowledge'
---@field instances? 'singleton'|'cwd'

---@param config custom.TerminalToolConfig
function M.create(config)
  local tool = {
    spec = normalize_config(config),
    instances = {},
    instances_by_token = {},
    next_instance_token = 0,
  }

  local registrations = {}
  for _, variant in ipairs(tool.spec.variants) do
    local callback = function() return toggle(tool, variant) end
    if variant.ex_command then callback = after_ui_enter(callback) end
    registrations[#registrations + 1] = {
      variant = variant,
      callback = callback,
    }
  end

  local registered_commands = {}
  local registered_mappings = {}
  local registered, registration_error = pcall(function()
    -- Register commands first with replacement disabled. All predictable
    -- conflicts were preflighted, and rollback still covers an API failure.
    for _, registration in ipairs(registrations) do
      local variant = registration.variant
      if variant.ex_command then
        vim.api.nvim_create_user_command(variant.ex_command, registration.callback, { desc = variant.desc, force = false })
        registered_commands[#registered_commands + 1] = variant.ex_command
      end
    end

    for _, registration in ipairs(registrations) do
      local variant = registration.variant
      vim.keymap.set('n', variant.key, registration.callback, { desc = variant.desc })
      registered_mappings[#registered_mappings + 1] = variant.key
    end
  end)

  if not registered then
    for index = #registered_mappings, 1, -1 do
      pcall(vim.keymap.del, 'n', registered_mappings[index])
    end
    for index = #registered_commands, 1, -1 do
      pcall(vim.api.nvim_del_user_command, registered_commands[index])
    end
    error(registration_error, 0)
  end

  for _, variant in ipairs(tool.spec.variants) do
    tool_keys[variant.key] = tool.spec.id
    if variant.ex_command then tool_commands[variant.ex_command] = tool.spec.id end
  end
  tools[tool.spec.id] = tool
end

---@return table
function M.editor_handoff_data()
  local id = vim.env[HANDOFF_SOURCE_ENV]
  local instance = vim.env[HANDOFF_INSTANCE_ENV]
  local generation = vim.env[HANDOFF_GENERATION_ENV]
  if id == nil or id == '' or instance == nil or instance == '' or generation == nil or generation == '' then return {} end
  return {
    [HANDOFF_DATA_KEY] = id,
    [HANDOFF_DATA_INSTANCE_KEY] = instance,
    [HANDOFF_DATA_GENERATION_KEY] = generation,
  }
end

---@param data? table
---@return integer? win
function M.editor_handoff_window(data)
  if not handoff_instance(data) then return nil end
  return find_host_window()
end

---@param data? table
---@return boolean handled
function M.complete_editor_handoff(data)
  local tool, instance = handoff_instance(data)
  if not tool then return false end
  if not focus_host_window() then
    notify(tool, 'could not return to the Host Window after editor handoff', vim.log.levels.WARN)
    return false
  end
  if tool.spec.handoff == 'return-and-acknowledge' then acknowledge_editor_return(tool, instance) end
  return true
end

return M
