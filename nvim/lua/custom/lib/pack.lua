local M = {}

function M.gh(repo) return 'https://github.com/' .. repo end

local function run_build(name, cmd, cwd)
  local result = vim.system(cmd, { cwd = cwd }):wait()
  if result.code == 0 then return end

  local stderr = result.stderr or ''
  local stdout = result.stdout or ''
  local output = stderr ~= '' and stderr or stdout
  if output == '' then output = 'No output from build command.' end
  vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
end

local function packadd_if_needed(name, active)
  if active then return true end
  local ok, err = pcall(vim.cmd.packadd, name)
  if not ok then
    vim.notify(('Unable to load %s after package change:\n%s'):format(name, err), vim.log.levels.ERROR)
    return false
  end
  return true
end

local function sync_treesitter_artifacts(kind)
  local ok, treesitter = pcall(require, 'nvim-treesitter')
  if not ok then return end

  -- install() skips existing parsers; update() advances installed parser/query pairs together.
  local operation = kind == 'update' and treesitter.update or treesitter.install
  local task = operation(require 'kickstart.parsers')
  if task and task.wait then task:wait(60000) end
end

local function install_fff_binary()
  local ok, download = pcall(require, 'fff.download')
  if ok then download.download_or_build_binary() end
end

function M.setup()
  vim.api.nvim_create_autocmd('PackChanged', {
    group = vim.api.nvim_create_augroup('custom-pack-build', { clear = true }),
    callback = function(ev)
      local name = ev.data.spec.name
      local kind = ev.data.kind
      if kind ~= 'install' and kind ~= 'update' then return end

      if name == 'telescope-fzf-native.nvim' and vim.fn.executable 'make' == 1 then
        run_build(name, { 'make' }, ev.data.path)
        return
      end

      if name == 'LuaSnip' then
        if vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then run_build(name, { 'make', 'install_jsregexp' }, ev.data.path) end
        return
      end

      if name == 'nvim-treesitter' then
        if packadd_if_needed(name, ev.data.active) then sync_treesitter_artifacts(kind) end
        return
      end

      if name == 'fff.nvim' then
        if packadd_if_needed(name, ev.data.active) then install_fff_binary() end
        return
      end
    end,
  })
end

return M
