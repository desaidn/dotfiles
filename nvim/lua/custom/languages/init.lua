-- Collect inert declarations before initializing shared tooling and adapters.
local languages = require 'custom.languages.config'

require 'custom.languages.lsp'
require 'custom.languages.treesitter'
require 'custom.languages.format'
require 'custom.languages.dap'

languages.setup()
