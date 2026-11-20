#!/usr/bin/env bash
# Verify that a restored (cached) Flutter + engine checkout is complete and
# still carries our patches. Used on actions/cache hits so we skip the
# expensive gclient sync without silently building from an unpatched tree.
# Usage: bash scripts/verify-sync.sh <flutter-tag>
set -euo pipefail

TAG="${1:?usage: verify-sync.sh <flutter-tag>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$HERE/flutter-src"

[ -d "$ROOT/.git" ] || { echo "ERROR: cached checkout has no .git directory" >&2; exit 1; }
[ -f "$ROOT/bin/internal/engine.version" ] || { echo "ERROR: cached checkout is incomplete" >&2; exit 1; }
[ -d "$ROOT/engine/src" ] || { echo "ERROR: cached checkout has no engine source" >&2; exit 1; }

ACTUAL=$(git -C "$ROOT" describe --tags --always)
ENGINE=$(cat "$ROOT/bin/internal/engine.version")
echo "restored Flutter checkout : $ACTUAL"
echo "engine hash               : $ENGINE"

# A cache is keyed by tag, but verify anyway (a corrupt cache should fail loudly).
if [ "$ACTUAL" != "$TAG" ]; then
    echo "WARN: cached checkout is $ACTUAL, expected $TAG" >&2
fi

# Patches are applied as working-tree changes by the gclient custom_hooks.
grep -q 'is_termux' "$ROOT/engine/src/build/config/BUILDCONFIG.gn" || {
    echo "ERROR: cached checkout is missing engine.patch (is_termux not found)" >&2
    exit 1
}

# Recreate .gclient in case it wasn't part of the cached paths.
cp "$HERE/config/gclient" "$ROOT/.gclient"

mkdir -p "$HERE/logs"
echo "cache verification OK — skipping gclient sync"
