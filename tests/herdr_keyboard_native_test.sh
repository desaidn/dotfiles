#!/usr/bin/env bash
# Opt-in native lifecycle check. Requires an already prepared upstream checkout,
# Cargo dependency cache and Zig 0.16. It never downloads or installs anything.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fixture_dir="$repo_root/tests/fixtures/herdr-keyboard/native"
native_revision=034f8b85f7e6bb71f8ff55cb4a80c548b2578c0f
ghostty_revision=291fd050b9e9c293c8adb6a140742649b7e42d3a
fail() { printf 'Native keyboard test: %s\n' "$*" >&2; exit 1; }

if [[ ${1:-} == --help ]]; then
  cat <<'HELP'
Usage: HERDR_NATIVE_SOURCE=/path/to/prepared/herdr-app \
       ZIG=/path/to/zig-0.16.0 \
       HERDR_NATIVE_WORKSPACE=/path/to/test-cache \
       bash tests/herdr_keyboard_native_test.sh

The prepared checkout must contain official Herdr app v0.1.16 and its pinned
Ghostty submodule. Prepare the upstream build dependencies separately. Cargo
runs --offline --locked; the runner cannot fetch missing packages or toolchains.
It uses the active installed Rust toolchain (upstream recommends 1.95 or newer).

The source checkout is read-only. The runner archives its pinned sources into
an owned scratch workspace and applies only native test hooks there. An omitted
HERDR_NATIVE_WORKSPACE creates a temporary directory, retained for evidence and
build-cache reuse. A nonempty foreign workspace is refused. Keep the same
workspace for later runs; changing native source paths can force recompilation.
CARGO_TARGET_DIR may point at an existing native build cache.

The real guide, keys and metadata come from this dotfiles checkout. Keyboard
and click events go only to GPUI TestPlatform with hc::offline(), never to a
running display, terminal service or user session. Each case has isolated homes.
HERDR_NATIVE_CASE selects one named case; the default runs all cases.
HELP
  exit 0
fi
[[ $# == 0 ]] || fail 'unexpected argument; use --help'
[[ -n ${HERDR_NATIVE_SOURCE:-} ]] || fail 'set HERDR_NATIVE_SOURCE to a prepared official v0.1.16 checkout; see --help'
native_source=$(cd -- "$HERDR_NATIVE_SOURCE" && pwd -P)
[[ $(git -C "$native_source" rev-parse 'v0.1.16^{commit}') == "$native_revision" ]] || fail 'prepared source is not the pinned official v0.1.16 tag'
[[ $(git -C "$native_source/vendor/ghostty" rev-parse HEAD) == "$ghostty_revision" ]] || fail 'prepare the pinned Ghostty submodule first'
git -C "$native_source/vendor/ghostty" diff --quiet HEAD -- || fail 'the prepared Ghostty submodule contains local edits'
export RUSTUP_AUTO_INSTALL=0
cargo --version >/dev/null || fail 'select an already installed Rust toolchain'
export ZIG="${ZIG:-$(command -v zig || true)}"
[[ -n "$ZIG" && $("$ZIG" version) == 0.16.0 ]] || fail 'set ZIG to an already installed Zig 0.16.0 executable'
hook_hash=$(shasum -a 256 "$fixture_dir/hooks.patch" | cut -d ' ' -f 1)
expected_marker=$(printf 'herdr-keyboard-native-v1\n%s\n%s\n%s' "$native_revision" "$ghostty_revision" "$hook_hash")

if [[ -n ${HERDR_NATIVE_WORKSPACE:-} ]]; then
  mkdir -p -- "$HERDR_NATIVE_WORKSPACE"
  workspace=$(cd -- "$HERDR_NATIVE_WORKSPACE" && pwd -P)
else
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/herdr-keyboard-native.XXXXXX")
fi
marker="$workspace/.herdr-keyboard-native"
if [[ -f "$marker" ]]; then
  [[ $(cat "$marker") == "$expected_marker" ]] || fail 'workspace belongs to a different native fixture; choose a fresh workspace'
  (cd -- "$workspace/source" && shasum -a 256 -c ../source.sha256 >/dev/null) || fail 'generated native test sources changed; choose a fresh workspace'
else
  [[ -z $(ls -A "$workspace") ]] || fail 'workspace is nonempty and has no native fixture marker; choose a fresh workspace'
  mkdir "$workspace/source"
  git -C "$native_source" archive "$native_revision" | tar -xf - -C "$workspace/source"
  git -C "$native_source/vendor/ghostty" archive "$ghostty_revision" | tar -xf - -C "$workspace/source/vendor/ghostty"
  GIT_CEILING_DIRECTORIES="$workspace" git -C "$workspace/source" apply --check "$fixture_dir/hooks.patch"
  GIT_CEILING_DIRECTORIES="$workspace" git -C "$workspace/source" apply "$fixture_dir/hooks.patch"
  (cd -- "$workspace/source" && shasum -a 256 src/window.rs src/terminal.rs Cargo.toml Cargo.lock > ../source.sha256)
  printf '%s\n' "$expected_marker" > "$marker"
fi

run_dir=$(mktemp -d "$workspace/run.XXXXXX")
printf 'Native test workspace: %s\nNative test evidence: %s\n' "$workspace" "$run_dir"
printf 'running\n' > "$run_dir/status"
exec > >(tee "$run_dir/output.log") 2>&1
trap 'native_status=$?; printf "%s\n" "$native_status" > "$run_dir/status"' EXIT
export HERDR_NATIVE_FIXTURE_DIR="$fixture_dir"
export HERDR_GUIDE_APP_DIR="$repo_root/herdr-app"
export HERDR_TEST_TMPDIR="$run_dir/cases"
export HERDR_APP_HOME="$run_dir/app"
export XDG_STATE_HOME="$run_dir/state"
export HC_SESSION="herdr-keyboard-native-$$"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$workspace/target}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"
mkdir -p "$HERDR_TEST_TMPDIR"
cd -- "$workspace/source"
cargo test --offline --locked --bin herdr-app window::tests::personal_keyboard_lifecycle -- --exact --nocapture --test-threads=1
