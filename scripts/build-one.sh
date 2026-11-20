#!/usr/bin/env bash
# Build one Android-target gen_snapshot variant.
# Usage: bash scripts/build-one.sh <bionic|glibc> <arch> <release|profile>
set -euo pipefail

LIBC="${1:?usage: build-one.sh <bionic|glibc> <arch> <mode>}"
ARCH="${2:-arm64}"
MODE="${3:-release}"
ROOT="$PWD/flutter-src"
OUT="$ROOT/out/android_${LIBC}_${MODE}_${ARCH}"
PYTHON="python3"

echo "=== building $LIBC gen_snapshot: arch=$ARCH mode=$MODE ==="

case "$LIBC" in
  bionic)
    # Termux sysroot + NDK clang, cross-compiled from x64 to aarch64 (bionic).
    SYSROOT="$PWD/sysroot/sysroot"
    TOOLCHAIN="$PWD/sysroot/ndk/toolchains/llvm/prebuilt/linux-x64"
    API=26

    export PATH="$HOME/depot_tools:$PATH"
    vpython3 engine/src/flutter/tools/gn \
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
      --gn-args 'extra_ldflags=["-llog"]' \
      --out-dir "android_${LIBC}_${MODE}_${ARCH}"

    ninja -C "$OUT" flutter/third_party/dart/runtime/bin:gen_snapshot -j"$(nproc)"
    ;;

  glibc)
    # Generic aarch64 glibc host, cross-compiled from x64 using the
    # host_clang_cpu approach from upstream PR flutter/flutter#187591.
    export PATH="$HOME/depot_tools:$PATH"
    vpython3 engine/src/flutter/tools/gn \
      --android --android-cpu "$ARCH" \
      --host-cpu arm64 \
      --no-goma --no-backtrace --clang --lto \
      --no-enable-unittests --no-build-embedder-examples \
      --no-prebuilt-dart-sdk \
      --runtime-mode "$MODE" \
      --out-dir "android_${LIBC}_${MODE}_${ARCH}"

    ninja -C "$OUT" clang_arm64/gen_snapshot -j"$(nproc)" || \
      ninja -C "$OUT" flutter/third_party/dart/runtime/bin:gen_snapshot -j"$(nproc)"
    ;;

  *)
    echo "unknown libc: $LIBC" >&2
    exit 1
    ;;
esac

# Collect the binary into a staging directory.
DIST="$PWD/dist/$LIBC/linux-arm64-android-$MODE"
mkdir -p "$DIST"
GS=$(find "$OUT" -type f -name gen_snapshot | head -1)
if [ -z "$GS" ]; then
    echo "ERROR: gen_snapshot not found in $OUT" >&2
    exit 1
fi
cp "$GS" "$DIST/gen_snapshot"
cat engine.version > "$DIST/engine.version" 2>/dev/null || true

# Record which libc and mode this is.
cat > "$DIST/manifest.json" <<EOF
{
  "libc": "$LIBC",
  "arch": "$ARCH",
  "mode": "$MODE",
  "engine": "$(cat engine.version 2>/dev/null || echo unknown)"
}
EOF

echo "=== built: $DIST/gen_snapshot ==="
file "$DIST/gen_snapshot"
