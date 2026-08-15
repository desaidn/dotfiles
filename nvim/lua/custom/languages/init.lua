-- Repository-owned language tooling. Keep loading explicit: package setup,
-- lifecycle policy, and language adapters have ordering requirements.

require 'custom.languages.lsp'
require 'custom.languages.treesitter'
require 'custom.languages.format'
require 'custom.languages.lint'
require 'custom.languages.dap'
require 'custom.languages.adapters.python'
require 'custom.languages.adapters.rust'
