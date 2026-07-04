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

-- ============================================================
-- SECTION 1: BASELINE
-- Neovim version check and Lua module cache
-- ============================================================
do
  local version = vim.version()
  local has_supported_version = version.major == 0 and version.minor == 12 and version.patch == 3 and not version.prerelease
  if not has_supported_version then
    vim.api.nvim_echo({
      { ("Unsupported Neovim version: '%s'. Install Neovim 0.12.3.\n"):format(version), 'ErrorMsg' },
      { 'This config follows the latest kickstart.nvim mainline baseline and requires exactly Neovim 0.12.3.' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end

  -- Enable faster startup by caching compiled Lua modules.
  vim.loader.enable()
end

-- ============================================================
-- SECTION 2: OPTIONS
-- Core Neovim settings
-- ============================================================
do
  -- Set <space> as the leader key
  -- See `:help mapleader`
  --  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- Set to true if you have a Nerd Font installed and selected in the terminal.
  vim.g.have_nerd_font = false

  -- Disable netrw to prevent flicker when opening directories (using neo-tree)
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

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

  vim.o.showtabline = 0
end

-- ============================================================
-- SECTION 3: KEYMAPS AND DIAGNOSTICS
-- Basic keymaps plus diagnostic UI
-- ============================================================
do
  -- [[ Diagnostic Config ]]
  -- See `:help vim.diagnostic.Opts`
  vim.diagnostic.config {
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = vim.diagnostic.severity.ERROR },
    signs = {},
    virtual_text = { source = 'if_many', spacing = 2 },
    jump = {
      on_jump = function(_, bufnr)
        vim.diagnostic.open_float {
          bufnr = bufnr,
          scope = 'cursor',
          focus = false,
        }
      end,
    },
  }

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
  --
  -- vim.keymap.set("n", "<C-S-h>", "<C-w>H", { desc = "Move window to the left" })
  -- vim.keymap.set("n", "<C-S-l>", "<C-w>L", { desc = "Move window to the right" })
  -- vim.keymap.set("n", "<C-S-j>", "<C-w>J", { desc = "Move window to the lower" })
  -- vim.keymap.set("n", "<C-S-k>", "<C-w>K", { desc = "Move window to the upper" })
end

-- ============================================================
-- SECTION 4: AUTOCOMMANDS
-- Core editor automation
-- ============================================================
do
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
end

-- ============================================================
-- SECTION 5: PLUGIN MANAGER INTRO
-- vim.pack intro and build hooks
-- ============================================================
do
  -- [[ Intro to `vim.pack` ]]
  -- `vim.pack` is a plugin manager built into Neovim,
  --  which provides a Lua interface for installing and managing plugins.
  --
  --  See `:help vim.pack`, `:help vim.pack-examples` or the
  --  excellent blog post from the creator of vim.pack and mini.nvim:
  --  https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack
  --
  --  To inspect plugin state and pending updates, run
  --    :lua vim.pack.update(nil, { offline = true })
  --
  --  To update plugins, run
  --    :lua vim.pack.update()
  --
  --  Build hooks for plugins that need native binaries or parser updates live in
  --  lua/custom/lib/pack.lua and run after install/update via PackChanged.
  require('custom.lib.pack').setup()
end

-- ============================================================
-- SECTION 6: UI / CORE UX PLUGINS
-- guess-indent, which-key, todo-comments, mini modules, undotree
-- ============================================================
do
  local gh = require('custom.lib.pack').gh

  vim.pack.add { gh 'NMAC427/guess-indent.nvim' }
  require('guess-indent').setup {}

  vim.pack.add { gh 'folke/which-key.nvim' }
  require('which-key').setup {
    preset = 'classic',
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
    spec = {
      { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
      { '<leader>t', group = '[T]oggle' },
      { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
      { '<leader>g', group = '[G]it', mode = { 'n', 'v' } },
      { '<leader>p', group = '[P]ath', mode = { 'n', 'v' } },
      { 'gr', group = 'LSP Actions', mode = { 'n' } },
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
  }

  vim.pack.add { gh 'nvim-mini/mini.nvim' }

  -- Better Around/Inside textobjects
  --
  -- Examples:
  --  - va)  - [V]isually select [A]round [)]paren
  --  - yiiq - [Y]ank [I]nside [I]+1 [Q]uote
  --  - ci'  - [C]hange [I]nside [']quote
  --
  -- mini.ai defaults map next textobjects to `an`/`in`. Neovim 0.12 also uses
  -- those keys for native tree-sitter node selection, but keeping mini.ai's
  -- defaults preserves the established textobject interface. Avoid remapping
  -- them to `aa`/`ii`: those become prefixes and obscure common argument
  -- textobjects like `daa` and `cia`.
  require('mini.ai').setup { n_lines = 500 }

  -- Add/delete/replace surroundings (brackets, quotes, etc.)
  --
  -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
  -- - sd'   - [S]urround [D]elete [']quotes
  -- - sr)'  - [S]urround [R]eplace [)] [']
  require('mini.surround').setup()

  -- Simple and easy statusline.
  --  You could remove this setup call if you don't like it,
  --  and try some other statusline plugin.
  local statusline = require 'mini.statusline'
  statusline.setup { use_icons = vim.g.have_nerd_font }

  -- You can configure sections in the statusline by overriding their
  -- default behavior. For example, here we set the section for
  -- cursor location to LINE:COLUMN
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_location = function() return '%2l:%-2v' end

  vim.pack.add { gh 'folke/todo-comments.nvim', gh 'nvim-lua/plenary.nvim' }
  require('todo-comments').setup { signs = false }

  vim.pack.add { gh 'mbbill/undotree' }
  vim.g.undotree_WindowLayout = 2
  vim.g.undotree_SetFocusWhenToggle = 1
  vim.keymap.set('n', '<leader>u', '<cmd>UndotreeToggle<cr>', { desc = 'Toggle [U]ndo tree' })
end

-- ============================================================
-- SECTION 7: PLUGIN MODULES
-- Modular plugin setup
-- ============================================================
do
  -- Plugins in this module come from upstream nvim-lua/kickstart.nvim.
  require 'kickstart.plugins'

  -- Add your own plugins to `lua/custom/plugins/*.lua`.
  require 'custom.plugins'
end

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
