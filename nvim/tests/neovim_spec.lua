local failures = {}
local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script) .. '/..')

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end
  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local function load_module(path, environment) return setfenv(assert(loadfile(nvim_root .. '/' .. path)), setmetatable(environment, { __index = _G }))() end

local function version_api(text)
  local version = assert(vim.version.parse(text))
  return setmetatable({ ge = vim.version.ge }, { __call = function() return version end })
end

local function compatibility(api) return load_module('lua/custom/lib/neovim.lua', { vim = { version = api } }) end

check('uses the stable minimum while accepting newer stable and prerelease versions', function()
  for _, case in ipairs {
    { '0.11.6', false },
    { '0.12.4', false },
    { '0.12.5-dev', false },
    { '0.12.5', true },
    { '0.12.6', true },
    { '0.13.0', true },
    { '1.0.0', true },
    { '0.13.0-dev', true },
  } do
    local supported, message = compatibility(version_api(case[1])).check()
    assert(supported == case[2], 'wrong compatibility result for ' .. case[1])
    assert(message == ('Neovim %s (minimum: 0.12.5)'):format(case[1]), message)
  end
end)

check('reports unavailable version APIs as unsupported without throwing', function()
  local supported, message = compatibility(nil).check()
  assert(supported == false)
  assert(message == 'Neovim unknown (minimum: 0.12.5)')

  local function old_version_api() return assert(vim.version.parse '0.9.5') end
  supported, message = compatibility(old_version_api).check()
  assert(supported == false)
  assert(message == 'Neovim 0.9.5 (minimum: 0.12.5)')

  local api_without_comparison = setmetatable({}, { __call = old_version_api })
  supported, message = compatibility(api_without_comparison).check()
  assert(supported == false)
  assert(message == 'Neovim 0.9.5 (minimum: 0.12.5)')
end)

local function consumer_environment(text)
  local calls = { errors = {}, warnings = {}, successes = {}, info = {}, echo = {}, loader = false }
  local api = version_api(text)
  local module = compatibility(api)
  local environment = {
    require = function(name)
      assert(name == 'custom.lib.neovim', 'startup loaded a feature before checking compatibility')
      return module
    end,
    vim = {
      version = api,
      inspect = vim.inspect,
      uv = { os_uname = vim.uv.os_uname },
      health = {
        start = function(_) end,
        error = function(message) table.insert(calls.errors, message) end,
        warn = function(message) table.insert(calls.warnings, message) end,
        ok = function(message) table.insert(calls.successes, message) end,
        info = function(message) table.insert(calls.info, message) end,
      },
      fn = {
        executable = function(_) return 1 end,
        getchar = function() error 'startup must not wait for input' end,
      },
      api = { nvim_echo = function(chunks, _, _) calls.echo = chunks end },
      loader = {
        enable = function()
          calls.loader = true
          error 'startup accepted'
        end,
      },
    },
    os = {
      exit = function(code)
        assert(code == 1)
        error 'startup rejected'
      end,
    },
  }
  return environment, calls
end

check('startup rejects old versions without waiting and proceeds on newer versions', function()
  for _, text in ipairs { '0.12.4', '0.12.5', '0.13.0-dev' } do
    local environment, calls = consumer_environment(text)
    local ok, err = pcall(load_module, 'init.lua', environment)
    assert(not ok)
    if text == '0.12.4' then
      assert(tostring(err):find('startup rejected', 1, true), err)
      assert(not calls.loader)
      assert(calls.echo[1][1] == 'Neovim 0.12.4 (minimum: 0.12.5). Install the latest stable release.')
    else
      assert(tostring(err):find('startup accepted', 1, true), err)
      assert(calls.loader)
      assert(#calls.echo == 0)
    end
  end
end)

check('health uses the same minimum and advises on accepted prerelease builds', function()
  for _, text in ipairs { '0.12.4', '0.12.5', '0.13.0-dev' } do
    local environment, calls = consumer_environment(text)
    load_module('lua/kickstart/health.lua', environment).check()
    if text == '0.12.4' then
      assert(vim.deep_equal(calls.errors, { 'Neovim 0.12.4 (minimum: 0.12.5). Install the latest stable release.' }))
    else
      assert(#calls.errors == 0)
      assert(calls.successes[1] == ('Neovim %s (minimum: 0.12.5)'):format(text))
      assert(vim.list_contains(calls.info, 'The latest stable Neovim release is recommended.'))
    end
    if text == '0.13.0-dev' then
      assert(vim.deep_equal(calls.warnings, { 'Prerelease build; stable-release validation does not cover it.' }))
    else
      assert(#calls.warnings == 0)
    end
  end
end)

if #failures > 0 then error(string.format('%d Neovim compatibility check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Neovim compatibility checks passed.\n'
