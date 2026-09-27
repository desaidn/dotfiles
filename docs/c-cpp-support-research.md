# C and C++ support research

Checked 2026-09-26 against the repository at
`b0699d9430f4e68ac586bf19dd6b370a07816d8f` and current primary upstream
documentation. The findings and proposed acceptance checklist below describe that
baseline. Implementation followed on `main` on 2026-09-27; the maintained usage
guide is [C and C++ in Neovim](../nvim/README.md#c-and-c).

## Implementation status

The general adapter is implemented: clangd, both parsers, Conform's canonical
`clang-format` formatter with an explicit buffer-local executable override, and
lazy CodeLLDB launch/attach support using the existing debugger interface. CMake
and Ninja are in Homebrew's inventory, and installer validation checks native C
and C++ compilation and standard-library linking. Rust retains its shared adapter.
No extra plugin, project-path special case, automatic build, or duplicate linter
was added. Existing LSP health reporting, Conform information, and clangd's check
command provide diagnostics; the proposed custom build-information scanner was
not needed.

On the local Apple Silicon machine, the installer integration suite, all 17 Lua
spec harnesses, and Lua diagnostics pass. A mixed C17/C++20 CMake/Ninja project
with a generated header builds and passes CTest. Live Neovim checks cover separate
project settings, completion, rename, project formatting styles, manual-only
formatting, and lazy debugger loading. DuckDB's navigation database was generated
without compiling its executable; header-first attachment, cross-file definitions,
references, workspace symbols, hover, source/header switching, and C++ highlighting
passed. Initial index creation must complete before all cross-file and standard
library results are available. Native Linux execution remains untested.

DuckDB's own `make format_venv` installed its pinned clang-format 11.0.1, but that
executable hangs both inside and outside Neovim, including later `--version`
probes. Its installed Mach-O binary is x86_64 on this Apple Silicon host. The
cause is not established, and no alternative version was silently substituted.
The current Mason formatter passed real C/C++ style checks; DuckDB's pinned
formatter remains a local runtime limitation.

Real C/C++ CodeLLDB tests passed adapter initialization, project-variable
expansion, both launch type names, and breakpoint configuration. The compiled
fixtures ran successfully outside the debugger with arguments, environment,
working directory, redirected input, and C++ containers. Launch and attach then
stalled inside macOS `task_for_pid`; Apple LLDB reproduced the same stall. No
breakpoint hit, variable inspection, STL inspection, or stepping was verified.
`DevToolsSecurity -status` reported disabled, but this alone does not establish
the cause. Check a visible terminal for an authorization prompt before changing
host policy; no security settings were changed during implementation. Apple
documents debugger task-port authorization in its
[debugger entitlement reference](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.debugger).

## Implementation plan in plain language

The result should be one general C/C++ setup: opening a source file automatically
starts code understanding, completion, highlighting, and navigation using that
project's settings. Formatting and debugging use the existing editor controls.
DuckDB is the first real project used to check the result, not a special case in
the implementation. The complete feature scope remains below; learning the
codebase determines the order of delivery rather than removing capabilities.

1. **Install the shared tools once.** Add the code-understanding and formatting
   tools through Neovim's existing tool manager, reuse the debugger already used
   for Rust, and add CMake/Ninja through Homebrew for projects using that build
   system. Check that the machine can compile both C and C++ with their standard
   libraries. Other build systems remain usable.
2. **Make opening a file enough to activate editor support.** Add one C/C++
   language settings file and connect it to the existing language list. Use the
   current keys for finding definitions, references, symbols, and documentation.
   Keep source/header switching, handle a header opened before its source, and
   keep separate projects' settings separate even in one editor session.
3. **Read each project's actual build information.** Reuse its existing
   `compile_commands.json`: a generated list explaining how each source file is
   compiled, including headers, compiler options, and language version. Follow
   project configuration when that list is stored elsewhere. If a complex project
   has no usable build description, explain the limitation and its setup step
   without blocking basic editing or pretending guessed settings are reliable.
   Preparing or refreshing this information is separate from opening the editor;
   do not run arbitrary project build scripts on open. Document setup for common
   CMake and Make workflows without requiring every project to use either one.
4. **Format according to the project.** Keep one formatting command, using the
   project's style file. Provide one shared default formatter and a documented,
   explicit way to select a project's required formatter executable/version.
   A style file does not reliably specify that version. Keep the existing
   format-on-save policy unchanged initially. DuckDB's older formatter is a test
   of this general override, not a reason to remove formatting elsewhere.
5. **Connect building, testing, and debugging.** Keep the project's own build and
   test commands available in the terminal. Existing debugger controls should
   work for C/C++ without first opening Rust. Offer a simple executable picker
   and use saved project launch settings for arguments, environment, and working
   directory. A debug session needs a compiled executable with debug information;
   opening a file does not compile or run it. Document memory-error checks and
   coverage as optional project build tasks, using the same tools where possible.
6. **Prove the setup works beyond the first project.** Start with small real C
   and C++ programs, then verify DuckDB and a separate project with different
   settings. Check completion, cross-file navigation, headers opened first,
   formatting, debug launch/attach, and existing Rust debugging. Test useful
   failure messages for missing tools/build information/executables. Keep the
   platform claims limited to machines actually tested, and document the known
   Linux ARM64 tooling decision separately.

Most implementation belongs in a new
`nvim/lua/custom/languages/adapters/c_cpp.lua`, with small wiring changes in the
language inventory and shared debugger. Build-information troubleshooting uses
the existing diagnostic surfaces. Provisioning changes belong in `Brewfile` and
`install.sh`; usage belongs in the READMEs. Extend the existing behavioral tests
and add real tool checks rather than introducing another configuration framework
or C/C++-specific set of keys.

After setup, ordinary opening should be automatic. The boundary is project
preparation: the project chooses its compiler, libraries, enabled features, and
build targets. Its generated build description must be refreshed when those
choices change. The editor consumes those choices rather than inventing them.

## General C/C++ recommendation and scope

Add C and C++ as one language family in the existing Neovim adapter architecture:
**clangd, C/C++ Tree-sitter parsers, Conform with clang-format, and the existing
CodeLLDB/nvim-dap surface**. Document **CMake + Ninja + CTest** as the reference
build/test workflow. Keep project build commands and test frameworks usable from
the terminal; a CMake UI, test explorer, second language server, or second debugger
is not needed for this baseline.

Here, complete everyday support means editing, semantic navigation, diagnostics,
formatting, building, running, testing, and source debugging of native C/C++
projects on macOS and Linux. Each project still owns its compiler selection,
language standard, flags, libraries, generated files, build configuration, and
test framework. Modules, embedded targets, remote execution, and specialized
toolchains require separate evidence before being advertised as supported.

## What the checkout supported before implementation

These are repository findings, distinct from upstream capabilities:

| Surface | Current state | Gap |
| --- | --- | --- |
| Parsing | `supporting.lua` declares the `c` parser | No `cpp` parser; installing one manually is insufficient because parser attachment follows the declared whitelist |
| LSP/completion | Shared native LSP, Blink completion, diagnostics and navigation exist | No C/C++ server is declared or enabled |
| Formatting | Shared Conform manual formatting exists; C/C++ save formatting is explicitly disabled | No C/C++ formatter is declared |
| Static analysis | Shared infrastructure supports language-owned linting | No C/C++ analysis route is configured |
| Debugging | Rust already requests Mason's CodeLLDB; shared DAP UI/controls and root-aware launch files exist | No C/C++ DAP route or first-use adapter registration |
| Build/test | Native terminal workflow exists | No C/C++ build/test contract or provisioned CMake/Ninja |
| Compiler provisioning | Bootstrap checks `cc` and `make`, and installs native development tools | No explicit C++ compile/link or standard-library validation |

Evidence: [supporting adapter](../nvim/lua/custom/languages/adapters/supporting.lua),
[adapter inventory](../nvim/lua/custom/languages/config.lua),
[parser attachment](../nvim/lua/custom/languages/treesitter.lua),
[LSP setup](../nvim/lua/custom/languages/lsp.lua),
[formatting](../nvim/lua/custom/languages/format.lua),
[Rust adapter](../nvim/lua/custom/languages/adapters/rust.lua),
[DAP lifecycle](../nvim/lua/custom/languages/dap.lua),
[installer](../install.sh), and [Brewfile](../Brewfile).

The current Mac has system compiler/LLDB commands and a Mason CodeLLDB installation.
That does not establish configured C/C++ editor support or a successful debug
session. Shell `PATH`, Neovim's Mason-augmented `PATH`, and tools reachable through
`xcrun` are different inventories.

Local validation used Apple Clang/clangd 21.0.0 on arm64 macOS. Isolated temporary
C17 and C++20 programs compiled and ran successfully, including C++ standard-library
headers; a database containing the real compiler/SDK commands passed Apple
`clangd --check` for both sources with zero errors. `xcrun` also located CLT's
`llvm-cov` and `llvm-profdata`. This verifies the current native compiler/SDK only;
Mason clangd, Neovim attachment, CodeLLDB launches, and Linux remain unvalidated.

## Ownership and dependency changes

Recommended ownership follows the existing [dependency contract](../AGENTS.md):

| Owner | Responsibility | Proposed change |
| --- | --- | --- |
| Platform bootstrap | Native compiler, linker, SDK, standard-library headers, `make` | Validate both C and C++ compilation/linking; preserve the existing bootstrap owner |
| Homebrew | Standalone build applications | Add `cmake` and `ninja` for the reference workflow; CTest is part of CMake |
| Neovim/Mason | Editor packages and tooling | Declare `clangd`, `clang-format`, and `codelldb`; collector deduplicates CodeLLDB already declared by Rust |
| Neovim/Tree-sitter | Syntax parsers | Move `c` into the new adapter and add `cpp` |
| Project | Compiler/version, standard, build presets, dependencies, tests and launch files | Document the contract without generating files or selecting a standard automatically |

Apple's Command Line Tools provide Clang and the macOS SDK; specialized Xcode
workflows may require full Xcode. Do not install a complete second LLVM toolchain
merely to obtain editor tooling. ([Apple CLT](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/))

Homebrew offers both reference build tools on macOS and Linux. Treat their version
requirements as capabilities required by projects, separate from any future exact
provisioning policy. ([CMake formula](https://formulae.brew.sh/formula/cmake),
[Ninja formula](https://formulae.brew.sh/formula/ninja))

**Provisioning limitation:** Mason's current clangd entry has macOS Intel/Apple
silicon and Linux x86-64 GNU assets, but no Linux ARM64 asset. The clang-format entry
is Python-package-backed. Thus this recommendation must not promise identical
automatic installation on every Linux architecture. Linux ARM64 needs an explicit
clangd ownership decision and real validation before it enters the supported
matrix; silently duplicating it in Homebrew would violate this repo's policy.
([clangd registry](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/clangd/package.yaml),
[clang-format registry](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/clang-format/package.yaml))

## Semantic editing and project discovery

clangd supplies completion, diagnostics, fixes, references, definition/declaration
navigation, rename, semantic highlighting, and project indexing. It also embeds
clang-tidy and respects `.clang-tidy`, although not every standalone clang-tidy
check runs inside the server. Rename has limitations involving templates, macros,
inactive code, and related symbols. Treat build/CI diagnostics as authoritative,
not editor silence as proof of correctness. ([clangd features](https://clangd.llvm.org/features))

Use the existing nvim-lspconfig clangd defaults and shared capabilities. Upstream
already supplies source/header switching and symbol-information commands, so an
attachment callback used to disable formatting must preserve that behavior.
There is no initial requirement for `clangd_extensions.nvim`.
([nvim-lspconfig clangd](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/clangd.lua))

Choose the LSP filetype scope deliberately: upstream also includes Objective-C,
Objective-C++, and CUDA. Restrict the new family to `c` and `cpp` for this baseline; parser whitelisting
does not constrain LSP attachment.

Current clangd source enables background indexing and clang-tidy by default.
Avoid copying historical flag bundles unless a tested requirement justifies an
override. In particular, do not impose a global `-std=c++XX` fallback on C files or
on projects with different standards.
([clangd option definitions](https://raw.githubusercontent.com/llvm/llvm-project/main/clang-tools-extra/clangd/tool/ClangdMain.cpp))

### Compilation databases are the central contract

Generate `compile_commands.json` from the actual build. It must describe the
selected compiler, source language/standard, include paths, defines, target,
sysroot, and working directory. Header commands are commonly inferred from a
source file that includes the header or a filename-based heuristic; a header
opened first can therefore receive inappropriate flags. External headers and
mixed C/C++ headers deserve explicit acceptance coverage.
([clangd compile commands](https://clangd.llvm.org/design/compile-commands))

clangd searches ancestor directories and conventional `build/` directories. A
simple uniform-flags scratch project can use `compile_flags.txt`, but that path
does not support background indexing and loses per-file build context. Prefer a
database for real projects. ([clangd project setup](https://clangd.llvm.org/installation#project-setup))

Keep editor project-root detection separate from database discovery. Finding
`CMakeLists.txt` does not establish compiler flags, and nested CMake files often
belong to one larger build. A root helper should not turn every such subdirectory
into an independent project; this is a project-boundary decision to test.

For a nonstandard or nested build location, project `.clangd` can point at its
database directory:

```yaml
CompileFlags:
  CompilationDatabase: build/debug
```

That path is relative to the configuration fragment. Only one active build
configuration should supply the intended semantics at a time; regenerate/reselect
it after changing toolchains or build options. Project `.clangd` also owns targeted
flag adjustments; avoid global include-path guesses. clangd configuration can
override `.clang-tidy` settings, and its default fast-check filter intentionally
omits checks unsuitable for interactive latency.
([clangd configuration](https://clangd.llvm.org/config))

### Compiler, SDK and headers

clangd includes its own built-in headers, not the platform's entire standard
library. The actual compiler and SDK must be usable. Prefer an absolute driver
path in the compilation database. For missing headers, first confirm the database
command builds; then inspect `clangd --check=/absolute/path/to/source.cpp` and its
reported command. A narrowly scoped `--query-driver` allowlist can query a known
compiler for target/system include paths; it executes that compiler, so do not
enable a wildcard matching every project executable. Keep SDK/sysroot and
cross-toolchain paths project- or machine-specific.
([clangd system headers](https://clangd.llvm.org/guides/system-headers))

## Formatting and static analysis

Recommended first change: Conform owns explicit C/C++ formatting through
`clang-format` (the old `clang_format` alias is deprecated); clangd's document/range-formatting capabilities are disabled using
the existing shared policy. Preserve the current disabled save-formatting policy
initially. Full formatting support does not require unrequested rewrites whenever
a file is saved. Enabling save formatting is a separate deliberate policy choice.
([repository formatting owner](../nvim/lua/custom/languages/capabilities.lua),
[Conform formatter](https://raw.githubusercontent.com/stevearc/conform.nvim/master/lua/conform/formatters/clang-format.lua))

The nearest project `.clang-format` or `_clang-format` owns style. Formatter
versions affect supported options, so projects needing reproducible formatting
should document their intended version and align editor/CI behavior. Do not add a
personal global C/C++ style or silently rewrite project configuration.
([clang-format style configuration](https://clang.llvm.org/docs/ClangFormatStyleOptions.html#configuring-style-with-clang-format))

Document that explicit formatting without project configuration uses the
formatter's fallback style. Keeping save formatting disabled avoids making that
fallback an automatic project policy.

Use clangd for interactive clang-tidy diagnostics; do not add a parallel
`nvim-lint` clang-tidy invocation producing duplicate feedback. A project needing
full analysis can run standalone `clang-tidy -p build source.cpp` or
`run-clang-tidy.py -p build` in CI/terminal against the same database. Standalone
clang-tidy is an optional project analysis tool, not a second mandatory editor
owner. Provision it explicitly only when a real project needs it.
([clang-tidy CLI and batch analysis](https://clang.llvm.org/extra/clang-tidy/))

## Building, running and testing

CMake/Ninja is the reference path because it gives a portable native CLI and a
compiler database without an editor plugin. CMake exports databases for Ninja and
Makefile generators; Xcode/Visual Studio generators ignore that option, and unity
builds have documented limitations. A successful configure can still leave
generated headers absent until the necessary generation/build targets run.
([CMake compilation database](https://cmake.org/cmake/help/latest/variable/CMAKE_EXPORT_COMPILE_COMMANDS.html))

Example commands from a project root with `CMakeLists.txt`:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build
ctest --test-dir build --output-on-failure --no-tests=error
```

The first two commands are CMake's native configure/build interface. Run the
resulting target executable directly with its required arguments, environment,
and working directory; neither clangd nor DAP should silently choose or rebuild
an arbitrary executable. ([CMake CLI](https://cmake.org/cmake/help/latest/manual/cmake.1.html))

For repeatable projects, prefer tracked `CMakePresets.json` for shared settings and
ignored `CMakeUserPresets.json` for local settings. Configure/build/test presets
then provide `cmake --preset debug`, `cmake --build --preset debug`, and
`ctest --preset debug`. Configure presets began in CMake 3.19; build/test presets
in 3.20. Let the project's preset schema/features establish its minimum rather
than inventing a universal new minimum here.
([CMake presets](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html))

CTest supports listing with `-N`, filtering by test name with `-R`, rerunning
failures with `--rerun-failed`, and parallel execution. `--no-tests=error` prevents
an accidentally empty test selection from looking successful. Keep these native
commands available even if a test UI is added later.
([CTest CLI](https://cmake.org/cmake/help/latest/manual/ctest.1.html))

| Project test choice | Native integration | Recommendation |
| --- | --- | --- |
| GoogleTest/GoogleMock | `gtest_discover_tests()` registers built test cases with CTest; binary filtering uses `--gtest_filter=Suite.Test` | Respect projects already using it; test one case by passing that argument to the same DAP executable |
| Catch2 | `catch_discover_tests()` registers tests with CTest; the test binary accepts test names/tags | Keep framework dependency and discovery in project CMake files |
| Pure C | CTest can run an ordinary test executable with `add_test`; Unity is a C testing framework | Do not require a C++ testing framework to call C supported |

Sources: [CMake GoogleTest module](https://cmake.org/cmake/help/latest/module/GoogleTest.html),
[GoogleTest filtering](https://google.github.io/googletest/advanced.html#running-a-subset-of-the-tests),
[Catch2 CMake](https://catch2-temp.readthedocs.io/en/latest/cmake-integration.html),
[Catch2 CLI](https://catch2-temp.readthedocs.io/en/latest/command-line.html),
[CMake add_test](https://cmake.org/cmake/help/latest/command/add_test.html), and
[Unity](https://github.com/ThrowTheSwitch/Unity).

Do not migrate existing Make, Meson, Bazel, or vendor build systems merely to use
Neovim. Use their project commands and database exporter. Bear is an optional
fallback for builds that cannot export a database; `bear -- <build-command>`
records compilation activity, so an incremental no-op is insufficient to describe
all translation units. Its interception constraints depend on the platform.
([Bear](https://github.com/rizsotto/Bear))

Package managers such as Conan/vcpkg, test explorers, and a richer build picker are
extensions to evaluate against an actual project. CMake CLI support does not imply
CMake-language editing support: its parser, LSP, or formatter would be separately
owned optional capabilities. None is required for C/C++ semantic support.

## Debugging through the existing interface

Reuse Mason CodeLLDB and the existing nvim-dap/UI controls. CodeLLDB publishes
macOS Intel/Apple silicon and glibc Linux x86-64/ARM builds; that is not a promise
for a musl host or every target architecture.
([CodeLLDB platforms](https://github.com/vadimcn/codelldb#supported-platforms),
[Mason CodeLLDB](https://github.com/mason-org/mason-registry/blob/main/packages/codelldb/package.yaml))

The new family must register CodeLLDB lazily even when C or C++ is the first opened
language. Rust already owns Rust-specific configurations and pretty-printer setup.
Preserve an existing `dap.adapters.codelldb` entry and test both opening orders.
Installed rustaceanvim currently recognizes CodeLLDB through its server adapter
contract; use the compatible TCP `--port ${port}` setup unless the shared lifecycle
is intentionally redesigned and tested. CodeLLDB supports stdio in newer versions,
so this is an integration choice, not a general lack of stdio support.
([repository Rust lifecycle](../nvim/lua/custom/languages/adapters/rust.lua),
[nvim-dap CodeLLDB setup](https://github.com/mfussenegger/nvim-dap/wiki/C-C---Rust-(via--codelldb)))

Keep the TCP adapter loopback-bound and launches user-triggered, following the
repository's existing [debugger trust contract](../nvim/AGENTS.md).

Provide prompted executable launch and process-picker attach defaults. Project
`.vscode/launch.json` should own `program`, `args`, `cwd`, `env`, and advanced source
mapping/LLDB commands. CodeLLDB's VS Code type is `lldb`; the repository already
uses `codelldb`. Accept both through C/C++-local normalization in the existing
launch provider, without globally claiming the `lldb` adapter name.
([CodeLLDB launch/attach](https://github.com/vadimcn/codelldb/blob/master/MANUAL.md),
[repository DAP provider](../nvim/lua/custom/languages/dap.lua))

Decide and test C/C++ DAP root precedence explicitly. The shared provider prefers
an attached language-server root, which may derive from a style file rather than
the intended build/launch boundary. Test ancestor style files, nested projects,
and standalone files; prompted defaults must derive cwd from the same source
context rather than the editor's current directory.

Do not promise arbitrary VS Code extension substitutions or task execution:
`preLaunchTask`, `${command:cmake.launchTargetPath}`, and extension-specific UIs are
not automatically supplied by nvim-dap. Keep building explicit and validate the
supported launch-file subset with the actual provider.
([nvim-dap VS Code configuration](https://github.com/mfussenegger/nvim-dap/blob/master/doc/dap.txt))

Build with full debug information, typically the project's Debug configuration,
and low optimization for predictable stepping. Line-tables-only debug information
cannot supply full variable inspection. Validate `std::string`, `std::vector`, and
`std::map` against the actual standard library; LLDB has libc++/libstdc++ formatters
but their existence does not guarantee all compiler/library combinations.
([Clang debug information](https://clang.llvm.org/docs/UsersManual.html#controlling-size-of-debug-information),
[LLDB type categories](https://lldb.llvm.org/use/variable.html#type-categories))

macOS attach can be constrained by debugger authorization, target signing, and
system protections; Linux attach can be constrained by ptrace policy. Test using
an explicitly started development process and distinguish authorization failures
from adapter setup failures. Do not automate system security changes.
([Apple debugger entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.debugger),
[CodeLLDB troubleshooting](https://github.com/vadimcn/codelldb/blob/master/MANUAL.md))

LLVM `lldb-dap` and GDB's native DAP are legitimate future alternatives for a
project needing their specific behavior. Adding both now would duplicate a working
debugger owner. ([LLVM lldb-dap](https://lldb.llvm.org/use/lldbdap.html),
[GDB DAP](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Debugger-Adapter-Protocol.html))

## Runtime analysis and limits

For projects that need them, recommend an ASan/UBSan build configuration using
`-fsanitize=address,undefined`, debug information, and symbolization. macOS may need
`dsymutil` for useful source locations. These are compiler/runtime analyses, not
editor plugins. ([AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html),
[UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html))

Use a separate ThreadSanitizer configuration; Clang does not permit combining
address/thread/memory sanitizers in one program. Platform support must match the
chosen compiler/runtime. ([Clang sanitizer constraints](https://clang.llvm.org/docs/UsersManual.html),
[ThreadSanitizer](https://clang.llvm.org/docs/ThreadSanitizer.html))

Optional LLVM coverage uses `-fprofile-instr-generate -fcoverage-mapping`, a suitable
`LLVM_PROFILE_FILE` pattern such as `%p` for distinct processes, `llvm-profdata`
merging, and `llvm-cov` reports. Keep instrumentation and matching tools owned by
the project's chosen toolchain; no coverage UI is required.
([LLVM source coverage](https://clang.llvm.org/docs/SourceBasedCodeCoverage.html))

Support boundaries must remain explicit:

- **C++20 modules:** clangd currently calls its support experimental and requires
  an opt-in flag. CMake also documents compiler/generator restrictions. A working
  non-module project does not validate module workflows.
  ([clangd modules](https://clangd.llvm.org/features#experimental-c20-modules-support),
  [CMake modules](https://cmake.org/cmake/help/latest/manual/cmake-cxxmodules.7.html))
- **Remote/container builds:** databases, source paths, generated headers, target
  binaries, and debugger source mappings must describe the same environment.
  Prefer running editor/tooling with the build environment for the first supported
  workflow; remote indexing is not remote compilation or debugging.
- **Embedded/cross compilation:** toolchain files, vendor headers, sysroots,
  flashed targets, probes, and GDB/LLDB remote setup are project work. Querying a
  compiler does not make clangd understand every vendor extension.
- **Native Windows:** the repository's Unix installer remains unsupported there.
  Upstream Windows support in clangd/CodeLLDB does not change that contract.
- **Other language families/features:** Objective-C, CUDA, profiling, core dumps,
  reverse debugging, memory visualizers, and GPU debugging are not established by
  this C/C++ baseline even if an upstream tool exposes related capabilities.

The final four bullets are recommended support boundaries, not claims that these
workflows are impossible. See the existing [platform statement](dependency-research.md)
and upstream tool-specific documentation before widening the tested matrix.

## Concrete implementation checklist

1. Add an inert `adapters/c_cpp.lua` and register it in the explicit adapter list.
   Declare `clangd`, `clang-format`, `codelldb`, `c`/`cpp` parsers, Conform mappings,
   DAP roots/types, and C/C++ formatting policy. Move existing C/C++ declarations
   out of `supporting.lua`; duplicate mappings are rejected by the collector.
2. Preserve upstream clangd callbacks while disabling LSP formatting. Reuse shared
   LSP/completion/navigation keys and existing source/header commands.
3. Add lazy C/C++ DAP registration, preserve Rust adapter ownership, and normalize
   project CodeLLDB types locally. Resolve roots from the source buffer without
   changing editor cwd. Do not start debug adapters or builds during module import.
4. Add CMake/Ninja to the Homebrew inventory if accepting this reference workflow;
   keep compiler bootstrap ownership and add real C/C++ capability checks with
   temporary outputs. Resolve Linux ARM64 clangd ownership before promising it.
5. Document project database/style/test/launch requirements in `nvim/README.md`,
   dependency changes in root `README.md`, and any new constraints/validation in
   the appropriate `AGENTS.md`. Add no new language-specific key namespace.

## Acceptance before calling the support complete

Repository-level checks should cover meaningful behavior: inventory ownership and
deduplication; parser attachment; preservation of clangd commands and formatter
ownership; cold C/C++ DAP setup; two-project root selection; absent executable
errors; and C-before-Rust/Rust-before-C registration. Extend the language harnesses
and run the relevant existing `languages_spec`, `lsp_lifecycle_spec`,
`treesitter_lifecycle_spec`, `context_spec`, `dap_spec`, `dap_launch_spec`, and
`rust_spec`, followed by Lua diagnostics. Run `tests/install_test.sh` for Brewfile
or installer changes. Follow [the required validation commands](../nvim/AGENTS.md).

Then verify the full matrix with real fixtures on native macOS and glibc Linux
x86-64. The limited Mac compiler checks above do not establish this acceptance:

- Compile/link one C and one C++ target including their standard-library headers;
  configure/build a mixed-language CMake project and generated header.
- Open each language first in a fresh Neovim. Check one correct clangd client,
  database-derived standards/defines/includes, completion, cross-file navigation,
  rename, diagnostics/fixes, source/header switching, and parser attachment.
- Open a header before its source and two independent projects without `:cd`;
  check compilation context, formatter style, and launch-file selection.
- Format C/C++ with project style, confirm only Conform formats, and confirm save
  behavior matches the documented policy. Check useful clang-tidy feedback once.
- List/run/filter/rerun CTest cases, including a pure-C executable and one C++
  framework fixture. Verify failures and empty selections are observable.
- Launch C and C++ debug executables with arguments/environment/cwd/stdin; stop
  at breakpoints, step, inspect frames/locals/watches, and inspect real STL values.
  Attach to an explicitly started fixture; verify errors for absent binaries/tools.
- Recheck Rust debugging in both language-opening orders. If claiming sanitizer,
  coverage, modules, Linux ARM64, or remote support, add independent real acceptance
  evidence for each capability instead of inheriting the baseline's result.

## First acceptance project: DuckDB

Checked 2026-09-26 against `/Users/desaidn/Projects/duckdb/` at `d8a1bd4f4fbccdf3d22d8f1fe27a94c11c805d0a` and the current dotfiles. This is a proposed setup; no packages, configuration, build outputs, or project files were changed for this addendum.

### Exercise the shared setup

Use DuckDB to verify the general C/C++ setup, starting with code navigation and then exercising compatible formatting and debugging. Existing completion, search, diagnostics, and syntax highlighting supply the learning interface. The same adapter and controls must work for other C/C++ repositories; this case study does not introduce DuckDB path checks or replace the complete support scope. ([adapter inventory](/Users/desaidn/dotfiles/nvim/lua/custom/languages/config.lua), [shared LSP](/Users/desaidn/dotfiles/nvim/lua/custom/languages/lsp.lua))

Keep nvim-lspconfig defaults with deliberate C/C++ filetypes and preserve its source/header commands. DuckDB's root `.clangd` already identifies the ordinary `src/` workspace. Do not hardcode checkout paths, change editor cwd, impose a standard, or add global include directories. ([upstream clangd configuration](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/clangd.lua), [DuckDB .clangd](/Users/desaidn/Projects/duckdb/.clangd))

After one-time tool/database preparation, opening a C/C++ file should attach clangd and begin indexing automatically. **Opening the checkout should not configure or build DuckDB each time.** Initial indexing may take time before workspace-wide navigation is complete.

### Prepare DuckDB's existing database convention

DuckDB's `.clangd` selects `.cache/clangd/compile_commands.json`. At the research baseline, the checkout had no database/build cache and host CMake was absent. Both were prepared during implementation. Ninja is unnecessary for this configure-only Makefile workflow.

The proposed command, **not executed**, from the DuckDB checkout is:

```sh
CMAKE_GENERATOR='Unix Makefiles' make clangd \
  EXTRA_CMAKE_VARIABLES='-DDISABLE_UNITY=ON'
```

`make clangd` configures CMake under `.cache/clangd/debug` and copies its database without compiling DuckDB. The explicit argument matters: this target does not expand `DISABLE_UNITY_FLAG`, so `DISABLE_UNITY=1 make clangd` is ineffective. DuckDB uses custom unity aggregation; `CMAKE_UNITY_BUILD=OFF` is not equivalent. Its CMake already exports compile commands and defaults to C++17. ([clangd target](/Users/desaidn/Projects/duckdb/Makefile:937), [extra variables](/Users/desaidn/Projects/duckdb/Makefile:271), [CMake settings](/Users/desaidn/Projects/duckdb/CMakeLists.txt:47))

Do not run `make generate-files` for navigation: it regenerates tracked sources and formats code. Later normal builds can overwrite the active database; keep them non-unity or refresh the configure-only database afterward. ([generation target](/Users/desaidn/Projects/duckdb/Makefile:949), [database publication](/Users/desaidn/Projects/duckdb/CMakeLists.txt:56))

### Preserve project analysis and formatting

Honor DuckDB's `.clangd`/`.clang-tidy` checks and exclusions, including its third-party policy. Do not add a duplicate lint runner or global check list. ([project analysis](/Users/desaidn/Projects/duckdb/.clang-tidy), [third-party configuration](/Users/desaidn/Projects/duckdb/third_party/.clangd))

DuckDB tests the general project-override requirement: its script accepts clang-format 11.x and recommends **11.0.1**; its Makefile provisions 11.0.1. A current Mason formatter is not established as compatible with that policy. Keep general Conform formatting support and explicitly select a compatible executable for this project before validating formatting. The shared configuration must not infer versions from arbitrary build scripts or impose DuckDB's version on other projects. Preserve the existing disabled C/C++ save-formatting policy independently of this project. ([version check](/Users/desaidn/Projects/duckdb/scripts/format.py:39), [provisioning](/Users/desaidn/Projects/duckdb/Makefile:804))

An adapter-owned `LspAttach` callback can apply the existing formatting-disable helper only to clangd while preserving upstream `on_attach`/`on_init`; register it during explicit adapter setup. Conform remains the shared manual formatting path; DuckDB acceptance must verify its explicitly selected formatter version. ([format ownership](/Users/desaidn/dotfiles/nvim/lua/custom/languages/capabilities.lua))

### Existing navigation and a first reading exercise

| Action | Key/command |
| --- | --- |
| Find files / search text | `<leader>sf` / `<leader>sg` |
| Definition / declaration | `grd` / `grD` |
| References / implementation / type | `grr` / `gri` / `grt` |
| Hover | `K` |
| Document / workspace symbols | `gO` / `gW` |
| Source/header counterpart | `:LspClangdSwitchSourceHeader` |

These are the existing dotfiles interface, not new bindings. ([Telescope mappings](/Users/desaidn/dotfiles/nvim/lua/kickstart/plugins/telescope.lua), [shared mappings](/Users/desaidn/dotfiles/nvim/lua/custom/languages/lsp.lua))

Start with [simple projection SQL tests](/Users/desaidn/Projects/duckdb/test/sql/projection/test_simple_projection.test), then trace `SELECT 42` through [ClientContext::Query](/Users/desaidn/Projects/duckdb/src/main/client_context.cpp:1189) and [planning orchestration](/Users/desaidn/Projects/duckdb/src/main/client_context.cpp:475). Follow planner → optimizer → physical plan → executor. Current parsing uses PEG and lazy top-level statement parsing; prefer current source over the older parser description in `src/README.md`. ([parse iterator](/Users/desaidn/Projects/duckdb/src/main/parse_iterator.cpp:30), [PEG parser](/Users/desaidn/Projects/duckdb/src/parser/parser.cpp:354))

Acceptance: fresh Neovim opens `.cpp`/`.hpp` without `:cd`, attaches the intended clangd, uses real database commands without missing-header errors, returns cross-file definitions/references and workspace symbols, and preserves source/header switching. Check C++ highlighting on an ordinary-sized file; existing policy skips Tree-sitter above 100 KB. Opening must neither format files nor launch builds/debuggers. ([parser policy](/Users/desaidn/dotfiles/nvim/lua/custom/languages/treesitter.lua))
