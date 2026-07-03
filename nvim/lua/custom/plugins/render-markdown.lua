--- Markdown rendering inside Neovim.
--- Requires: render-markdown.nvim (https://github.com/MeanderingProgrammer/render-markdown.nvim)
local gh = require('kickstart.pack').gh

local function callout(raw, rendered, highlight, category)
  return { raw = raw, rendered = rendered, highlight = highlight, category = category }
end

vim.pack.add {
  gh 'MeanderingProgrammer/render-markdown.nvim',
  gh 'nvim-treesitter/nvim-treesitter',
}

require('render-markdown').setup {
  file_types = { 'markdown', 'gitcommit' },
  completions = {
    lsp = { enabled = true },
  },
  heading = {
    sign = false,
    icons = { '# ', '## ', '### ', '#### ', '##### ', '###### ' },
    width = 'block',
  },
  code = {
    language_icon = false,
    width = 'block',
    left_pad = 1,
    right_pad = 1,
    min_width = 24,
    border = 'thin',
    inline = false,
  },
  checkbox = {
    unchecked = { icon = '[ ] ' },
    checked = { icon = '[x] ' },
    custom = {
      todo = { raw = '[-]', rendered = '[-] ', highlight = 'RenderMarkdownTodo' },
    },
  },
  link = {
    enabled = false,
  },
  callout = {
    note = callout('[!NOTE]', 'Note', 'RenderMarkdownInfo', 'github'),
    tip = callout('[!TIP]', 'Tip', 'RenderMarkdownSuccess', 'github'),
    important = callout('[!IMPORTANT]', 'Important', 'RenderMarkdownHint', 'github'),
    warning = callout('[!WARNING]', 'Warning', 'RenderMarkdownWarn', 'github'),
    caution = callout('[!CAUTION]', 'Caution', 'RenderMarkdownError', 'github'),
    abstract = callout('[!ABSTRACT]', 'Abstract', 'RenderMarkdownInfo', 'obsidian'),
    summary = callout('[!SUMMARY]', 'Summary', 'RenderMarkdownInfo', 'obsidian'),
    tldr = callout('[!TLDR]', 'Tldr', 'RenderMarkdownInfo', 'obsidian'),
    info = callout('[!INFO]', 'Info', 'RenderMarkdownInfo', 'obsidian'),
    todo = callout('[!TODO]', 'Todo', 'RenderMarkdownInfo', 'obsidian'),
    hint = callout('[!HINT]', 'Hint', 'RenderMarkdownSuccess', 'obsidian'),
    success = callout('[!SUCCESS]', 'Success', 'RenderMarkdownSuccess', 'obsidian'),
    check = callout('[!CHECK]', 'Check', 'RenderMarkdownSuccess', 'obsidian'),
    done = callout('[!DONE]', 'Done', 'RenderMarkdownSuccess', 'obsidian'),
    question = callout('[!QUESTION]', 'Question', 'RenderMarkdownWarn', 'obsidian'),
    help = callout('[!HELP]', 'Help', 'RenderMarkdownWarn', 'obsidian'),
    faq = callout('[!FAQ]', 'Faq', 'RenderMarkdownWarn', 'obsidian'),
    attention = callout('[!ATTENTION]', 'Attention', 'RenderMarkdownWarn', 'obsidian'),
    failure = callout('[!FAILURE]', 'Failure', 'RenderMarkdownError', 'obsidian'),
    fail = callout('[!FAIL]', 'Fail', 'RenderMarkdownError', 'obsidian'),
    missing = callout('[!MISSING]', 'Missing', 'RenderMarkdownError', 'obsidian'),
    danger = callout('[!DANGER]', 'Danger', 'RenderMarkdownError', 'obsidian'),
    error = callout('[!ERROR]', 'Error', 'RenderMarkdownError', 'obsidian'),
    bug = callout('[!BUG]', 'Bug', 'RenderMarkdownError', 'obsidian'),
    example = callout('[!EXAMPLE]', 'Example', 'RenderMarkdownHint', 'obsidian'),
    quote = callout('[!QUOTE]', 'Quote', 'RenderMarkdownQuote', 'obsidian'),
    cite = callout('[!CITE]', 'Cite', 'RenderMarkdownQuote', 'obsidian'),
  },
}

vim.keymap.set('n', '<leader>tm', '<cmd>RenderMarkdown buf_toggle<cr>', { desc = '[T]oggle rendered [M]arkdown' })
