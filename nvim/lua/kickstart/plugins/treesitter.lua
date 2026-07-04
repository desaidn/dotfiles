-- Treesitter: syntax highlighting and code parsing
-- See `:help nvim-treesitter`

local gh = require('custom.lib.pack').gh

vim.pack.add {
  { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' },
  gh 'nvim-treesitter/nvim-treesitter-context',
}

local treesitter = require 'nvim-treesitter'

-- Older nvim-treesitter configurations exposed setup(); current mainline
-- mostly uses the native vim.treesitter APIs directly.
pcall(treesitter.setup, {})

---@param buf integer
---@param language string
local function treesitter_try_attach(buf, language)
  -- Check if a parser exists and load it
  if not vim.treesitter.language.add(language) then return end

  -- Enable syntax highlighting and other treesitter features
  vim.treesitter.start(buf, language)

  -- Enable treesitter based folds
  -- For more info on folds see `:help folds`
  -- vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  -- vim.wo.foldmethod = 'expr'

  -- Check if treesitter indentation is available for this language, and if so enable it
  -- in case there is no indent query, the indentexpr will fallback to the vim's built in one
  local has_indent_query = vim.treesitter.query.get(language, 'indents') ~= nil

  -- Enable treesitter based indentation
  if has_indent_query then vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()" end
end

-- Languages with poor treesitter support
local skip_langs = { ruby = true, smithy = true }
local max_filesize = 100 * 1024 -- 100 KB
local available_parsers = treesitter.get_available()

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('treesitter-start', { clear = true }),
  callback = function(event)
    local lang = vim.treesitter.language.get_lang(event.match) or event.match
    if skip_langs[lang] then return end

    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(event.buf))
    if ok and stats and stats.size > max_filesize then return end

    local installed_parsers = treesitter.get_installed 'parsers'
    if vim.tbl_contains(installed_parsers, lang) then
      treesitter_try_attach(event.buf, lang)
    elseif vim.tbl_contains(available_parsers, lang) then
      treesitter.install(lang):await(function() treesitter_try_attach(event.buf, lang) end)
    else
      treesitter_try_attach(event.buf, lang)
    end
  end,
})

require('treesitter-context').setup {}
