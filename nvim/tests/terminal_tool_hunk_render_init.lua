vim.o.mouse = 'a'
vim.g.mapleader = ' '

local fixture = assert(vim.env.HUNK_RENDER_FIXTURE, 'HUNK_RENDER_FIXTURE is required')
local second_fixture = assert(vim.env.HUNK_RENDER_SECOND_FIXTURE, 'HUNK_RENDER_SECOND_FIXTURE is required')
local repo_root = assert(vim.env.DOTFILES_REPO_ROOT, 'DOTFILES_REPO_ROOT is required')
local start_mode = vim.env.HUNK_RENDER_START_MODE or 'manual'
vim.cmd.cd(vim.fn.fnameescape(fixture))
vim.opt.runtimepath:prepend(repo_root .. '/nvim')
package.path = table.concat({
  repo_root .. '/nvim/lua/?.lua',
  repo_root .. '/nvim/lua/?/init.lua',
  package.path,
}, ';')

local host_tabs = { vim.api.nvim_get_current_tabpage() }

local function invoke_hunk()
  local mapping = vim.fn.maparg('<leader>gd', 'n', false, true)
  return assert(mapping.callback, 'Hunk mapping is not registered')()
end

function _G.HunkRenderOpenSecond()
  vim.cmd.tabnew()
  host_tabs[2] = vim.api.nvim_get_current_tabpage()
  vim.cmd.lcd(vim.fn.fnameescape(second_fixture))
  invoke_hunk()
  return true
end

function _G.HunkRenderOpen(index)
  local tab = assert(host_tabs[index], 'unknown Hunk render Host Window')
  vim.api.nvim_set_current_tabpage(tab)
  vim.api.nvim_set_current_win(vim.api.nvim_tabpage_list_wins(tab)[1])
  invoke_hunk()
  return true
end

function _G.HunkRenderTerminalBufferCount()
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then count = count + 1 end
  end
  return count
end

function _G.HunkRenderTerminalPids()
  local pids = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'terminal' then
      local job = vim.b[buf].terminal_job_id
      local pid = job and vim.fn.jobpid(job) or nil
      if pid and pid > 0 then pids[#pids + 1] = pid end
    end
  end
  return pids
end

require 'custom.plugins.hunk'

if start_mode == 'manual' then
  vim.defer_fn(invoke_hunk, 100)
elseif start_mode ~= 'startup' then
  error('unknown HUNK_RENDER_START_MODE: ' .. start_mode)
end
