-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

local gh = require('kickstart.pack').gh

vim.pack.add {
  { src = gh 'nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
  gh 'nvim-lua/plenary.nvim',
  gh 'MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '<leader>e', '<cmd>Neotree toggle reveal<CR>', { desc = '[E]xplorer' })

require('neo-tree').setup {
  log_to_file = false,
  window = {
    position = 'right',
    width = function() return math.floor(vim.o.columns * 0.25) end,
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
  -- Return focus to neo-tree after opening a file (keeps the explorer visible)
  event_handlers = {
    {
      event = 'file_opened',
      handler = function()
        vim.schedule(function()
          local neo_tree_wins = vim.tbl_filter(function(win)
            return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neo-tree'
          end, vim.api.nvim_list_wins())

          if #neo_tree_wins > 0 then vim.api.nvim_set_current_win(neo_tree_wins[1]) end
        end)
      end,
    },
  },
}
