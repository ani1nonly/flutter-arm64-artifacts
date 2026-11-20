#!/usr/bin/env bash
# Checkout Flutter at the given ref and apply the bionic/Termux engine patches.
# Usage: bash scripts/sync.sh <flutter-tag>
set -euo pipefail

TAG="${1:?usage: sync.sh <flutter-tag>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$HERE/flutter-src"

if [ ! -d "$ROOT/.git" ]; then
    echo "=== cloning Flutter $TAG into $ROOT ==="
    git clone --depth 1 --branch "$TAG" https://github.com/flutter/flutter.git "$ROOT"
fi

cd "$ROOT"

# gclient requires a .gclient file in the working directory. The Flutter repo
# does NOT ship one (it lives in the Termux build repo). Copy it in.
cp "$HERE/config/gclient" "$ROOT/.gclient"

echo "=== gclient sync (fetches engine source + applies patches) ==="
gclient sync --no-history -v

echo "=== synced Flutter $TAG ==="
git describe --tags --always
echo "engine: $(cat bin/internal/engine.version)"
echo "patches applied:"
grep -q 'is_termux' engine/src/build/config/BUILDCONFIG.gn && echo "  engine.patch OK" || echo "  engine.patch MISSING"

# Keep logs for debugging (persisted in the CI artifact / local dir).
mkdir -p "$HERE/logs"
cp "$ROOT/.gclient" "$HERE/logs/gclient-used.txt" 2>/dev/null || true
