#!/usr/bin/env bash
# Build one Android-target gen_snapshot variant.
# Usage: bash scripts/build-one.sh <bionic|glibc> <arch> <release|profile>
set -euo pipefail

LIBC="${1:?usage: build-one.sh <bionic|glibc> <arch> <mode>}"
ARCH="${2:-arm64}"
MODE="${3:-release}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer the apt-installed ninja; depot_tools' ninja wrapper needs a bootstrap
# that is not present in the cached checkout.
NINJA=/usr/bin/ninja
[ -x "$NINJA" ] || NINJA=ninja
ROOT="$REPO/flutter-src"
OUT="$ROOT/engine/src/out/android_${MODE}_${ARCH}"
GS=""

echo "=== building $LIBC gen_snapshot: arch=$ARCH mode=$MODE ==="
echo "    flutter checkout: $ROOT"

cd "$ROOT"
export PATH="$HOME/depot_tools:$PATH"

case "$LIBC" in
  bionic)
    # Termux sysroot + NDK clang, cross-compiled from x64 to aarch64 (bionic).
    SYSROOT="$REPO/sysroot/sysroot"
    TOOLCHAIN="$REPO/sysroot/ndk/toolchains/llvm/prebuilt/linux-x64"
    API=26

    python3 engine/src/flutter/tools/gn \
      --android --android-cpu "$ARCH" \
      --no-goma --no-backtrace --clang --lto \
      --no-enable-unittests --no-build-embedder-examples \
      --no-prebuilt-dart-sdk \
      --target-toolchain "$TOOLCHAIN" \
      --runtime-mode "$MODE" \
      --gn-args symbol_level=0 \
      --gn-args is_termux=true \
      --gn-args is_termux_host=false \
      --gn-args termux_api_level=$API \
      --gn-args "custom_sysroot=\"$SYSROOT\"" \
      --gn-args 'extra_ldflags=["-llog"]'

    "$NINJA" -C "$OUT" flutter/third_party/dart/runtime/bin:gen_snapshot -j"$(nproc)"
    ;;

  glibc)
    # Generic aarch64 glibc host. Cross-compile the HOST gen_snapshot from an
    # x64 builder using the approach from upstream flutter/flutter#187591.
    # Build the zip archive target (not the raw Dart target) so the host
    # toolchain is used and the binary actually runs on linux-arm64.
    OUT="$ROOT/engine/src/out/glibc_${MODE}_${ARCH}"
    ZIP_REL="zip_archives/android-arm64-${MODE}/linux-arm64.zip"

    python3 engine/src/flutter/tools/gn \
      --android --android-cpu "$ARCH" \
      --host-cpu arm64 \
      --target-dir "glibc_${MODE}_${ARCH}" \
      --no-goma --no-backtrace --clang --lto \
      --no-enable-unittests --no-build-embedder-examples \
      --no-prebuilt-dart-sdk \
      --runtime-mode "$MODE"

    "$NINJA" -C "$OUT" "$ZIP_REL" -j"$(nproc)"

    STAGE=$(mktemp -d)
    unzip -q "$OUT/$ZIP_REL" -d "$STAGE"
    GS=$(find "$STAGE" -type f -name gen_snapshot | head -1)
    if [ -z "$GS" ]; then
        echo "ERROR: gen_snapshot not found in $OUT/$ZIP_REL" >&2
        unzip -l "$OUT/$ZIP_REL" | head -20 >&2
        exit 1
    fi
    ;;

  *)
    echo "unknown libc: $LIBC" >&2
    exit 1
    ;;
esac

# Collect the binary into a staging directory.
DIST="$REPO/dist/$LIBC/linux-arm64-android-$MODE"
mkdir -p "$DIST"
if [ -z "$GS" ]; then
    GS=$(find "$OUT" -type f -name gen_snapshot | head -1)
fi
if [ -z "$GS" ]; then
    echo "ERROR: gen_snapshot not found in $OUT" >&2
    exit 1
fi
cp "$GS" "$DIST/gen_snapshot"
ENGINE=$(cat "$ROOT/bin/internal/engine.version" 2>/dev/null || echo unknown)
echo "$ENGINE" > "$DIST/engine.version"

cat > "$DIST/manifest.json" <<EOF
{
  "libc": "$LIBC",
  "arch": "$ARCH",
  "mode": "$MODE",
  "engine": "$ENGINE"
}
EOF

echo "=== built: $DIST/gen_snapshot ==="
file "$DIST/gen_snapshot"
