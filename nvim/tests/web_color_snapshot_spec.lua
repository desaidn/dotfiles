local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local snapshot = require 'custom.lib.web_color_snapshot'

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end
  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function sample(rendered)
  return {
    environment = { nvim = 'NVIM v0.12.4' },
    artifacts = { parsers = { { language = 'tsx', sha256 = 'same' } } },
    tokens = {
      {
        file = 'card.tsx',
        label = 'component',
        rendered = rendered,
        contributors = { { group = '@function.tsx' } },
      },
    },
  }
end

check('identical snapshots match', function()
  local colors, evidence = snapshot.compare(sample 'fg=#ffb86c', sample 'fg=#ffb86c')
  assert(#colors == 0)
  assert(#evidence == 0)
end)

check('resolved color drift is a color failure', function()
  local colors = snapshot.compare(sample 'fg=#ffb86c', sample 'fg=#00ff00')
  assert(#colors == 1)
  assert(colors[1]:find('rendered', 1, true))
end)

check('artifact drift is evidence without a color failure', function()
  local left = sample 'fg=#ffb86c'
  local right = sample 'fg=#ffb86c'
  right.artifacts.parsers[1].sha256 = 'different'
  local colors, evidence = snapshot.compare(left, right)
  assert(#colors == 0)
  assert(#evidence == 1)
  assert(evidence[1]:find('sha256', 1, true))
end)

if #failures > 0 then error(string.format('%d web color snapshot check(s) failed: %s', #failures, table.concat(failures, ', '))) end

io.stdout:write 'All web color snapshot checks passed.\n'
