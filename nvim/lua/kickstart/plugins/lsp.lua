-- LSP Configuration
-- See `:help lsp` and `:help lsp-config`

local gh = require('custom.lib.pack').gh
local tooling = require 'custom.language_tooling'

vim.pack.add {
  gh 'neovim/nvim-lspconfig',
  gh 'mason-org/mason.nvim',
  gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  gh 'j-hui/fidget.nvim',
  { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' },
}

-- Automatically install LSPs and related tools to stdpath for Neovim.
require('mason').setup {}

-- Useful status updates for LSP.
require('fidget').setup {
  notification = {
    window = {
      winblend = 0,
      normal_hl = 'Normal',
    },
  },
}

-- Runs when an LSP attaches to a buffer (e.g., opening `main.rs` triggers `rust_analyzer`)
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
  callback = function(event)
    -- Helper to avoid repeating buffer and description boilerplate for each LSP keymap.
    --  Sets the mode, buffer and description prefix for us each time.
    local map = function(keys, func, desc, mode)
      mode = mode or 'n'
      vim.keymap.set(mode, keys, func, { buf = event.buf, desc = 'LSP: ' .. desc })
    end

    -- WARN: This is not Goto Definition, this is Goto Declaration.
    --  For example, in C this would take you to the header.
    map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

    -- The following two autocommands are used to highlight references of the
    -- word under your cursor when your cursor rests there for a little while.
    --    See `:help CursorHold` for information about when this is executed
    --
    -- When you move your cursor, the highlights will be cleared (the second autocommand).
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client:supports_method('textDocument/documentHighlight', event.buf) then
      local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        buf = event.buf,
        group = highlight_augroup,
        callback = vim.lsp.buf.document_highlight,
      })

      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buf = event.buf,
        group = highlight_augroup,
        callback = vim.lsp.buf.clear_references,
      })

      vim.api.nvim_create_autocmd('LspDetach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
        callback = function(event2)
          vim.lsp.buf.clear_references()
          vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buf = event2.buf }
        end,
      })
    end

    -- The following code creates a keymap to toggle inlay hints in your
    -- code, if the language server you are using supports them
    --
    -- This may be unwanted, since they displace some of your code
    if client and client:supports_method('textDocument/inlayHint', event.buf) then
      map('<leader>th', function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end, '[T]oggle Inlay [H]ints')
    end
  end,
})

-- LSP servers and clients are able to communicate to each other what features they support.
--  By default, Neovim doesn't support everything that is in the LSP specification.
--  When you add blink.cmp, luasnip, etc. Neovim now has *more* capabilities.
--  So, we create new capabilities with blink.cmp, and then broadcast that to the servers.
local capabilities = require('blink.cmp').get_lsp_capabilities()

-- [[ Native LSP Configuration (Neovim 0.11+) ]]
--
-- Four config layers, lowest to highest priority:
--   1. vim.lsp.config('*') — shared client capabilities
--   2. nvim-lspconfig defaults (cmd, filetypes, root_dir, commands) — no files needed
--   3. after/lsp/*.lua — servers with substantial custom logic (only lua_ls)
--   4. vim.lsp.config() below — small server-specific overrides (settings, init_options)
--
-- See `:help lsp-config` for more information.

vim.lsp.config('*', { capabilities = capabilities })

-- Server-specific overrides (highest priority, merged on top of nvim-lspconfig defaults)
vim.lsp.config('rust_analyzer', {
  settings = {
    ['rust-analyzer'] = {
      cargo = { allFeatures = true },
      check = { command = 'clippy' },
    },
  },
})

vim.lsp.config('gopls', {
  settings = {
    gopls = {
      completeUnimported = true,
      usePlaceholders = true,
      analyses = { unusedparams = true },
    },
  },
})

vim.lsp.config('yamlls', { settings = { yaml = { keyOrdering = false } } })

vim.lsp.config('jdtls', { init_options = { provideFormatter = false } })

vim.lsp.config('jsonls', { init_options = { provideFormatter = false } })
vim.lsp.config('cssls', { init_options = { provideFormatter = false } })
vim.lsp.config('html', { init_options = { provideFormatter = false } })

vim.lsp.enable(tooling.lsp_servers)

-- Ensure declared language servers, formatters, and linters are installed via Mason.
--
-- To check the current status of installed tools and/or manually install
-- other tools, you can run
--    :Mason
--
-- You can press `g?` for help in this menu.
require('mason-tool-installer').setup {
  ensure_installed = tooling.mason_tools,
}
