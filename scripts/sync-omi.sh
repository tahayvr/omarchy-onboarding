#!/bin/bash
# Updates omi/ from Meet Omi on GitHub: the Omarchy example's Omi.qml and the
# pack's player and data, at a branch, tag or commit. Run it after Omi
# changes upstream, then commit omi/.
#
#   scripts/sync-omi.sh            the latest on master
#   scripts/sync-omi.sh v1.0.0     a tag, a branch, or a full commit hash
#                                  (GitHub can't fetch a short one)
#
# Nothing local is used: it fetches that ref into a temporary directory,
# checks the player against the pack's conformance data there, and copies
# the three files. omi/SOURCE records the repo and the full commit, so a
# sync can be repeated exactly. OMI_REPO overrides the repository URL.
set -euo pipefail

REPO=${OMI_REPO:-https://github.com/tahayvr/meet-omi.git}
REF=${1:-master}
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

command -v node >/dev/null || { echo "sync-omi: node is needed to check the player" >&2; exit 1; }

git -C "$work" init -q
git -C "$work" remote add origin "$REPO"
git -C "$work" fetch -q --depth 1 origin "$REF" || { echo "sync-omi: couldn't fetch '$REF' from $REPO" >&2; exit 1; }
git -C "$work" checkout -q FETCH_HEAD
commit=$(git -C "$work" rev-parse HEAD)

[[ -f $work/pack/omi.json ]] || { echo "sync-omi: no Omi pack at $REF" >&2; exit 1; }
node "$work/tools/check-player.js" >/dev/null || { echo "sync-omi: the player at $REF fails its checks" >&2; exit 1; }

mkdir -p "$root/omi"
cp "$work/examples/omarchy/Omi.qml" "$work/pack/omi.js" "$work/pack/omi.json" "$root/omi/"
version=$(jq -r .version "$work/pack/omi.json")
printf 'Omi pack version %s, from %s at %s (%s)\n' "$version" "${REPO%.git}" "$commit" "$REF" > "$root/omi/SOURCE"
cat "$root/omi/SOURCE"
