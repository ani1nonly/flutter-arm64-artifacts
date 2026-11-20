#!/usr/bin/env bash
# Checkout Flutter at the given ref and apply the bionic/Termux engine patches.
# Usage: bash scripts/sync.sh <flutter-tag>
set -euo pipefail

TAG="${1:?usage: sync.sh <flutter-tag>}"
ROOT="$PWD/flutter-src"
PATCH_DIR="$PWD/patches"

if [ ! -d "$ROOT/.git" ]; then
    git clone --depth 1 --branch "$TAG" https://github.com/flutter/flutter.git "$ROOT"
fi

cd "$ROOT"

# gclient sync fetches the engine source and third_party deps, then applies
# the custom_hooks from config/gclient (patches/engine.patch, dart.patch, skia.patch).
gclient sync --no-history -v

echo "=== synced Flutter $TAG ==="
git describe --tags --always
cat bin/internal/engine.version
