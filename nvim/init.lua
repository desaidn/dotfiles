--[[

Kickstart Guide:

  If you don't know anything about Lua, I recommend taking some time to read through
  a guide. One possible example which will only take 10-15 minutes:
    - https://learnxinyminutes.com/docs/lua/

  After understanding a bit more about Lua, you can use `:help lua-guide` as a
  reference for how Neovim integrates Lua.
  - :help lua-guide
  - (or HTML version): https://neovim.io/doc/user/lua-guide.html

  The very first thing you should do is to run the command `:Tutor` in Neovim.

  Next, run AND READ `:help`.
  This will open up a help window with some basic information
  about reading, navigating and searching the builtin help documentation.

  MOST IMPORTANTLY, we provide a keymap "<space>sh" to [s]earch the [h]elp documentation,
  which is very useful when you're not exactly sure of what you're looking for.

  If you experience any errors while trying to install kickstart, run `:checkhealth` for more info.

--]]

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Disable netrw to prevent flicker when opening directories (using neo-tree)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- [[ Setting options ]]
-- See `:help vim.o`
--  For more options, you can see `:help option-list`

-- Make line numbers default
vim.o.number = true
-- You can also add relative line numbers, to help with jumping.
--  Experiment for yourself to see if you like it!
vim.o.relativenumber = true

-- Line number management (relative number toggling + special buffer suppression)
local line_numbers_group = vim.api.nvim_create_augroup('line-numbers', { clear = true })

vim.api.nvim_create_autocmd('InsertEnter', {
  desc = 'Disable relative numbers in insert mode',
  group = line_numbers_group,
  callback = function()
    if vim.bo.buftype == '' and vim.bo.filetype ~= 'neo-tree' then vim.wo.relativenumber = false end
  end,
})

vim.api.nvim_create_autocmd('InsertLeave', {
  desc = 'Re-enable relative numbers in normal mode',
  group = line_numbers_group,
  callback = function()
    if vim.bo.buftype == '' and vim.bo.filetype ~= 'neo-tree' then vim.wo.relativenumber = true end
  end,
})

vim.api.nvim_create_autocmd({ 'TermOpen', 'BufEnter', 'WinEnter', 'FileType' }, {
  desc = 'Disable line numbers for special buffers',
  group = line_numbers_group,
  callback = function()
    local buftype = vim.bo.buftype
    local filetype = vim.bo.filetype

    if buftype == 'terminal' or filetype == 'neo-tree' or filetype == 'help' or filetype == 'qf' or buftype == 'nofile' or buftype == 'prompt' then
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      if buftype == 'terminal' then vim.opt_local.signcolumn = 'no' end
    end
  end,
})

-- Don't show the mode, since it's already in the status line
vim.o.showmode = false

-- Use global statusline that spans the full width (not per-window)
vim.o.laststatus = 3

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function() vim.o.clipboard = 'unnamedplus' end)

-- Indentation: 2 spaces
vim.o.expandtab = true
vim.o.shiftwidth = 2
vim.o.tabstop = 2
vim.o.softtabstop = 2

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300

-- Configure how new splits should be opened
vim.o.splitright = true
vim.o.splitbelow = true

-- Display whitespace characters in the editor.
--  See `:help 'list'` and `:help 'listchars'`
--
--  Uses `vim.opt` (not `vim.o`) for table-like option handling.
--  See `:help lua-options`
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.o.inccommand = 'split'

-- Show which line your cursor is on
vim.o.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.o.scrolloff = 10

-- Load custom colorscheme (see colors/custom.lua)
vim.cmd.colorscheme 'custom'

vim.o.winborder = 'rounded'
vim.o.pumborder = 'rounded'

-- if performing an operation that would fail due to unsaved changes in the buffer (like `:q`),
-- instead raise a dialog asking if you wish to save the current file(s)
-- See `:help 'confirm'`
vim.o.confirm = true

-- Always show tabline
vim.o.showtabline = 2

function _G.custom_tabline()
  local tabs = {}
  local lg_open = vim.g.lazygit_open
  local current_tabpage = vim.api.nvim_get_current_tabpage()
  for i, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local buf
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if vim.api.nvim_win_get_config(win).relative == '' then
        buf = vim.api.nvim_win_get_buf(win)
        break
      end
    end
    if buf then
      local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
      if name == '' then name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t') end
      if vim.bo[buf].modified then name = name .. ' +' end
      local hl = (tabpage == current_tabpage and not lg_open) and '%#TabLineSel#' or '%#TabLine#'
      table.insert(tabs, hl .. '%' .. i .. 'T' .. '   ' .. name .. '   ')
    end
  end
  if lg_open then table.insert(tabs, '%#TabLineSel#' .. '   lazygit   ') end
  return table.concat(tabs) .. '%#TabLineFill#%T'
end

vim.o.tabline = '%!v:lua.custom_tabline()'

-- [[ Diagnostic Config ]]
-- See `:help vim.diagnostic.Opts`
vim.diagnostic.config {
  update_in_insert = false,
  severity_sort = true,
  float = { source = 'if_many' },
  underline = { severity = vim.diagnostic.severity.ERROR },
  signs = {},
  virtual_text = { source = 'if_many', spacing = 2 },
  -- Auto open the float when jumping with `[d` and `]d`
  jump = { float = true },
}

-- [[ Basic Keymaps ]]
-- See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Half-page navigation with centered cursor
vim.keymap.set('n', '<C-d>', '<C-d>zz', { desc = 'Half-page down and center cursor' })
vim.keymap.set('n', '<C-u>', '<C-u>zz', { desc = 'Half-page up and center cursor' })

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Toggle spell checking
vim.keymap.set('n', '<leader>ts', function() vim.opt_local.spell = not vim.wo.spell end, { desc = '[T]oggle [S]pell check' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Copy file paths to clipboard
vim.keymap.set('n', '<leader>pa', function()
  local path = vim.fn.expand '%:p'
  vim.fn.setreg('+', path)
  print('Copied absolute path: ' .. path)
end, { desc = 'Copy [P]ath [A]bsolute' })

vim.keymap.set('n', '<leader>pr', function()
  local path = vim.fn.expand '%:.'
  vim.fn.setreg('+', path)
  print('Copied relative path: ' .. path)
end, { desc = 'Copy [P]ath [R]elative' })

-- NOTE: Some terminals have colliding keymaps or are not able to send distinct keycodes
-- vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
-- vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
-- vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
-- vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })

-- [[ Basic Autocommands ]]
-- See `:help lua-guide-autocommands`

-- Auto-reload files when changed externally
local auto_reload_group = vim.api.nvim_create_augroup('auto-reload', { clear = true })

vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  desc = 'Check if file changed on disk and reload',
  group = auto_reload_group,
  callback = function()
    if vim.fn.getcmdwintype() == '' then vim.cmd.checktime() end
  end,
})

vim.api.nvim_create_autocmd('FileChangedShellPost', {
  desc = 'Notify when file is reloaded',
  group = auto_reload_group,
  callback = function() vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.WARN) end,
})

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function() vim.hl.on_yank() end,
})

-- [[ Install `lazy.nvim` plugin manager ]]
-- See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { out, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end

vim.opt.rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]
--
--  To check the current status of your plugins, run
--    :Lazy
--
--  You can press `?` in this menu for help. Use `:q` to close the window
--
--  To update plugins you can run
--    :Lazy update
--
-- NOTE: Here is where you install your plugins.
require('lazy').setup({
  -- Plugins can be added via a link or github org/name. Use `opts = {}` to call setup automatically,
  --  or `config = function() ... end` for full control. Plugins support lazy loading via `event`,
  --  `cmd`, `keys`, etc. See `:help lazy.nvim-🔌-plugin-spec`
  { 'NMAC427/guess-indent.nvim', opts = {} },

  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter',
    opts = {
      preset = 'classic', -- Use classic preset for familiar behavior
      -- delay between pressing a key and opening which-key (milliseconds)
      delay = 0,
      win = { border = 'rounded' },
      icons = {
        mappings = false,
        keys = {
          Up = '<Up> ',
          Down = '<Down> ',
          Left = '<Left> ',
          Right = '<Right> ',
          C = '<C-…> ',
          M = '<M-…> ',
          D = '<D-…> ',
          S = '<S-…> ',
          CR = '<CR> ',
          Esc = '<Esc> ',
          ScrollWheelDown = '<ScrollWheelDown> ',
          ScrollWheelUp = '<ScrollWheelUp> ',
          NL = '<NL> ',
          BS = '<BS> ',
          Space = '<Space> ',
          Tab = '<Tab> ',
          F1 = '<F1>',
          F2 = '<F2>',
          F3 = '<F3>',
          F4 = '<F4>',
          F5 = '<F5>',
          F6 = '<F6>',
          F7 = '<F7>',
          F8 = '<F8>',
          F9 = '<F9>',
          F10 = '<F10>',
          F11 = '<F11>',
          F12 = '<F12>',
        },
      },

      -- Document existing key chains
      spec = {
        { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
        { '<leader>g', group = '[G]it', mode = { 'n', 'v' } },
        { '<leader>p', group = '[P]ath', mode = { 'n', 'v' } },
        { '<leader>1', hidden = true },
        { '<leader>2', hidden = true },
        { '<leader>3', hidden = true },
        { '<leader>4', hidden = true },
        { '<leader>5', hidden = true },
        { '<leader>6', hidden = true },
        { '<leader>7', hidden = true },
        { '<leader>8', hidden = true },
        { '<leader>9', hidden = true },
        { '<leader>0', hidden = true },
      },
    },
  },

  { -- Collection of various small independent plugins/modules
    'nvim-mini/mini.nvim',
    config = function()
      -- Better Around/Inside textobjects
      --
      -- Examples:
      --  - va)  - [V]isually select [A]round [)]paren
      --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
      --  - ci'  - [C]hange [I]nside [']quote
      require('mini.ai').setup { n_lines = 500 }

      -- Add/delete/replace surroundings (brackets, quotes, etc.)
      --
      -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
      -- - sd'   - [S]urround [D]elete [']quotes
      -- - sr)'  - [S]urround [R]eplace [)] [']
      require('mini.surround').setup()

      -- Simple and easy statusline.
      --  You could remove this setup call if you don't like it,
      --  and try some other statusline plugin
      local statusline = require 'mini.statusline'
      statusline.setup { use_icons = false }

      -- You can configure sections in the statusline by overriding their
      -- default behavior. For example, here we set the section for
      -- cursor location to LINE:COLUMN
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function() return '%2l:%-2v' end

      -- ... and there is more!
      --  Check out: https://github.com/nvim-mini/mini.nvim
    end,
  },

  -- [[ Small Utility Plugins ]]
  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  -- Undo tree visualization
  {
    'mbbill/undotree',
    cmd = 'UndotreeToggle',
    keys = { { '<leader>u', '<cmd>UndotreeToggle<cr>', desc = 'Toggle [U]ndo tree' } },
    config = function()
      vim.g.undotree_WindowLayout = 2
      vim.g.undotree_SetFocusWhenToggle = 1
    end,
  },

  -- Plugins can specify `dependencies` — these are full plugin specs loaded before the parent.
  -- Each plugin module in lua/kickstart/plugins/ returns a lazy.nvim spec table.

  require 'kickstart.plugins.telescope',
  require 'kickstart.plugins.lsp',
  require 'kickstart.plugins.conform',
  require 'kickstart.plugins.blink-cmp',
  require 'kickstart.plugins.treesitter',
  require 'kickstart.plugins.debug',
  require 'kickstart.plugins.lint',
  require 'kickstart.plugins.autopairs',
  require 'kickstart.plugins.neo-tree',
  require 'kickstart.plugins.gitsigns',
  -- require 'kickstart.plugins.indent_line',

  -- Add your own plugins to `lua/custom/plugins/*.lua` and import them here.
  --  See `:help lazy.nvim-🔌-plugin-spec`
  { import = 'custom.plugins' },
}, {
  ui = {
    icons = {
      cmd = '[cmd]',
      config = '[cfg]',
      event = '[event]',
      ft = '[ft]',
      init = '[init]',
      keys = '[keys]',
      plugin = '[plugin]',
      runtime = '[rt]',
      require = '[req]',
      source = '[src]',
      start = '[start]',
      task = '[task]',
      lazy = '[lazy]',
    },
  },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
