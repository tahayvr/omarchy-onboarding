#!/bin/bash
# Copies Omi from a Meet Omi checkout into omi/: the Omarchy example's Omi.qml
# and the pack's player and data. Run it after Omi changes, then commit omi/.
#
#   scripts/sync-omi.sh [path to meet-omi]     (default: ./meet-omi)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
src=$(cd "${1:-$root/meet-omi}" && pwd)

[[ -f $src/pack/omi.json ]] || { echo "no Omi pack in $src" >&2; exit 1; }
node "$src/tools/check-player.js" >/dev/null || { echo "the player in $src fails its checks" >&2; exit 1; }

mkdir -p "$root/omi"
cp "$src/examples/omarchy/Omi.qml" "$src/pack/omi.js" "$src/pack/omi.json" "$root/omi/"
version=$(jq -r .version "$src/pack/omi.json")
commit=$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown)
dirty=$(git -C "$src" status --porcelain 2>/dev/null | grep -q . && echo " (with local changes)" || true)
printf 'Omi pack version %s, from meet-omi %s%s\n' "$version" "$commit" "$dirty" > "$root/omi/SOURCE"
cat "$root/omi/SOURCE"
