-- LSP Configuration
-- See `:help lsp` and `:help lsp-config`

return {
  {
    -- Main LSP Configuration
    -- NOTE: nvim-lspconfig is not called directly but serves as lazy.nvim's dependency
    -- anchor for mason, fidget, and blink.cmp load ordering.
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      -- Mason must be loaded before its dependents so we need to set it up here.
      -- NOTE: `opts = {}` is the same as calling `require('mason').setup({})`
      { 'mason-org/mason.nvim', opts = {} },
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      {
        'j-hui/fidget.nvim',
        opts = {
          notification = {
            window = {
              winblend = 0, -- Transparency (0 = opaque, 100 = fully transparent)
              normal_hl = 'Normal', -- Use Normal highlight (transparent bg)
            },
          },
        },
      },

      -- Allows extra capabilities provided by blink.cmp
      'saghen/blink.cmp',
    },
    config = function()
      -- LSP (Language Server Protocol) provides go-to-definition, references,
      --  completions, diagnostics, and more via external language servers
      --  (e.g., `gopls`, `lua_ls`, `rust_analyzer`).
      --
      -- Mason auto-installs these servers. Treesitter handles syntax highlighting
      --  separately — see `:help lsp-vs-treesitter` for the distinction.

      -- Runs when an LSP attaches to a buffer (e.g., opening `main.rs` triggers `rust_analyzer`)
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- Helper to avoid repeating buffer and description boilerplate for each LSP keymap.
          --  Sets the mode, buffer and description prefix for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
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
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
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
      -- Three config layers, lowest to highest priority:
      --   1. nvim-lspconfig defaults (cmd, filetypes, root_dir, commands) — no files needed
      --   2. after/lsp/*.lua — servers with substantial custom logic (only lua_ls)
      --   3. vim.lsp.config() below — small overrides (settings, init_options)
      --
      -- See `:help lsp-config` for more information.

      -- LSP servers to enable: maps server name → Mason package name.
      -- nvim-lspconfig provides base configs (cmd, filetypes, root_dir, commands).
      -- Server-specific overrides below are merged on top (highest priority).
      -- lua_ls has substantial custom logic and lives in after/lsp/lua_ls.lua.
      local servers = {
        lua_ls = 'lua-language-server',
        ts_ls = 'typescript-language-server',
        rust_analyzer = 'rust-analyzer',
        gopls = 'gopls',
        pyright = 'pyright',
        jsonls = 'json-lsp',
        yamlls = 'yaml-language-server',
        html = 'html-lsp',
        cssls = 'css-lsp',
        hls = 'haskell-language-server',
        jdtls = 'jdtls',
        kotlin_lsp = 'kotlin-lsp',
      }

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

      -- Configure and enable each server with blink.cmp capabilities
      local ensure_installed = {}
      for name, mason_pkg in pairs(servers) do
        vim.lsp.config(name, { capabilities = capabilities })
        vim.lsp.enable(name)
        table.insert(ensure_installed, mason_pkg)
      end

      -- Ensure the servers and tools above are installed via Mason
      --
      -- To check the current status of installed tools and/or manually install
      -- other tools, you can run
      --    :Mason
      --
      -- You can press `g?` for help in this menu.
      vim.list_extend(ensure_installed, {
        'stylua',
        'prettier',
        'prettierd',
        'eslint_d',
        'ruff',
        'google-java-format',
        'ktlint',
      })

      require('mason-tool-installer').setup {
        ensure_installed = ensure_installed,
      }
    end,
  },
}
