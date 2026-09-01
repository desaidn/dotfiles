# Agent tools

`tools/` is the source workspace for small command-line utilities used by
`AGENTS.md`, skills, scripts, people, and other tools.

Each tool has its own directory and keeps its own clear executable name. There
is no generic `tools` command, plugin registry, callback system, or framework.
Tools compose through ordinary command-line arguments, exit status, and JSON
output when structured results are useful. Share infrastructure only after
more than one tool genuinely needs it.

## Included tools

- [`devflow/`](devflow/) provides the independently installed `devflow`
  command for the common agent WIP, review, and squash-landing flow.

The root installer owns installation and removal of packaged tools. Each tool
otherwise keeps its implementation, tests, dependencies, and release metadata
inside its own directory.
