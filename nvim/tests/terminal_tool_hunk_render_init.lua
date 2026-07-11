vim.o.mouse = 'a'

local fixture = assert(vim.env.HUNK_RENDER_FIXTURE, 'HUNK_RENDER_FIXTURE is required')
local repo_root = assert(vim.env.DOTFILES_REPO_ROOT, 'DOTFILES_REPO_ROOT is required')
vim.cmd.cd(vim.fn.fnameescape(fixture))

vim.defer_fn(function()
  local terminal_tool = dofile(repo_root .. '/nvim/lua/custom/lib/terminal_tool.lua')
  _G.hunk_render_probe = terminal_tool.create {
    name = 'HunkRenderProbe',
    source = 'hunk',
    command = { 'hunk', 'diff', '--watch', '--mode', 'stack' },
    env = { OPENTUI_GRAPHICS = 'false' },
    key = '<leader>gd',
    desc = 'Hunk render probe',
    hide_command = 'HunkRenderProbeHide',
  }
  _G.hunk_render_probe.toggle()
end, 100)
