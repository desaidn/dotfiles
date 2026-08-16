# Neovim Java LSP/DAP best practices

Research date: 2026-08-16

Scope: the planned Java vertical slice in this Neovim 0.12.4 configuration.
This note uses upstream Neovim, nvim-jdtls, Eclipse JDT LS, Mason Registry, and
Microsoft Java-debug/test sources. It records implementation constraints rather
than prescribing a second editor workflow.

## Recommended shape

Use `nvim-jdtls` as Java's lifecycle owner.  Load it before Java buffers can
open, but invoke `require('jdtls').start_or_attach(config)` from a `FileType`
`java` autocmd (or an equivalent `ftplugin/java.lua`).  Upstream explicitly
states that the ftplugin path runs on every Java `FileType` event and cautions
not to also enable generic `vim.lsp.enable('jdtls')` in that mode.
[nvim-jdtls configuration](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

`start_or_attach` is the appropriate reuse boundary: calculate one stable,
absolute Java build root for the buffer, then give that exact root in the
configuration on every Java-buffer event.  Do not try to share a client merely
because two directories have the same leaf name, and do not make generic LSP
startup compete with nvim-jdtls.  Neovim's native LSP configuration is still
the common client substrate; nvim-jdtls adds Java-only operations such as
extract refactors, class-file viewing, extended symbols, bytecode/JShell, and
JDT-LS debugger/test support.
[nvim-jdtls extensions](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

### Root policy

Resolve Java roots from the active buffer, never Neovim's process CWD.  Favor
one imported build over a module or a whole unrelated Git checkout:

1. nearest Gradle/Maven workspace marker: `gradlew`, `gradlew.bat`,
   `settings.gradle`, `settings.gradle.kts`, `mvnw`, `mvnw.cmd`, or reactor
   `pom.xml`;
2. nearest module `build.gradle`, `build.gradle.kts`, or `pom.xml` only when
   no workspace marker is available;
3. `.git` only as a non-project fallback.

This is a deliberate refinement of nvim-jdtls's minimal example
(`gradlew`, `.git`, `mvnw`): JDT LS imports Maven and Gradle builds, and its
own documentation says full functionality needs a Gradle or Maven project.
Eclipse JDT LS lists Maven and Gradle support as core features.
[nvim-jdtls root example and troubleshooting](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)
[Eclipse JDT LS features](https://raw.githubusercontent.com/eclipse-jdtls/eclipse.jdt.ls/main/README.md)

Keep this profile in the Java adapter and use the same profile for Java DAP
launch-file lookup.  It is not a universal root algorithm for Rust, Python, or
Kotlin.

## Server process and workspace data

Run the JDT LS process on the repository's Mise-managed Corretto 21.  Current
nvim-jdtls documentation says Eclipse JDT LS requires Java 21; the server can
analyze projects using another JDK (8 or newer) only when that runtime is
provided in `java.configuration.runtimes`.  Project Gradle/Maven toolchains
remain the preferred authority for project compilation.  Do not add a global
list of guessed JDK paths: those are host- and project-specific.  Expose
`JdtSetRuntime` for an installed runtime when a project needs an explicit
selection.
[nvim-jdtls JDK requirements and runtime guidance](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

Pass an explicit `-data` directory.  JDT LS uses it for per-project index
data; without it nvim-jdtls describes a temporary-directory location derived
from CWD, which can require a full reindex after a reboot.  Use the existing
`context.workspace_data('jdtls', root)` path: it is under Neovim's cache,
contains a readable basename plus a hash of the normalized absolute root, and
therefore keeps same-named projects/worktrees isolated.  It must not live in
the repository.  If that state corrupts, use nvim-jdtls's
`JdtWipeDataAndRestart` rather than silently deleting it.
[nvim-jdtls data-directory and recovery guidance](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

Preserve the existing `JDTLS_JVM_ARGS` forwarding when composing the command;
it is the local escape hatch for supported server JVM tuning.  Use only
absolute resolved command and bundle paths: Neovim does not expand `~` in an
LSP `cmd` array.
[nvim-jdtls command-path troubleshooting](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

## Debugging and tests

Install `java-debug-adapter` and `java-test` through Mason.  The registry
packages are Open VSX VSIX distributions and expose their server directories
under Mason's package prefix; `java-debug-adapter` additionally declares the
exact `com.microsoft.java.debug.plugin.jar` share path, and `java-test` declares
its `com.microsoft.java.test.plugin.jar` share path.
[Mason java-debug-adapter package](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/java-debug-adapter/package.yaml)
[Mason java-test package](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/java-test/package.yaml)

Discover those paths with Mason's package API/prefix, rather than a Homebrew
or platform-specific location.  The VSIX currently carries a versioned debug
plugin jar, so glob the `com.microsoft.java.debug.plugin*.jar` prefix rather
than assuming an unversioned filename. Build `init_options.bundles` from that
debug plugin jar plus the Java-test server jars. When globbing test jars, exclude
`com.microsoft.java.test.runner-jar-with-dependencies.jar` and `jacocoagent.jar`;
this is the exact upstream nvim-jdtls filtering rule.  Prefer the explicit
Mason share-path jar for Java debug, and filter only the test directory where
multiple jars are required.
[nvim-jdtls bundle configuration](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

Ensure the shared `custom.languages.dap` core before invoking JDT LS's DAP
setup/startup.  nvim-jdtls automatically registers its `java` adapter only
when nvim-dap is already available; with the bundles loaded it supports
explicit configurations, discovered main classes, and JUnit class/method
debugging.  Java-test is required for test debugging.  Do not register a
second raw Java adapter in the shared DAP module.  Its setup registers both
the `java` adapter and a `jdtls` configuration provider that discovers main
classes during `dap.continue`; do not manually call the alternative helper
that replaces that automatic provider.
[nvim-jdtls DAP integration](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)
[nvim-jdtls DAP source](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/lua/jdtls/dap.lua)

Register Java in the common `dap_by_ft` policy with `launch_types = { 'java' }`
so the existing root-aware `.vscode/launch.json` provider can offer project
launch/attach options.  Let JDT LS discover generated main/test configurations;
the project launch file is the durable route for custom arguments, modules,
environment, and attach details.  Upstream explicitly supports both
`dap.java.configurations` and project-local `.vscode/launch.json` for extra
configurations.
[nvim-jdtls Java DAP configurations](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

The `java-test` Mason package currently advertises JUnit 4, 5, and 6 plus
TestNG support.  Microsoft describes java-debug as a Debug Adapter Protocol
server, so debugger controls remain the existing language-neutral nvim-dap
keys rather than Java-only F-key mappings.
[Mason java-test package](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/java-test/package.yaml)
[Microsoft java-debug](https://github.com/microsoft/java-debug)

## Formatting and commands

JDT LS can format, but this configuration already chooses Google Java Format
through Conform.  Set `init_options.provideFormatter = false` and/or disable
the JDT LS formatting capabilities on attach so there remains exactly one
format-on-save owner.  Do not configure both as fallbacks.

Keep generic Neovim LSP actions and the shared DAP keys as the public editing
interface.  nvim-jdtls's backend-specific commands should be available, not
given a competing custom keymap namespace: `JdtCompile`, `JdtSetRuntime`,
`JdtUpdateConfig`, `JdtRestart`, and, when the debug bundle is available,
`JdtUpdateDebugConfig`/`JdtUpdateHotcode`.  Test actions are exposed by
`require('jdtls').test_class()` and `test_nearest_method()`.
[nvim-jdtls commands and test functions](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)

## Acceptance matrix

Automated configuration tests should prove:

- generic `jdtls` is absent from the enabled-server list; a Java `FileType`
  event calls `start_or_attach` with the active buffer's exact root;
- two Java buffers under one root reuse one identity, while two roots with the
  same basename produce distinct `-data` paths and never mutate global CWD;
- Gradle multi-module and Maven reactor markers select the build root rather
  than an inner module; isolated module roots and standalone files degrade
  predictably;
- Mason debug and test bundle discovery finds only existing absolute paths and
  excludes the two upstream-rejected test jars;
- DAP is ensured before JDT LS registration, Java buffers see only `java`
  launch-file configurations alongside JDT LS's generated-main provider, and
  a changed project `launch.json` is read afresh;
- JDT LS format capabilities are disabled while Conform retains
  `google-java-format` as the only formatter owner.

Manual/integration fixtures should cover a Gradle multi-module project, Maven
reactor, generated sources/dependency navigation, a project whose target JDK
differs from the Java 21 server runtime, discovered main-class debugging,
attach debugging, JUnit 4/5/6 and TestNG class/method debugging, source
refactors, and same-basename worktrees.  JDT LS itself declares support for
Java 8 through 25, Maven, Gradle, standalone files, semantic navigation, code
actions, formatting, and annotation processing; the fixture determines which
of those work with this exact host/toolchain combination.
[Eclipse JDT LS feature list](https://raw.githubusercontent.com/eclipse-jdtls/eclipse.jdt.ls/main/README.md)

## Platform and operational constraints

- The `jdtls` wrapper needs Python 3.9, whereas the server needs Java 21;
  this repository already provides both through Mise.  A direct Java launch is
  an upstream-supported alternative, but Mason's `jdtls` wrapper keeps server
  installation under Neovim ownership.
- Do not hardcode `/opt/homebrew`, `~`, or a Linux JVM path.  Mason package
  prefixes and `stdpath('cache')` are portable; LSP command arrays require
  expanded absolute paths.
- Large projects can overload JDT LS if completion is requested on every typed
  character.  Tune completion policy only when measured, not by weakening
  semantic indexing globally.
- When build files/dependencies change outside Neovim, use `JdtUpdateConfig`
  and restart if needed; JDT LS warns that out-of-editor filesystem changes can
  leave its buffer model stale.

[nvim-jdtls operational troubleshooting](https://raw.githubusercontent.com/mfussenegger/nvim-jdtls/master/README.md)
