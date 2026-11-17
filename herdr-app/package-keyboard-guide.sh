#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# != 1 || -z "$1" ]]; then
    echo "Usage: $0 <new-destination-directory>" >&2
    exit 1
fi
destination="$1"
[[ -f "$source_dir/../LICENSE" ]] || { echo "Missing repository license" >&2; exit 1; }
package_files=(
    mods/keyboard-guide/main.js mods/keyboard-guide/mod.json
    mods/keyboard-tabs/main.js mods/keyboard-tabs/mod.json
    mods/keyboard-agents/main.js mods/keyboard-agents/mod.json
    mods/keyboard-status/main.js mods/keyboard-status/mod.json
    layouts/keyboard.json layouts/keyboard.svg
    upstream/LICENSE-herdr-app-0.1.16 upstream/README.md
)
for file in "${package_files[@]}" mods/keyboard-guide/RECIPE.md mods/keyboard-guide/preview.png; do
    [[ -f "$source_dir/$file" ]] || {
        echo "Missing keyboard guide source: $file" >&2
        exit 1
    }
done
# mkdir is exclusive: never merge into or overwrite an existing package.
mkdir -- "$destination"
for file in "${package_files[@]}"; do
    mkdir -p -- "$(dirname "$destination/$file")"
    cp -- "$source_dir/$file" "$destination/$file"
done
cp -- "$source_dir/mods/keyboard-guide/RECIPE.md" "$source_dir/mods/keyboard-guide/preview.png" \
    "$destination/"
cp -- "$source_dir/../LICENSE" "$destination/LICENSE"
cat > "$destination/keys.json" <<'JSON'
{
  "global": {
    "ctrl-b": "mod.open:keyboard-guide"
  }
}
JSON
printf 'Keyboard guide package: %s\n' "$destination"
