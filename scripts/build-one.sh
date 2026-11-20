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
    # GitHub's ubuntu-24.04 runners ship the Android NDK; sysroot.py only
    # assembles Termux packages, it does not download an NDK.
    SYSROOT="$REPO/sysroot"
    # The runner sets ANDROID_NDK_HOME but the deployed image has occasionally
    # lacked the actual NDK files. Search every plausible location, verify a
    # real clang++ exists, and install via sdkmanager as a last resort.
    find_ndk() {
        local candidate clangxx
        for candidate in \
            "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK:-}" "${ANDROID_NDK_LATEST_HOME:-}" \
            "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"/ndk/* \
            "${ANDROID_HOME:-}"/ndk/* "$HOME/android-sdk/ndk/"*; do
            [ -n "$candidate" ] && [ -d "$candidate" ] || continue
            # Locate clang++ at any prebuilt/<host>/bin depth -- NDK layouts
            # differ between runner image versions.
            clangxx=$(find "$candidate" -name clang++ -path '*/prebuilt/*/bin/*' -print -quit 2>/dev/null || true)
            if [ -n "$clangxx" ] && [ -x "$clangxx" ]; then
                dirname "$(dirname "$clangxx")"
                return 0
            fi
        done
        return 1
    }
    NDK_HOME=$(find_ndk || true)
    if [ -z "$NDK_HOME" ]; then
        echo "WARN: preinstalled NDK missing; installing via sdkmanager ..." >&2
        SDKM="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}/cmdline-tools/latest/bin/sdkmanager"
        if [ -x "$SDKM" ]; then
            yes | "$SDKM" --install "ndk;27.3.13750724" >&2 || true
            NDK_HOME=$(find_ndk || true)
        fi
    fi
    if [ -z "$NDK_HOME" ]; then
        echo "ERROR: no usable Android NDK. Diagnostics:" >&2
        echo "  ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-unset}" >&2
        ls -la "${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}/ndk" 2>&1 | head -20 >&2 || true
        find /usr/local/lib/android/sdk/ndk -name clang++ -print 2>/dev/null | head -10 >&2 || true
        find /usr/local/lib/android/sdk/ndk -maxdepth 3 -type d 2>/dev/null | head -40 >&2 || true
        exit 1
    fi
    TOOLCHAIN="$NDK_HOME/toolchains/llvm/prebuilt/linux-x64"
    echo "    NDK toolchain: $TOOLCHAIN"
    API=26

    # gn args mirror scripts/build-termux.py::_termux_gn_args(), the canonical
    # Termux configuration. They matter: without them the build links against
    # the wrong libc++/skia config and misses the Android log/EGL stubs.
    VULKAN_INC="$TOOLCHAIN/sysroot/usr/include"
    STUBS="$REPO/scripts/stubs"
    GN_CFLAGS="[\"-I$VULKAN_INC\", \"-I$STUBS\", \"-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__\"]"
    GN_CFLAGS_CC="[\"-I$VULKAN_INC\", \"-I$STUBS\", \"-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__\", \"-Wno-newline-eof\"]"

    python3 engine/src/flutter/tools/gn \
      --android --android-cpu "$ARCH" \
      --no-goma --no-backtrace --clang --lto \
      --no-enable-unittests --no-build-embedder-examples \
      --no-prebuilt-dart-sdk \
      --target-toolchain "$TOOLCHAIN" \
      --runtime-mode "$MODE" \
      --gn-args symbol_level=0 \
      --gn-args arm_use_neon=false \
      --gn-args arm_optionally_use_neon=true \
      --gn-args dart_include_wasm_opt=false \
      --gn-args dart_platform_sdk=false \
      --gn-args is_desktop_linux=false \
      --gn-args use_default_linux_sysroot=false \
      --gn-args skia_use_perfetto=false \
      --gn-args is_termux=true \
      --gn-args is_termux_host=false \
      --gn-args termux_api_level=$API \
      --gn-args "custom_sysroot=\"$SYSROOT\"" \
      --gn-args 'extra_ldflags=["-lEGL", "-lGLESv2", "-llog"]' \
      --gn-args "extra_cflags=$GN_CFLAGS" \
      --gn-args "extra_cflags_cc=$GN_CFLAGS_CC"

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
