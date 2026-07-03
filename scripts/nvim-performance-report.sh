#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

NVIM_BIN="${NVIM_BIN:-nvim}"
ITERATIONS="${ITERATIONS:-5}"
SKIP_SHELL=0
OUT_FILE=""

usage() {
  cat <<'EOF'
Usage: scripts/nvim-performance-report.sh [options]

Generate a Markdown performance report for this repo's Neovim setup.

Options:
  -n, --iterations N   Number of startup samples to collect. Default: 5
  -o, --out FILE       Markdown report path. Default: reports/nvim-performance-<timestamp>.md
      --nvim-bin BIN   Neovim binary to run. Default: nvim
      --skip-shell     Skip fish/zsh startup timing
  -h, --help           Show this help

Environment:
  NVIM_BIN             Alternative way to set the Neovim binary
  ITERATIONS           Alternative way to set sample count
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n | --iterations)
      [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
      ITERATIONS="$2"
      shift 2
      ;;
    -o | --out)
      [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
      OUT_FILE="$2"
      shift 2
      ;;
    --nvim-bin)
      [ "$#" -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
      NVIM_BIN="$2"
      shift 2
      ;;
    --skip-shell)
      SKIP_SHELL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$ITERATIONS" in
  '' | *[!0-9]*)
    echo "Iterations must be a positive integer." >&2
    exit 2
    ;;
esac

if [ "$ITERATIONS" -lt 1 ]; then
  echo "Iterations must be at least 1." >&2
  exit 2
fi

if ! command -v "$NVIM_BIN" >/dev/null 2>&1; then
  echo "Neovim binary not found: $NVIM_BIN" >&2
  exit 1
fi

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
if [ -z "$OUT_FILE" ]; then
  OUT_FILE="$REPO_ROOT/reports/nvim-performance-$TIMESTAMP.md"
fi

OUT_DIR="$(dirname -- "$OUT_FILE")"
mkdir -p "$OUT_DIR"

TMP_ROOT="${TMPDIR:-/tmp}"
TMP_DIR="$TMP_ROOT/dotfiles-nvim-perf-$TIMESTAMP-$$"
mkdir -p "$TMP_DIR"

NVIM_CACHE_HOME="$TMP_DIR/cache"
NVIM_STATE_HOME="$TMP_DIR/state"
NVIM_RUNTIME_DIR="$TMP_DIR/run"
NVIM_TMPDIR="$TMP_DIR/tmp"
mkdir -p "$NVIM_CACHE_HOME" "$NVIM_STATE_HOME" "$NVIM_RUNTIME_DIR" "$NVIM_TMPDIR"

CLEAN_SAMPLES="$TMP_DIR/clean.samples"
CONFIG_SAMPLES="$TMP_DIR/config.samples"
RUNS_MD="$TMP_DIR/runs.md"
HOTSPOTS_TSV="$TMP_DIR/hotspots.tsv"

: > "$CLEAN_SAMPLES"
: > "$CONFIG_SAMPLES"
: > "$RUNS_MD"
: > "$HOTSPOTS_TSV"

is_number() {
  case "$1" in
    '' | *[!0-9.]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

markdown_escape() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

parse_started_ms() {
  awk '
    /NVIM STARTED/ { value = $1 }
    END {
      if (value != "") {
        printf "%.3f", value
      } else {
        exit 1
      }
    }
  ' "$1"
}

run_startup_sample() {
  local mode="$1"
  local log_file="$2"
  local err_file="$3"
  local status

  set +e
  if [ "$mode" = "clean" ]; then
    XDG_CACHE_HOME="$NVIM_CACHE_HOME" \
      XDG_STATE_HOME="$NVIM_STATE_HOME" \
      XDG_RUNTIME_DIR="$NVIM_RUNTIME_DIR" \
      TMPDIR="$NVIM_TMPDIR" \
      NVIM_LOG_FILE="$TMP_DIR/nvim-$mode.log" \
      "$NVIM_BIN" --clean --headless --startuptime "$log_file" +qa >"$err_file" 2>&1
  else
    XDG_CONFIG_HOME="$REPO_ROOT" \
      XDG_CACHE_HOME="$NVIM_CACHE_HOME" \
      XDG_STATE_HOME="$NVIM_STATE_HOME" \
      XDG_RUNTIME_DIR="$NVIM_RUNTIME_DIR" \
      TMPDIR="$NVIM_TMPDIR" \
      NVIM_LOG_FILE="$TMP_DIR/nvim-$mode.log" \
      "$NVIM_BIN" --headless --startuptime "$log_file" +qa >"$err_file" 2>&1
  fi
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    printf 'failed:%s' "$status"
    return 0
  fi

  if grep -Eq 'Error detected|Error in |E[0-9]+:' "$err_file"; then
    printf 'failed:startup-error'
    return 0
  fi

  if ! parse_started_ms "$log_file"; then
    printf 'no-start-line'
  fi
}

delta_ms() {
  local clean_ms="$1"
  local config_ms="$2"
  if is_number "$clean_ms" && is_number "$config_ms"; then
    awk -v clean="$clean_ms" -v config="$config_ms" 'BEGIN { printf "%.3f", config - clean }'
  else
    printf 'n/a'
  fi
}

stats_line() {
  awk '
    NF {
      n += 1
      value = $1 + 0
      sum += value
      if (n == 1 || value < min) min = value
      if (n == 1 || value > max) max = value
    }
    END {
      if (n == 0) {
        printf "n/a|n/a|n/a|0"
      } else {
        printf "%.3f|%.3f|%.3f|%d", min, sum / n, max, n
      }
    }
  ' "$1"
}

time_command_seconds() {
  local binary="$1"
  shift

  if ! command -v "$binary" >/dev/null 2>&1; then
    printf 'missing'
    return 0
  fi

  local output
  local status
  set +e
  output=$({ /usr/bin/time -p "$binary" "$@" >/dev/null; } 2>&1)
  status=$?
  set -e

  local real_seconds
  real_seconds="$(printf '%s\n' "$output" | awk '$1 == "real" { print $2; exit }')"

  if [ "$status" -ne 0 ]; then
    printf 'failed:%s' "$status"
  elif [ -n "$real_seconds" ]; then
    printf '%s' "$real_seconds"
  else
    printf 'n/a'
  fi
}

seconds_to_ms() {
  if is_number "$1"; then
    awk -v seconds="$1" 'BEGIN { printf "%.0f", seconds * 1000 }'
  else
    printf '%s' "$1"
  fi
}

startup_note() {
  local avg="$1"
  if ! is_number "$avg"; then
    printf 'The configured startup benchmark did not complete cleanly.'
    return 0
  fi

  awk -v avg="$avg" 'BEGIN {
    if (avg < 100) {
      print "Configured startup is excellent."
    } else if (avg < 200) {
      print "Configured startup is good, but eager plugin setup is worth watching."
    } else {
      print "Configured startup is slow enough to justify profiling eager plugin setup."
    }
  }'
}

printf '| Run | Clean startup ms | Config startup ms | Delta ms |\n' >> "$RUNS_MD"
printf '| ---: | ---: | ---: | ---: |\n' >> "$RUNS_MD"

i=1
while [ "$i" -le "$ITERATIONS" ]; do
  clean_log="$TMP_DIR/clean-$i.log"
  clean_err="$TMP_DIR/clean-$i.err"
  config_log="$TMP_DIR/config-$i.log"
  config_err="$TMP_DIR/config-$i.err"

  clean_ms="$(run_startup_sample clean "$clean_log" "$clean_err")"
  config_ms="$(run_startup_sample config "$config_log" "$config_err")"
  delta="$(delta_ms "$clean_ms" "$config_ms")"

  if is_number "$clean_ms"; then
    printf '%s\n' "$clean_ms" >> "$CLEAN_SAMPLES"
  fi
  if is_number "$config_ms"; then
    printf '%s\n' "$config_ms" >> "$CONFIG_SAMPLES"
  fi

  printf '| %s | %s | %s | %s |\n' "$i" "$clean_ms" "$config_ms" "$delta" >> "$RUNS_MD"

  i=$((i + 1))
done

IFS='|' read -r clean_min clean_avg clean_max clean_n <<EOF
$(stats_line "$CLEAN_SAMPLES")
EOF

IFS='|' read -r config_min config_avg config_max config_n <<EOF
$(stats_line "$CONFIG_SAMPLES")
EOF

avg_delta="$(delta_ms "$clean_avg" "$config_avg")"

last_config_log="$TMP_DIR/config-$ITERATIONS.log"
if [ -f "$last_config_log" ]; then
  awk '
    NF >= 3 && $1 ~ /^[0-9.]+$/ && $2 ~ /^[0-9.]+$/ {
      cost = $2
      message = $0
      sub(/^[[:space:]]*[0-9.]+[[:space:]]+[0-9.]+[[:space:]]+([0-9.]+:)?[[:space:]]*/, "", message)
      if (cost >= 1) {
        printf "%.3f\t%s\n", cost, message
      }
    }
  ' "$last_config_log" | sort -nr | head -20 > "$HOTSPOTS_TSV"
fi

fish_seconds="skipped"
zsh_seconds="skipped"
if [ "$SKIP_SHELL" -eq 0 ]; then
  fish_seconds="$(time_command_seconds fish -ic exit)"
  zsh_seconds="$(time_command_seconds zsh -ic exit)"
fi

nvim_version="$("$NVIM_BIN" --version | sed -n '1p')"
uname_value="$(uname -a)"
git_head="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
git_branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || printf 'unknown')"
git_status="$(git -C "$REPO_ROOT" status --short 2>/dev/null || true)"
if [ -z "$git_status" ]; then
  git_status="clean"
fi

{
  printf '# Neovim Performance Report\n\n'
  printf '%s\n' "- Generated: \`$(date '+%Y-%m-%d %H:%M:%S %Z')\`"
  printf '%s\n' "- Repo: \`$REPO_ROOT\`"
  printf '%s\n' "- Git: \`$git_head\` on \`$git_branch\`"
  printf '%s\n' "- Neovim: \`$nvim_version\`"
  printf '%s\n' "- System: \`$uname_value\`"
  printf '%s\n' "- Iterations: \`$ITERATIONS\`"
  printf '%s\n\n' "- Raw logs: \`$TMP_DIR\`"
  printf 'Neovim is run with scratch cache, state, runtime, and temp directories under the raw log directory. User plugin data is still used, so the configured setup is measured without polluting normal state files.\n\n'

  printf '## Summary\n\n'
  printf '%s\n\n' "$(startup_note "$config_avg")"
  printf '| Target | Runs | Min ms | Avg ms | Max ms |\n'
  printf '| --- | ---: | ---: | ---: | ---: |\n'
  printf '| `nvim --clean` | %s | %s | %s | %s |\n' "$clean_n" "$clean_min" "$clean_avg" "$clean_max"
  printf '| repo config | %s | %s | %s | %s |\n' "$config_n" "$config_min" "$config_avg" "$config_max"
  printf '| config overhead | - | - | %s | - |\n\n' "$avg_delta"

  printf '## Startup Samples\n\n'
  cat "$RUNS_MD"
  printf '\n'

  printf '## Shell Startup\n\n'
  printf '| Shell | Startup ms |\n'
  printf '| --- | ---: |\n'
  printf '| fish | %s |\n' "$(seconds_to_ms "$fish_seconds")"
  printf '| zsh | %s |\n\n' "$(seconds_to_ms "$zsh_seconds")"

  printf '## Startup Hotspots\n\n'
  if [ -s "$HOTSPOTS_TSV" ]; then
    printf 'Top entries from the final configured startup sample, sorted by reported cost.\n\n'
    printf '| Cost ms | Entry |\n'
    printf '| ---: | --- |\n'
    while IFS="$(printf '\t')" read -r cost entry; do
      printf '| %s | `%s` |\n' "$cost" "$(markdown_escape "$entry")"
    done < "$HOTSPOTS_TSV"
    printf '\n'
  else
    printf 'No individual startup entries above 1 ms in the final configured sample.\n\n'
  fi

  printf '## Commands\n\n'
  printf '```sh\n'
  printf 'XDG_CACHE_HOME=<scratch>/cache XDG_STATE_HOME=<scratch>/state XDG_RUNTIME_DIR=<scratch>/run TMPDIR=<scratch>/tmp %s --clean --headless --startuptime <log> +qa\n' "$NVIM_BIN"
  printf 'XDG_CONFIG_HOME=%s XDG_CACHE_HOME=<scratch>/cache XDG_STATE_HOME=<scratch>/state XDG_RUNTIME_DIR=<scratch>/run TMPDIR=<scratch>/tmp %s --headless --startuptime <log> +qa\n' "$REPO_ROOT" "$NVIM_BIN"
  if [ "$SKIP_SHELL" -eq 0 ]; then
    printf '/usr/bin/time -p fish -ic exit\n'
    printf '/usr/bin/time -p zsh -ic exit\n'
  fi
  printf '```\n\n'

  printf '## Git Status\n\n'
  printf '```text\n'
  printf '%s\n' "$git_status"
  printf '```\n'
} > "$OUT_FILE"

printf 'Wrote %s\n' "$OUT_FILE"
