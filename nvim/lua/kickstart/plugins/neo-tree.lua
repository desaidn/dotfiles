-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

local gh = require('custom.lib.pack').gh

local function selected_path(state)
  local node = state.tree:get_node()
  -- Source nodes use absolute paths; unnamed buffers and virtual groups do not.
  if
    not node
    or (node.type ~= 'file' and node.type ~= 'directory' and node.type ~= 'link')
    or type(node.path) ~= 'string'
    or node.path ~= vim.fs.abspath(node.path)
  then
    vim.notify('Selected Neo-tree node has no filesystem path', vim.log.levels.INFO)
    return nil
  end
  return node.path
end

local function copy_absolute_path(state)
  local path = selected_path(state)
  if not path then return end
  vim.fn.setreg('+', path)
  print('Copied absolute path: ' .. path)
end

local function copy_relative_path(state)
  local path = selected_path(state)
  if not path then return end
  local relative = vim.fs.relpath(state.path, path)
  if not relative then
    vim.notify('Selected path is outside the Neo-tree root', vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', relative)
  print('Copied relative path: ' .. relative)
end

vim.pack.add {
  { src = gh 'nvim-neo-tree/neo-tree.nvim', version = vim.version.range '3' },
  gh 'nvim-lua/plenary.nvim',
  gh 'MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '<leader>e', '<cmd>Neotree toggle reveal<CR>', { desc = '[E]xplorer' })

require('neo-tree').setup {
  log_to_file = false,
  window = {
    position = 'right',
    width = function() return math.floor(vim.o.columns * 0.25) end,
    mappings = {
      ['<leader>pa'] = { copy_absolute_path, desc = 'Copy [P]ath [A]bsolute' },
      ['<leader>pr'] = { copy_relative_path, desc = 'Copy [P]ath [R]elative' },
    },
  },
  default_component_configs = {
    icon = {
      folder_closed = '[+]',
      folder_open = '[-]',
      folder_empty = '[.]',
      default = '',
    },
    git_status = {
      symbols = {
        added = '+',
        modified = '~',
        deleted = '_',
        renamed = '>',
        untracked = '?',
        ignored = '.',
        unstaged = 'U',
        staged = 'S',
        conflict = '!',
      },
    },
    indent = {
      indent_size = 2,
      padding = 1,
      with_markers = true,
      indent_marker = '│',
      last_indent_marker = '└',
      highlight = 'NeoTreeIndentMarker',
    },
  },
  filesystem = {
    filtered_items = {
      hide_dotfiles = false,
      hide_hidden = false,
      hide_gitignored = false,
    },
    follow_current_file = {
      enabled = true,
      leave_dirs_open = true,
    },
    use_libuv_file_watcher = true,
  },
  event_handlers = {
    {
      event = 'neo_tree_buffer_enter',
      handler = function()
        vim.wo.number = true
        vim.wo.relativenumber = true
        vim.wo.cursorlineopt = vim.go.cursorlineopt
      end,
    },
  },
}

local manager = require 'neo-tree.sources.manager'
local renderer = require 'neo-tree.ui.renderer'
local filesystem_commands = require 'neo-tree.sources.filesystem.commands'

vim.api.nvim_create_autocmd('FocusGained', {
  group = vim.api.nvim_create_augroup('NeoTreeRefreshOnFocus', { clear = true }),
  desc = 'Refresh the visible Neo-tree filesystem after external changes',
  callback = function()
    local state = manager.get_state 'filesystem'
    if renderer.window_exists(state) then filesystem_commands.refresh(state) end
  end,
})
