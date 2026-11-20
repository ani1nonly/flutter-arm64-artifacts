#!/usr/bin/env bash
# Build one Android-target gen_snapshot variant.
# Usage: bash scripts/build-one.sh <bionic|glibc> <arch> <release|profile>
set -euo pipefail

LIBC="${1:?usage: build-one.sh <bionic|glibc> <arch> <mode>}"
ARCH="${2:-arm64}"
MODE="${3:-release}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$REPO/flutter-src"
OUT="$ROOT/engine/src/out/android_${LIBC}_${MODE}_${ARCH}"

echo "=== building $LIBC gen_snapshot: arch=$ARCH mode=$MODE ==="
echo "    flutter checkout: $ROOT"
echo "    ninja out dir   : $OUT"

# flutter/tools/gn must run from the Flutter checkout root; it resolves
# --out-dir relative to engine/src/out.
cd "$ROOT"
export PATH="$HOME/depot_tools:$PATH"

case "$LIBC" in
  bionic)
    # Termux sysroot + NDK clang, cross-compiled from x64 to aarch64 (bionic).
    SYSROOT="$REPO/sysroot/sysroot"
    TOOLCHAIN="$REPO/sysroot/ndk/toolchains/llvm/prebuilt/linux-x64"
    API=26

    vpython3 engine/src/flutter/tools/gn \
      --android --android-cpu "$ARCH" \
      --no-goma --no-backtrace --clang --lto \
      --no-enable-unittests --no-build-embedder-examples \
      --no-prebuilt-dart-sdk \
      --target-toolchain "$TOOLCHAIN" \
      --runtime-mode "$MODE" \
      --out-dir "android_${LIBC}_${MODE}_${ARCH}" \
      --gn-args symbol_level=0 \
      --gn-args is_termux=true \
      --gn-args is_termux_host=false \
      --gn-args termux_api_level=$API \
      --gn-args "custom_sysroot=\"$SYSROOT\"" \
      --gn-args 'extra_ldflags=["-llog"]'

    ninja -C "$OUT" flutter/third_party/dart/runtime/bin:gen_snapshot -j"$(nproc)"
    ;;

  glibc)
    # Generic aarch64 glibc host, cross-compiled from x64 using the
    # host_clang_cpu approach from upstream PR flutter/flutter#187591.
    # Requires patches/linux-arm64-aot.patch to be applied to the engine.
    vpython3 engine/src/flutter/tools/gn \
      --android --android-cpu "$ARCH" \
      --host-cpu arm64 \
      --no-goma --no-backtrace --clang --lto \
      --no-enable-unittests --no-build-embedder-examples \
      --no-prebuilt-dart-sdk \
      --runtime-mode "$MODE" \
      --out-dir "android_${LIBC}_${MODE}_${ARCH}"

    ninja -C "$OUT" flutter/third_party/dart/runtime/bin:gen_snapshot -j"$(nproc)"
    ;;

  *)
    echo "unknown libc: $LIBC" >&2
    exit 1
    ;;
esac

# Collect the binary into a staging directory.
DIST="$REPO/dist/$LIBC/linux-arm64-android-$MODE"
mkdir -p "$DIST"
GS=$(find "$OUT" -type f -name gen_snapshot | head -1)
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
