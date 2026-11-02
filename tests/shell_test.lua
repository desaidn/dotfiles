-- Exercise shell startup with real interpreters and isolated HOME directories.
-- Run with: nvim --clean --headless -l tests/shell_test.lua

local uv = vim.uv
local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local repo = vim.fs.dirname(vim.fs.dirname(script))
local fish = vim.fn.exepath 'fish'
-- Homebrew Zsh includes its site-functions in the default fpath; the system
-- interpreter exposes missing completion setup when inheriting Fish's PATH.
local zsh = uv.fs_stat '/bin/zsh' and '/bin/zsh' or vim.fn.exepath 'zsh'
local brew = vim.fn.exepath 'brew'
assert(fish ~= '' and zsh ~= '' and brew ~= '', 'shell tests require Fish, Zsh, and Homebrew')

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

local function run(command, env, input)
  local result = vim.system(command, { env = env, clear_env = env ~= nil, stdin = input or '', text = true, timeout = 20000 }):wait()
  assert(result.code == 0, vim.inspect(command) .. ' exited ' .. result.code .. '\n' .. result.stdout .. '\n' .. result.stderr)
  return result.stdout
end

local brew_repository = vim.trim(run { brew, '--repository' })
local shellenv = brew_repository .. '/Library/Homebrew/cmd/shellenv.sh'
assert(uv.fs_stat(shellenv), "cannot find Homebrew's shellenv implementation")

local function mkdir(path) assert(vim.fn.mkdir(path, 'p') == 1 or uv.fs_stat(path), 'could not create ' .. path) end

local function write(path, contents, append)
  mkdir(vim.fs.dirname(path))
  local file = assert(io.open(path, append and 'a' or 'w'))
  assert(file:write(contents))
  assert(file:close())
end

local function executable(path, contents)
  write(path, contents)
  assert(uv.fs_chmod(path, 493)) -- 0755
end

local function symlink(target, path) assert(uv.fs_symlink(target, path)) end

local function lines(value)
  if value == '' then return {} end
  return vim.split(value:gsub('\n$', ''), '\n', { plain = true })
end

local function equal(actual, expected) assert(vim.deep_equal(actual, expected), 'expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual)) end

local function contains(value, expected) return value:find(expected, 1, true) ~= nil end

local function fixture(root, name)
  local directory = root .. '/' .. name
  local home = directory .. '/home'
  for _, item in ipairs { '.config/fish', '.local/bin', '.local/share/dotfiles', '.cache/fish/generated_completions', 'tmp' } do
    mkdir(home .. '/' .. item)
  end
  assert(uv.fs_copyfile(repo .. '/fish/config.fish', home .. '/.config/fish/config.fish'))
  assert(uv.fs_copyfile(repo .. '/zsh/.zshrc', home .. '/.zshrc'))
  for _, shell in ipairs { 'fish', 'zsh' } do
    assert(uv.fs_copyfile(repo .. '/templates/local.' .. shell, home .. '/.local/share/dotfiles/local.' .. shell))
  end
  local prefix = directory .. '/brew'
  mkdir(prefix .. '/sbin')
  executable(prefix .. '/bin/brew', '#!/bin/bash\nsource ' .. quote(shellenv) .. '\nexport HOMEBREW_PREFIX=' .. quote(prefix) .. [[

export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX"
export HOMEBREW_PATH="$PATH"
case "$1" in
    shellenv) homebrew-shellenv "$2" ;;
    --prefix) printf '%s\n' "$HOMEBREW_PREFIX" ;;
    *) exit 1 ;;
esac
]])
  for _, command in ipairs { 'mise', 'atuin' } do
    executable(prefix .. '/bin/' .. command, '#!/bin/sh\nprintf "' .. command .. ' %s\\n" "$*" >> "$STARTUP_LOG"\n')
  end
  local env = {
    HOME = home,
    PATH = prefix .. '/bin:/usr/bin:/bin',
    TERM = 'dumb',
    TMPDIR = home .. '/tmp',
    XDG_CONFIG_HOME = home .. '/.config',
    XDG_DATA_HOME = home .. '/.local/share',
    XDG_CACHE_HOME = home .. '/.cache',
    XDG_STATE_HOME = home .. '/.local/state',
    MISE_FISH_AUTO_ACTIVATE = '0',
    STARTUP_LOG = directory .. '/startup.log',
  }
  return directory, home, prefix, env
end

local function startup_calls(env)
  if not uv.fs_stat(env.STARTUP_LOG) then return {} end
  return vim.fn.readfile(env.STARTUP_LOG)
end

local function shell_command(shell, binary, command) return { binary, shell == 'fish' and '--no-config' or '-df', '-c', command } end

local function rc_path(home, shell) return home .. (shell == 'fish' and '/.config/fish/config.fish' or '/.zshrc') end

local shells = { { 'fish', fish }, { 'zsh', zsh } }
local root = assert(uv.fs_mkdtemp(vim.fs.joinpath(uv.os_tmpdir(), 'dotfiles-shell-test-XXXXXX')))
root = assert(uv.fs_realpath(root))
local ok, err = xpcall(function()
  for _, runtime in ipairs { 'mise', 'venv' } do
    for _, entry in ipairs(shells) do
      local shell, binary = unpack(entry)
      local directory, home, prefix, env = fixture(root, runtime .. '-' .. shell)
      local runtime_bin = directory .. '/' .. runtime .. '/bin'
      for _, command in ipairs { 'python3', 'bun' } do
        executable(runtime_bin .. '/' .. command, '#!/bin/sh\necho ' .. runtime .. '\n')
        executable(prefix .. '/bin/' .. command, '#!/bin/sh\necho brew\n')
        executable(home .. '/.bun/bin/' .. command, '#!/bin/sh\necho optional\n')
      end
      env.PATH = runtime_bin .. ':' .. home .. '/.local/bin:' .. prefix .. '/bin:/usr/bin:/bin'
      if runtime == 'venv' then env.VIRTUAL_ENV = vim.fs.dirname(runtime_bin) end
      local command = 'source ' .. quote(rc_path(home, shell)) .. '; python3; bun'
      equal(lines(run(shell_command(shell, binary, command), env)), { runtime, runtime })
      assert(#startup_calls(env) == 0, 'noninteractive shell activated interactive tools')
      if shell == 'fish' then
        equal(lines(run({ binary, '--no-config', '-i', '-c', command }, env)), { runtime, runtime })
        equal(startup_calls(env), { 'mise activate fish', 'mise completion fish', 'atuin init fish' })
      end
    end
  end
  print 'PASS Fish and Zsh preserve inherited Mise and virtualenv command resolution'

  for _, entry in ipairs(shells) do
    local shell, binary = unpack(entry)
    local directory, home, prefix, env = fixture(root, 'discovery-' .. shell)
    local lookup = directory .. '/lookup'
    mkdir(lookup)
    symlink(prefix .. '/bin/brew', lookup .. '/brew')
    symlink(vim.fn.exepath 'cat', prefix .. '/bin/cat')
    env.PATH = lookup .. ':/usr/bin:/bin'
    local command = 'source ' .. quote(rc_path(home, shell)) .. '; command -v mise; command -v cat'
    equal(lines(run(shell_command(shell, binary, command), env)), { prefix .. '/bin/mise', prefix .. '/bin/cat' })
  end
  print 'PASS Homebrew discovery adds missing executable paths ahead of system commands'

  -- Python is the subject of this integration check, not the test runner.
  local python = vim.fn.exepath 'python3'
  if python ~= '' then
    -- Resolve runtime-manager shims before the fixture HOME hides their config.
    python = vim.trim(run { python, '-c', 'import sys; print(sys.executable)' })
    for _, entry in ipairs(shells) do
      local shell, binary = unpack(entry)
      local directory, home, prefix, env = fixture(root, 'venv-brew-discovery-' .. shell)
      local environment = directory .. '/.venv'
      run({ python, '-m', 'venv', '--without-pip', environment }, env)
      -- A Brew command discoverable outside its prefix models startup before
      -- shellenv has added bin/sbin. Both competing Pythons are real runtimes.
      local lookup = directory .. '/lookup'
      mkdir(lookup)
      symlink(prefix .. '/bin/brew', lookup .. '/brew')
      symlink(python, prefix .. '/bin/python3')
      env.PATH = lookup .. ':/usr/bin:/bin'
      local activation = environment .. '/bin/' .. (shell == 'fish' and 'activate.fish' or 'activate')
      local command = 'source '
        .. quote(activation)
        .. "; python3 -c 'import sys; print(sys.prefix)'; source "
        .. quote(rc_path(home, shell))
        .. "; python3 -c 'import sys; print(sys.prefix)'"
      equal(lines(run(shell_command(shell, binary, command), env)), { environment, environment })
    end
    print 'PASS Homebrew discovery preserves a genuinely activated virtualenv'
  else
    print 'SKIP activated Python virtualenv check (python3 is unavailable)'
  end

  local directory, home, prefix, env = fixture(root, 'zsh-branch-prompt')
  for index, branch in ipairs { 'fix/plain', 'fix/%F{red}', 'fix/%{', 'fix/1234567890123456789012345%F{red}' } do
    local checkout = directory .. '/project-' .. index
    run({ 'git', 'init', '-q', '--initial-branch=' .. branch, checkout }, env)
    local command = 'source "$HOME/.zshrc"; cd ' .. quote(checkout) .. '; print -P -- "$PROMPT"'
    local output = run({ zsh, '-df', '-c', command }, env)
    local displayed_branch = branch:sub(1, 30) .. (#branch > 30 and '...' or '')
    assert(contains(output, '[branch: ' .. displayed_branch .. ']'), vim.inspect(output))
  end
  print 'PASS Zsh renders valid Git branch names literally after truncation'

  directory, home, prefix, env = fixture(root, 'zsh-overrides')
  write(
    home .. '/.local/share/dotfiles/local.zsh',
    [[PROMPT='MACHINE_PROMPT> '
alias nvim-reset='echo machine-reset'
git_prompt() { print MACHINE_BRANCH; }
MACHINE_EDITORS="$EDITOR:$VISUAL:$GIT_EDITOR"
(( MACHINE_LOCAL_LOADS += 1 ))
]]
  )
  local output = run({ zsh, '-d', '-i', '-c', 'print -r -- "$PROMPT"; alias nvim-reset; git_prompt; print -r -- "$MACHINE_EDITORS:$MACHINE_LOCAL_LOADS"' }, env)
  equal(lines(output), { 'MACHINE_PROMPT> ', "nvim-reset='echo machine-reset'", 'MACHINE_BRANCH', 'nvim:nvim:nvim:1' })
  print 'PASS Zsh preserves machine prompt, alias, and function overrides after one local source'

  for _, inherited_exports in ipairs { false, true } do
    directory, home, prefix, env = fixture(root, 'zsh-completions-' .. tostring(inherited_exports))
    local completions = prefix .. '/share/zsh/site-functions'
    write(completions .. '/_dotfiles_brew_probe', '#compdef dotfiles-brew-probe\n')
    env.PATH = prefix .. '/bin:' .. prefix .. '/sbin:' .. home .. '/.local/bin:/usr/bin:/bin'
    if inherited_exports then
      env.HOMEBREW_PREFIX = prefix
      env.HOMEBREW_CELLAR = prefix .. '/Cellar'
      env.HOMEBREW_REPOSITORY = prefix
    end
    assert(run({ prefix .. '/bin/brew', 'shellenv', 'zsh' }, env) == '', "fixture must exercise Homebrew's Brew-first PATH no-op")
    local completion_output = lines(run({ zsh, '-d', '-i', '-c', 'print -rl -- "${_comps[dotfiles-brew-probe]}" "$PATH"; print -rl -- $fpath' }, env))
    equal({ completion_output[1], completion_output[2] }, { '_dotfiles_brew_probe', env.PATH })
    local occurrences = 0
    for index = 3, #completion_output do
      if completion_output[index] == completions then occurrences = occurrences + 1 end
    end
    assert(occurrences == 1, vim.inspect(completion_output))
  end
  print 'PASS Zsh registers Homebrew completions with Brew-first PATH, with and without exports'

  directory, home, prefix, env = fixture(root, 'handoff')
  write(home .. '/.local/share/dotfiles/local.zsh', '\nexport MACHINE_SETTING="preserved"\n', true)
  executable(prefix .. '/bin/fish', '#!/bin/sh\nprintf "HANDOFF=%s EDITOR=%s\\n" "$MACHINE_SETTING" "$EDITOR"\n')
  assert(contains(run({ zsh, '-d', '-i' }, env), 'HANDOFF=preserved EDITOR=nvim'))
  assert(#startup_calls(env) == 0, 'Zsh initialized tools before handing off to Fish')
  assert(not uv.fs_stat(home .. '/.zcompdump'), 'Zsh initialized discarded completion state')
  print 'PASS Zsh handoff preserves machine exports and skips discarded activation'

  output = run({ zsh, '-d', '-i', '-c', 'printf "ZSH_COMMAND=%s\\n" "$ZSH_VERSION"' }, env)
  assert(contains(output, 'ZSH_COMMAND=') and not contains(output, 'HANDOFF='))
  equal(startup_calls(env), { 'mise activate zsh', 'mise completion zsh', 'atuin init zsh' })
  assert(uv.fs_stat(home .. '/.zcompdump'), 'explicit interactive Zsh lost completion setup')
  assert(not contains(run({ zsh, '-d', '-i', '-c', '' }, env), 'HANDOFF='))
  print 'PASS explicit interactive Zsh commands retain completion and tool activation'

  directory, home, prefix, env = fixture(root, 'fallback')
  -- Exclude system Fish installations while retaining utilities used by compinit.
  for _, command in ipairs { 'cat', 'chmod', 'cut', 'dirname', 'mkdir', 'mv', 'rm', 'sed', 'uname' } do
    local target = vim.fn.exepath(command)
    if target ~= '' then symlink(target, prefix .. '/bin/' .. command) end
  end
  env.PATH = prefix .. '/bin'
  output = run({ zsh, '-d', '-i' }, env, 'printf "ZSH_FALLBACK=%s\\n" "$ZSH_VERSION"\nexit\n')
  assert(contains(output, 'ZSH_FALLBACK='))
  equal(startup_calls(env), { 'mise activate zsh', 'mise completion zsh', 'atuin init zsh' })
  print 'PASS Fish-unavailable Zsh fallback retains interactive activation'

  local resources = vim.env.GHOSTTY_RESOURCES_DIR
  local integration = (resources or '/nonexistent') .. '/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish'
  if uv.fs_stat(integration) then
    directory, home, prefix, env = fixture(root, 'ghostty')
    env.GHOSTTY_RESOURCES_DIR = resources
    env.GHOSTTY_SHELL_FEATURES = 'title,ssh-env,ssh-terminfo'
    env.TERM = 'xterm-ghostty'
    local probe = 'emit fish_prompt; functions -q ssh; or exit 1; '
      .. 'source "$HOME/.config/fish/config.fish"; '
      .. 'functions -q __ghostty_setup; and exit 1; printf "GHOSTTY_OK\\n"'
    executable(prefix .. '/bin/fish', '#!/bin/sh\nexec ' .. quote(fish) .. ' -i -c ' .. quote(probe) .. '\n')
    local direct = vim.tbl_extend('force', env, {
      XDG_DATA_DIRS = resources .. '/shell-integration',
      GHOSTTY_SHELL_INTEGRATION_XDG_DIR = resources .. '/shell-integration',
    })
    assert(contains(run({ prefix .. '/bin/fish' }, direct), 'GHOSTTY_OK'))
    local handoff = vim.tbl_extend('force', env, {
      ZDOTDIR = resources .. '/shell-integration/zsh',
      GHOSTTY_ZSH_ZDOTDIR = home,
    })
    assert(contains(run({ zsh, '-d', '-i' }, handoff), 'GHOSTTY_OK'))
    print 'PASS real Ghostty Fish integration survives direct injection, Zsh handoff, and rc reload'
  else
    print 'SKIP real Ghostty integration (GHOSTTY_RESOURCES_DIR is unavailable)'
  end
end, debug.traceback)
local cleaned = vim.fn.delete(root, 'rf')
assert(ok, err)
assert(cleaned == 0, 'could not remove temporary fixtures: ' .. root)
print 'shell regression checks passed'
