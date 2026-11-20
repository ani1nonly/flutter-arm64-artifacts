#!/usr/bin/env bash
# Checkout Flutter at the given ref and apply the patches for the chosen libc.
# Usage: bash scripts/sync.sh <flutter-tag> [bionic|glibc]
set -euo pipefail

TAG="${1:?usage: sync.sh <flutter-tag> [bionic|glibc]}"
VARIANT="${2:-bionic}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$HERE/flutter-src"

echo "=== sync $VARIANT checkout for Flutter $TAG ==="

if [ ! -d "$ROOT/.git" ]; then
    echo "=== cloning Flutter $TAG into $ROOT ==="
    git clone --depth 1 --branch "$TAG" https://github.com/flutter/flutter.git "$ROOT"
fi

cd "$ROOT"

case "$VARIANT" in
  bionic)
    # Termux patches are applied by the gclient custom_hooks in config/gclient.
    cp "$HERE/config/gclient" "$ROOT/.gclient"
    echo "=== gclient sync (Termux patches via custom_hooks) ==="
    gclient sync --no-history -v
    ;;

  glibc)
    # No Termux patches. Apply the upstream #187591 patch in two phases:
    #  1. DEPS hunk BEFORE sync so gclient fetches the linux-arm64 clang
    #  2. remaining hunks AFTER sync so engine source files now exist
    cp "$HERE/config/gclient-glibc" "$ROOT/.gclient"
    echo "=== apply DEPS hunk (fetch arm64 host clang) ==="
    git apply --include=DEPS "$HERE/patches/linux-arm64-aot.patch"
    echo "=== gclient sync (unpatched engine) ==="
    gclient sync --no-history -v
    echo "=== apply remaining #187591 engine patches ==="
    git apply --exclude=DEPS "$HERE/patches/linux-arm64-aot.patch"
    ;;

  *)
    echo "unknown variant: $VARIANT" >&2
    exit 1
    ;;
esac

echo "=== synced Flutter $TAG ($VARIANT) ==="
git describe --tags --always
echo "engine: $(cat bin/internal/engine.version)"

mkdir -p "$HERE/logs"
cp "$ROOT/.gclient" "$HERE/logs/gclient-$VARIANT.txt"

if [ "$VARIANT" = bionic ]; then
    grep -q 'is_termux' engine/src/build/config/BUILDCONFIG.gn \
      && echo "engine.patch applied" || echo "engine.patch MISSING"
else
    grep -q 'builder_cpu' engine/src/build/config/BUILDCONFIG.gn \
      && echo "linux-arm64-aot.patch applied" || echo "linux-arm64-aot.patch MISSING"
fi
