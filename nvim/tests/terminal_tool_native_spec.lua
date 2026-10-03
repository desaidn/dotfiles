local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local nvim_root = vim.fs.dirname(vim.fs.dirname(script))
vim.opt.runtimepath:prepend(nvim_root)
package.path = nvim_root .. '/lua/?.lua;' .. nvim_root .. '/lua/?/init.lua;' .. package.path

local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, 'p')
fixture = assert(vim.uv.fs_realpath(fixture))
local original_cwd = assert(vim.fn.getcwd())
local notifications = {}
local function capture_notification(message) notifications[#notifications + 1] = message end
vim.notify = capture_notification

local function git(...)
  local result = vim
    .system({ 'git', ... }, {
      text = true,
      clear_env = true,
      env = { PATH = vim.env.PATH, HOME = fixture, GIT_CONFIG_GLOBAL = '/dev/null', GIT_CONFIG_NOSYSTEM = '1' },
    })
    :wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local failures = {}
local function check(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    print('PASS ' .. name)
  else
    failures[#failures + 1] = name
    io.stderr:write('FAIL ' .. name .. '\n' .. tostring(err) .. '\n')
  end
end

local function invoke(key)
  vim.cmd.stopinsert()
  return assert(vim.fn.maparg(key, 'n', false, true).callback, 'missing tool mapping')()
end

local function terminal()
  local buf = vim.api.nvim_get_current_buf()
  assert(vim.bo[buf].buftype == 'terminal', 'tool did not select a terminal buffer')
  return { buf = buf, job = vim.b[buf].terminal_job_id, tab = vim.api.nvim_get_current_tabpage() }
end

local function running(job) return vim.fn.jobwait({ job }, 0)[1] == -1 end

local function await(message, callback) assert(vim.wait(3000, callback, 10), message) end

local function assert_cwd(tool, expected)
  assert(vim.api.nvim_buf_get_name(tool.buf):find('term://' .. expected .. '//', 1, true) == 1, 'tool launched in the wrong directory')
end

local function host(path)
  vim.cmd.tabnew()
  vim.cmd.lcd(vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_win()
end

local tool = require 'custom.lib.terminal_tool'
tool.create {
  id = 'native_repo',
  instances = 'repo',
  variants = {
    { key = '<F5>', desc = 'Native checkout fixture', command = { '/bin/cat' } },
    { key = '<F6>', desc = 'Native checkout variant', command = { '/bin/sh', '-c', 'exec /bin/cat' } },
  },
}
tool.create { id = 'native_singleton', key = '<F7>', desc = 'Native singleton fixture', command = { '/bin/cat' } }

local repo = fixture .. '/repo'
local worktree = fixture .. '/worktree'
git('init', '--template=', repo)
git(
  '-C',
  repo,
  '-c',
  'user.name=Fixture',
  '-c',
  'user.email=fixture@example.invalid',
  '-c',
  'core.hooksPath=/dev/null',
  'commit',
  '--allow-empty',
  '-m',
  'Fixture'
)
git('-C', repo, 'worktree', 'add', '--detach', worktree)
vim.fn.mkdir(repo .. '/nested/deeper', 'p')
assert(vim.uv.fs_symlink(repo, fixture .. '/alias', { dir = true }))

local first
local second
local first_host
local latest_host

check('checkout instances collapse subdirectories and aliases but keep worktrees distinct', function()
  first_host = host(repo .. '/nested')
  assert(invoke '<F5>')
  first = terminal()
  assert_cwd(first, repo)
  assert(invoke '<F5>')
  vim.cmd.lcd(vim.fn.fnameescape(repo .. '/nested/deeper'))
  assert(invoke '<F5>')
  assert(terminal().job == first.job, 'subdirectory started another checkout process')
  assert(invoke '<F5>')
  vim.cmd.lcd(vim.fn.fnameescape(fixture .. '/alias'))
  assert(invoke '<F5>')
  assert(terminal().job == first.job, 'symlink alias started another checkout process')
  latest_host = host(worktree)
  assert(invoke '<F5>')
  second = terminal()
  assert(second.job ~= first.job and running(first.job), 'worktree did not retain its independent process')
  assert_cwd(second, worktree)
end)

check('native navigation selects the latest Host Window and explicit scoped cwd', function()
  assert(first and second and latest_host)
  vim.api.nvim_set_current_win(first_host)
  vim.api.nvim_set_current_win(latest_host)
  vim.api.nvim_set_current_tabpage(first.tab)
  assert(invoke '<F5>')
  assert(vim.api.nvim_get_current_win() == latest_host, 'native navigation left a stale Host Window')
  vim.api.nvim_set_current_tabpage(first.tab)
  assert(invoke '<F7>')
  assert_cwd(terminal(), worktree)
end)

check('changing a variant retains the viewed checkout and native tab identity', function()
  assert(first and second)
  vim.api.nvim_set_current_tabpage(first.tab)
  assert(invoke '<F6>')
  local replacement = terminal()
  assert(replacement.tab == first.tab, 'variant change recreated its Tool Tab')
  assert_cwd(replacement, repo)
  assert(replacement.job ~= first.job, 'variant change reused its old process')
  await('old variant process remained alive', function() return not running(first.job) end)
  assert(running(second.job), 'variant change stopped another checkout')
  first = replacement
end)

check('native tabclose hides a live terminal and invocation recreates only its tab', function()
  assert(first)
  vim.api.nvim_set_current_tabpage(first.tab)
  vim.cmd.tabclose()
  assert(running(first.job), 'native tabclose stopped its terminal job')
  vim.api.nvim_set_current_win(first_host)
  assert(invoke '<F6>')
  local reopened = terminal()
  assert(reopened.job == first.job and reopened.buf == first.buf, 'native tabclose lost its persistent process')
  assert(reopened.tab ~= first.tab, 'tabclose did not recreate the tab')
  first = reopened
end)

check('process exit closes a Tool Tab with an ordinary split and remains retryable', function()
  assert(first)
  vim.api.nvim_set_current_tabpage(first.tab)
  vim.cmd.vnew()
  vim.fn.jobstop(first.job)
  await('finished Tool Tab with a split remained open', function() return not vim.api.nvim_tabpage_is_valid(first.tab) end)
  assert(not vim.api.nvim_buf_is_valid(first.buf), 'finished terminal buffer remained valid')
  vim.api.nvim_set_current_win(first_host)
  assert(invoke '<F5>')
  first = terminal()
  assert(running(first.job), 'tool could not relaunch after exit')
end)

check('cleanup preserves modified ordinary buffers without blocking relaunch', function()
  assert(first)
  vim.api.nvim_set_current_tabpage(first.tab)
  vim.cmd.vnew()
  local modified = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(modified, 0, -1, false, { 'keep this unsaved work' })
  local was_hidden = vim.o.hidden
  vim.o.hidden = false
  vim.fn.jobstop(first.job)
  await('finished terminal buffer was not cleaned up', function() return not vim.api.nvim_buf_is_valid(first.buf) end)
  assert(vim.api.nvim_buf_is_valid(modified) and vim.bo[modified].modified, 'cleanup discarded the modified buffer')
  assert(vim.api.nvim_tabpage_is_valid(first.tab), 'cleanup force-closed the modified split')
  vim.api.nvim_set_current_win(first_host)
  assert(invoke '<F5>')
  assert(terminal().tab ~= first.tab, 'relaunch reclaimed the preserved ordinary tab')
  assert(vim.api.nvim_buf_get_lines(modified, 0, -1, false)[1] == 'keep this unsaved work', 'cleanup changed unsaved content')
  vim.o.hidden = was_hidden
end)

check('repository tools reject directories outside a checkout without opening a tab', function()
  host(fixture)
  local tabs = #vim.api.nvim_list_tabpages()
  assert(not invoke '<F5>', 'tool accepted a directory outside a checkout')
  assert(#vim.api.nvim_list_tabpages() == tabs, 'failed checkout discovery left a Tool Tab')
end)

check('a failed buffer display rolls back its native tab and remains retryable', function()
  tool.create { id = 'native_rollback', key = '<F8>', desc = 'Native rollback fixture', command = { '/bin/cat' } }
  local tabs = #vim.api.nvim_list_tabpages()
  local set_buf = vim.api.nvim_win_set_buf
  local function fail_display() error 'injected buffer-display failure' end
  vim.api.nvim_win_set_buf = fail_display
  local ok, result = pcall(invoke, '<F8>')
  vim.api.nvim_win_set_buf = set_buf
  assert(ok and not result, 'buffer-display failure did not report a failed launch')
  assert(#vim.api.nvim_list_tabpages() == tabs, 'failed buffer display left its provisional Tool Tab')
  assert(invoke '<F8>', 'failed buffer display blocked a subsequent launch')
  assert(running(terminal().job), 'retry did not start a live process')
end)

vim.api.nvim_exec_autocmds('VimLeavePre', {})
vim.wait(100, function() return false end, 10)
vim.cmd.tabonly { bang = true }
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fs.rm(fixture, { recursive = true, force = true })
if #failures > 0 then error(table.concat(failures, ', ')) end
print 'terminal_tool native regression checks passed'
