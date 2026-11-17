#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null || { echo "Node is required (managed by Mise)." >&2; exit 1; }
node "$repo_root/tests/fixtures/herdr-keyboard/check.cjs" "$repo_root/herdr-app/mods/keyboard-guide/main.js"
node "$repo_root/tests/fixtures/herdr-keyboard/numbering.cjs" "$repo_root/herdr-app/mods"
node "$repo_root/tests/fixtures/herdr-keyboard/copy.cjs" "$repo_root/herdr-app/mods/keyboard-guide/main.js"
node "$repo_root/tests/fixtures/herdr-keyboard/entrypoints.cjs" "$repo_root/herdr-app"
node "$repo_root/tests/fixtures/herdr-keyboard/commands.cjs" "$repo_root/herdr-app/mods/keyboard-guide/main.js"
