local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')

local function fail(message)
  io.stderr:write('FAIL ', message, '\n')
  vim.cmd.cquit { args = { '1' } }
end

local function hover_server(dispatchers)
  local closing = false
  local request_id = 0

  return {
    request = function(method, _, callback)
      request_id = request_id + 1
      if method == 'initialize' then
        callback(nil, { capabilities = { hoverProvider = true } }, request_id)
      elseif method == 'textDocument/hover' then
        callback(nil, {
          contents = {
            kind = 'markdown',
            value = '```lua\nlocal value = 42\n```',
          },
        }, request_id)
      elseif method == 'shutdown' then
        callback(nil, nil, request_id)
      end
      return true, request_id
    end,
    notify = function(method)
      if method == 'exit' then dispatchers.on_exit(0, 15) end
      return true
    end,
    is_closing = function() return closing end,
    terminate = function() closing = true end,
  }
end

local function find_hover_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    local buf = vim.api.nvim_win_get_buf(win)
    if config.relative ~= '' and vim.bo[buf].filetype == 'markdown' then return win end
  end
end

local function capture_screen()
  local rows = {}
  for row = 1, vim.o.lines do
    local cells = {}
    for col = 1, vim.o.columns do
      cells[#cells + 1] = vim.fn.screenstring(row, col)
    end
    rows[#rows + 1] = table.concat(cells)
  end
  return rows
end

vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

vim.cmd.syntax 'enable'
vim.o.columns = 80
vim.o.lines = 24
vim.o.laststatus = 0
vim.o.swapfile = false
vim.o.winborder = 'rounded'

local source_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_win_set_buf(0, source_buf)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'hover_target' })
vim.bo.filetype = 'text'
vim.api.nvim_win_set_cursor(0, { 1, 0 })

local client_id = vim.lsp.start({
  name = 'hover-fixture',
  cmd = hover_server,
  root_dir = nvim_root,
}, { attach = true })

if not client_id then
  fail 'failed to start the fixture LSP client'
  return
end

if not vim.wait(5000, function() return #vim.lsp.get_clients { bufnr = 0 } > 0 end, 20) then
  fail 'timed out waiting for the fixture LSP client'
  return
end

local k_mapping = vim.fn.maparg('K', 'n', false, true)
if type(k_mapping.callback) ~= 'function' then
  fail 'K did not resolve to an attached LSP hover mapping'
  return
end

vim.api.nvim_feedkeys('K', 'mx', false)

local hover_win
if not vim.wait(5000, function()
  hover_win = find_hover_window()
  return hover_win ~= nil
end, 20) then
  fail 'timed out waiting for a markdown hover float after K'
  return
end

local hover_buf = vim.api.nvim_win_get_buf(hover_win)
local expected = 'local value = 42'
if not vim.tbl_contains(vim.api.nvim_buf_get_lines(hover_buf, 0, -1, false), expected) then
  fail 'fixture documentation was missing from the hover buffer'
  return
end

vim.cmd.redraw { bang = true }

local screen = capture_screen()
local rendered = table.concat(screen, '\n')
if not rendered:find(expected, 1, true) then
  local position = vim.api.nvim_win_get_position(hover_win)
  local visible = {}
  local last_row = position[1] + vim.api.nvim_win_get_height(hover_win) + 2
  for row = math.max(1, position[1]), math.min(vim.o.lines, last_row) do
    visible[#visible + 1] = screen[row]
  end
  fail(('LSP hover documentation is clipped after K; expected screen text %q, saw:\n%s'):format(expected, table.concat(visible, '\n')))
  return
end

io.stdout:write(('PASS K opened an LSP hover with complete screen text %q\n'):format(expected))
vim.cmd.qa { bang = true }
