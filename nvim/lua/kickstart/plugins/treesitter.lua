-- Treesitter: syntax highlighting and code parsing
-- See `:help nvim-treesitter`

return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    -- Parser installation in `build` (runs on install/update) vs `config` (runs every startup).
    -- This prevents parser checks on every nvim launch.
    build = function()
      require('nvim-treesitter')
        .install({
          'bash',
          'c',
          'diff',
          'html',
          'lua',
          'luadoc',
          'markdown',
          'markdown_inline',
          'query',
          'vim',
          'vimdoc',
          'java',
          'kotlin',
          'javascript',
          'typescript',
          'tsx',
          'css',
          'scss',
          'json',
          'yaml',
          'toml',
          'dockerfile',
          'sql',
          'regex',
          'gitignore',
          'gitcommit',
          'python',
          'go',
          'rust',
          'haskell',
        })
        :wait(60000)
    end,
    config = function()
      require('nvim-treesitter').setup {}

      -- Languages with poor treesitter support
      local skip_langs = { ruby = true, smithy = true }
      local max_filesize = 100 * 1024 -- 100 KB

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('treesitter-start', { clear = true }),
        callback = function(event)
          local lang = vim.treesitter.language.get_lang(event.match) or event.match
          if skip_langs[lang] then return end

          local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(event.buf))
          if ok and stats and stats.size > max_filesize then return end

          pcall(vim.treesitter.start, event.buf, lang)
        end,
      })
    end,
    -- There are additional nvim-treesitter modules that you can use to interact
    -- with nvim-treesitter. You should go explore a few and see what interests you:
    --
    --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
    --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
    --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
  },

  { -- Show treesitter context
    'nvim-treesitter/nvim-treesitter-context',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {},
  },
}
