local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')
local fixture_root = nvim_root .. '/tests/fixtures/web-colors'
vim.o.verbose = 0

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local snapshot = require 'custom.lib.web_color_snapshot'
local command = arg[1]

if command == 'capture' then
  local output = assert(arg[2], 'usage: ... capture <output.json> [typescript-project-root]')
  local typescript_root = vim.fs.normalize(arg[3] or vim.env.HOME .. '/Projects/desaidn.dev')
  local captured = snapshot.capture(nvim_root, fixture_root, typescript_root)
  snapshot.write(output, captured)
  for _, line in ipairs(snapshot.summary(captured)) do
    io.stdout:write(line, '\n')
  end
  io.stdout:write('Snapshot: ', vim.fs.normalize(output), '\n')
  vim.cmd.quitall()
elseif command == 'compare' then
  local left_path = assert(arg[2], 'usage: ... compare <left.json> <right.json>')
  local right_path = assert(arg[3], 'usage: ... compare <left.json> <right.json>')
  local color_differences, evidence_differences = snapshot.compare(snapshot.read(left_path), snapshot.read(right_path))

  if #color_differences == 0 then
    io.stdout:write 'COLOR MATCH\n'
  else
    io.stderr:write 'COLOR MISMATCH\n'
    for _, difference in ipairs(color_differences) do
      io.stderr:write('  ', difference, '\n')
    end
  end

  if #evidence_differences == 0 then
    io.stdout:write 'EVIDENCE MATCH\n'
  else
    io.stdout:write 'Evidence differences:\n'
    for _, difference in ipairs(evidence_differences) do
      io.stdout:write('  ', difference, '\n')
    end
  end

  if #color_differences > 0 then
    vim.cmd 'cquit 1'
  else
    vim.cmd.quitall()
  end
else
  error(
    'usage: nvim --headless -u '
      .. nvim_root
      .. '/init.lua -l '
      .. script_path
      .. ' {capture <output.json> [typescript-project-root]|compare <left.json> <right.json>}'
  )
end
