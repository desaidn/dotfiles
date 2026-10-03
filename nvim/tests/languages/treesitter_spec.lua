local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')

package.path = table.concat({ nvim_root .. '/lua/?.lua', nvim_root .. '/lua/?/init.lua', package.path }, ';')

local original_pack_add = vim.pack.add
local original_start = vim.treesitter.start
local original_treesitter = package.loaded['nvim-treesitter']
local original_context = package.loaded['treesitter-context']
local original_config = package.loaded['custom.languages.config']
local buffers = {}
local completions = {}
local starts = {}
local installed = false
local indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

local function check(name, body)
  completions = {}
  starts = {}
  installed = false
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end
  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function create_buffer(filetype)
  local buf = vim.api.nvim_create_buf(true, false)
  buffers[#buffers + 1] = buf
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local value = 1' })
  if filetype then vim.bo[buf].filetype = filetype end
  vim.bo[buf].indentexpr = '0'
  return buf
end

local function complete_install()
  assert(#completions == 1, 'expected one pending Lua parser installation')
  assert(#starts == 0, 'attached a parser before installation completed')
  installed = true
  completions[1]()
end

local function ignore_package_additions(_, _) end
local function capture_start(buf, language)
  starts[#starts + 1] = { buf = buf, language = language }
  original_start(buf, language)
end
vim.pack.add = ignore_package_additions
vim.treesitter.start = capture_start
package.loaded['custom.languages.config'] = { treesitter_parsers = { 'lua' } }
package.loaded['treesitter-context'] = { setup = function() end }
package.loaded['nvim-treesitter'] = {
  setup = function() end,
  get_available = function() return { 'lua' } end,
  get_installed = function() return installed and { 'lua' } or {} end,
  install = function(language)
    assert(language == 'lua', 'unexpected parser installation')
    return {
      await = function(_, callback) completions[#completions + 1] = callback end,
    }
  end,
}

local setup_ok, setup_error = xpcall(function()
  -- Neovim's Lua ftplugin starts Treesitter independently of the callback under test.
  vim.cmd 'filetype plugin indent off'
  assert(vim.treesitter.language.add 'lua', 'Neovim must provide its bundled Lua parser')
  -- Exercise real parser attachment and query lookup without installing a plugin or parser.
  vim.treesitter.query.set('lua', 'indents', '(chunk) @indent.begin')
  dofile(nvim_root .. '/lua/custom/languages/treesitter.lua')

  check('ignores an installation completion after its buffer is wiped', function()
    local buf = create_buffer 'lua'
    vim.api.nvim_buf_delete(buf, { force = true })
    assert(not vim.api.nvim_buf_is_valid(buf), 'fixture buffer was not wiped')
    complete_install()
    assert(#starts == 0, 'attempted to attach a parser to a wiped buffer')
  end)

  check('ignores an installation completion after its buffer is unloaded', function()
    local buf = create_buffer 'lua'
    create_buffer()
    vim.api.nvim_buf_delete(buf, { force = true, unload = true })
    assert(vim.api.nvim_buf_is_valid(buf), 'fixture buffer was wiped instead of unloaded')
    assert(not vim.api.nvim_buf_is_loaded(buf), 'fixture buffer was not unloaded')
    complete_install()
    assert(#starts == 0, 'attempted to attach a parser to an unloaded buffer')
    assert(not vim.api.nvim_buf_is_loaded(buf), 'installation completion reloaded its buffer')
  end)

  check('ignores an installation completion after its buffer changes language', function()
    local buf = create_buffer 'lua'
    vim.bo[buf].filetype = 'text'
    complete_install()
    assert(#starts == 0, 'attached the old Lua parser after the filetype changed')
    assert(vim.bo[buf].indentexpr == '0', 'changed indentation for the new filetype')
  end)

  check('attaches and sets indentation only on the original buffer after switching buffers', function()
    local buf = create_buffer 'lua'
    local other = create_buffer()
    complete_install()
    assert(#starts == 1 and starts[1].buf == buf and starts[1].language == 'lua', 'did not attach Lua to the original buffer')
    assert(vim.treesitter.highlighter.active[buf] ~= nil, 'original buffer has no active highlighter')
    assert(vim.bo[buf].indentexpr == indentexpr, 'did not enable indentation in the original buffer')
    assert(vim.bo[other].indentexpr == '0', 'changed indentation in the current unrelated buffer')
    assert(vim.api.nvim_get_current_buf() == other, 'attachment changed the current buffer')
  end)

  check('attaches immediately when the parser is already installed', function()
    installed = true
    local buf = create_buffer()
    vim.bo[buf].filetype = 'lua'
    assert(#completions == 0, 'reinstalled an already installed parser')
    assert(#starts == 1 and starts[1].buf == buf and starts[1].language == 'lua', 'did not attach the installed Lua parser')
    assert(vim.treesitter.highlighter.active[buf] ~= nil, 'buffer has no active highlighter')
    assert(vim.bo[buf].indentexpr == indentexpr, 'did not enable indentation for the installed parser')
  end)
end, debug.traceback)

pcall(vim.api.nvim_clear_autocmds, { group = 'treesitter-start' })
pcall(vim.api.nvim_clear_autocmds, { group = 'language-treesitter-sync' })
for _, buf in ipairs(buffers) do
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end
vim.pack.add = original_pack_add
vim.treesitter.start = original_start
package.loaded['nvim-treesitter'] = original_treesitter
package.loaded['treesitter-context'] = original_context
package.loaded['custom.languages.config'] = original_config

if not setup_ok then
  failures[#failures + 1] = 'initializes the Treesitter test fixture'
  io.stderr:write('FAIL initializes the Treesitter test fixture\n  ', tostring(setup_error):gsub('\n', '\n  '), '\n')
end

if #failures > 0 then error(string.format('%d Treesitter check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Treesitter checks passed.\n'
