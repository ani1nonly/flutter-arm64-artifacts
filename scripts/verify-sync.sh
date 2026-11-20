#!/usr/bin/env bash
# Verify a restored (cached) checkout is complete and still patched.
# Usage: bash scripts/verify-sync.sh <flutter-tag> [bionic|glibc]
set -euo pipefail

TAG="${1:?usage: verify-sync.sh <flutter-tag> [bionic|glibc]}"
VARIANT="${2:-bionic}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$HERE/flutter-src"

[ -d "$ROOT/.git" ] || { echo "ERROR: cached checkout has no .git directory" >&2; exit 1; }
[ -f "$ROOT/bin/internal/engine.version" ] || { echo "ERROR: cached checkout is incomplete" >&2; exit 1; }
[ -d "$ROOT/engine/src" ] || { echo "ERROR: cached checkout has no engine source" >&2; exit 1; }

ACTUAL=$(git -C "$ROOT" describe --tags --always)
echo "restored checkout : $ACTUAL ($VARIANT)"
echo "engine hash       : $(cat "$ROOT/bin/internal/engine.version")"
[ "$ACTUAL" = "$TAG" ] || echo "WARN: cached checkout is $ACTUAL, expected $TAG" >&2

case "$VARIANT" in
  bionic)
    grep -q 'is_termux' "$ROOT/engine/src/build/config/BUILDCONFIG.gn" || {
      echo "ERROR: cached checkout is missing engine.patch" >&2; exit 1; }
    cp "$HERE/config/gclient" "$ROOT/.gclient"
    ;;
  glibc)
    grep -q 'builder_cpu' "$ROOT/engine/src/build/config/BUILDCONFIG.gn" || {
      echo "ERROR: cached checkout is missing linux-arm64-aot.patch" >&2; exit 1; }
    cp "$HERE/config/gclient-glibc" "$ROOT/.gclient"
    ;;
  *)
    echo "unknown variant: $VARIANT" >&2; exit 1
    ;;
esac

mkdir -p "$HERE/logs"
echo "cache verification OK — skipping gclient sync"
