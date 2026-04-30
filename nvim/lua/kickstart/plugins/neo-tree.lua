-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  keys = {
    { '<leader>e', '<cmd>Neotree toggle reveal<CR>', desc = '[E]xplorer' },
  },
  opts = {
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
        handler = function(file_path)
          vim.schedule(function()
            local neo_tree_wins = vim.tbl_filter(function(win)
              return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neo-tree'
            end, vim.api.nvim_list_wins())

            if #neo_tree_wins > 0 then vim.api.nvim_set_current_win(neo_tree_wins[1]) end
          end)
        end,
      },
    },
  },
}
