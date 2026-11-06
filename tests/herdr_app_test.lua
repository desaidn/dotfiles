local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')))
local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch, 'p')

local function read(path)
  return table.concat(vim.fn.readfile(path), '\n')
end

local function copy(source, target)
  vim.fn.writefile(vim.fn.readfile(source, 'b'), target, 'b')
end

local function check(app, path, home)
  vim.fn.mkdir(home, 'p')
  local result = vim.system({ app, 'check', path }, {
    env = { HERDR_APP_HOME = home },
    text = true,
  }):wait(30000)
  assert(result.code == 0, (result.stdout or '') .. (result.stderr or ''))
end

local ok, err = pcall(function()
  for _, file in ipairs {
    'keys.json',
    'settings.json',
    'themes/terminal.json',
    'templates/shared.json',
    'mods/legacy-prefix/mod.json',
  } do
    vim.json.decode(read(root .. '/herdr-app/' .. file))
  end
  local keys = vim.json.decode(read(root .. '/herdr-app/keys.json'))
  assert(keys.global['ctrl-b'] == 'mod.open:legacy-prefix', 'Ctrl+B must open the installed prefix mod')
  print('ok - Herdr app configuration parses and connects Ctrl+B to its mod')

  local app = vim.fn.exepath('herdr-app')
  assert(app ~= '', 'herdr-app is required for native mod checks')
  local mod = scratch .. '/legacy-prefix'
  vim.fn.mkdir(mod, 'p')
  for _, file in ipairs { 'main.js', 'mod.json' } do
    assert(vim.uv.fs_symlink(root .. '/herdr-app/mods/legacy-prefix/' .. file, mod .. '/' .. file))
  end
  check(app, mod, scratch .. '/app-home')
  print('ok - Linked prefix mod passes its native load and render check')

  local fixture = scratch .. '/prefix-behavior'
  vim.fn.mkdir(fixture, 'p')
  copy(root .. '/tests/fixtures/herdr-app/prefix/main.js', fixture .. '/main.js')
  copy(root .. '/herdr-app/mods/legacy-prefix/main.js', fixture .. '/prefix.js')
  check(app, fixture, scratch .. '/fixture-home')
  print('ok - Prefix tab/agent selection, remote addresses, and modifier handling')
end)

vim.fn.delete(scratch, 'rf')
if not ok then
  io.stderr:write(tostring(err), '\n')
  vim.cmd('cquit 1')
end
