-- Auto-close brackets, quotes, etc.
-- https://github.com/windwp/nvim-autopairs

local gh = require('custom.lib.pack').gh

vim.pack.add { gh 'windwp/nvim-autopairs' }
require('nvim-autopairs').setup {}
