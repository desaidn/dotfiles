#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NVIM_BIN="$(command -v "${NVIM_BIN:-nvim}")"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-perf-test.XXXXXX")"
FIXTURE="$(CDPATH='' cd -- "$FIXTURE" && pwd -P)"
trap 'rm -rf "$FIXTURE"' EXIT
FIXTURE_REPO="$FIXTURE/repo space\\path"
mkdir -p "$FIXTURE_REPO/scripts" "$FIXTURE_REPO/nvim" "$FIXTURE/home" "$FIXTURE/data" "$FIXTURE/empty"
cp "$REPO_ROOT/scripts/nvim-performance-report.sh" "$FIXTURE_REPO/scripts/"
cat > "$FIXTURE_REPO/nvim/init.lua" <<'LUA'
assert(vim.env.NVIM_APPNAME == 'nvim', 'alternate app selected')
assert(not vim.env.VIMINIT and not vim.env.EXINIT, 'startup override survived')
assert(not vim.env.NVIM and not vim.env.NVIM_LISTEN_ADDRESS, 'parent editor IPC survived')
assert(vim.fn.stdpath('config') == vim.env.PERF_EXPECTED_CONFIG, 'wrong config path')
vim.fn.writefile({ 'loaded' }, vim.env.PERF_TEST_MARKER)
LUA

# Real Neovim loads only the tiny fixture init; no dotfiles plugins or installers
# are run. The checkout path includes literal spaces and a backslash.
# All user data and output paths are isolated under the fixture.
env HOME="$FIXTURE/home" XDG_DATA_HOME="$FIXTURE/data" XDG_DATA_DIRS="$FIXTURE/empty" \
  XDG_CONFIG_DIRS="$FIXTURE/empty" TMPDIR="$FIXTURE" \
  NVIM_APPNAME=other-profile VIMINIT='lua error("unexpected VIMINIT")' EXINIT='cq' \
  NVIM="$FIXTURE/parent.sock" NVIM_LISTEN_ADDRESS="$FIXTURE/parent-listen.sock" \
  PERF_EXPECTED_CONFIG="$FIXTURE_REPO/nvim" PERF_TEST_MARKER="$FIXTURE/loaded" \
  bash "$FIXTURE_REPO/scripts/nvim-performance-report.sh" --nvim-bin "$NVIM_BIN" --skip-shell -n 1 -o "$FIXTURE/report.md"
[ "$(cat "$FIXTURE/loaded")" = loaded ]
grep -Eq '^\| repo config \| 1 \| [0-9]' "$FIXTURE/report.md"
printf 'PASS configured benchmark preserves literal paths and ignores profile, init, and parent IPC overrides\n'

# An otherwise successful binary invocation that omits -u must not be counted
# as a configured sample merely because a startup timing line exists.
cat > "$FIXTURE/skip-config" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = -u ]; then
    shift 2
    args+=( -u NONE )
  else
    args+=( "$1" )
    shift
  fi
done
exec "$PERF_REAL_NVIM" "${args[@]}"
SH
chmod +x "$FIXTURE/skip-config"
env HOME="$FIXTURE/home" XDG_DATA_HOME="$FIXTURE/data" XDG_DATA_DIRS="$FIXTURE/empty" \
  XDG_CONFIG_DIRS="$FIXTURE/empty" TMPDIR="$FIXTURE" PERF_REAL_NVIM="$NVIM_BIN" \
  bash "$FIXTURE_REPO/scripts/nvim-performance-report.sh" --nvim-bin "$FIXTURE/skip-config" --skip-shell -n 1 -o "$FIXTURE/missing-init.md"
grep -Fq 'failed:repo-init-not-loaded' "$FIXTURE/missing-init.md"
grep -Fq '| repo config | 0 | n/a | n/a | n/a |' "$FIXTURE/missing-init.md"
printf 'PASS missing repository init cannot produce a configured timing claim\n'
