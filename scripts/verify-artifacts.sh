#!/usr/bin/env bash
# Verify that built gen_snapshot binaries are correct for their target libc.
# Usage: bash scripts/verify-artifacts.sh <bionic|glibc>
set -euo pipefail

LIBC="${1:?usage: verify-artifacts.sh <bionic|glibc>}"
DIST="$PWD/dist/$LIBC"

fail=0
for dir in "$DIST"/linux-arm64-android-*; do
    [ -f "$dir/gen_snapshot" ] || continue
    echo "=== $(basename "$dir") ==="
    file "$dir/gen_snapshot"

    # Must be aarch64.
    file -b "$dir/gen_snapshot" | grep -q 'arm64\|aarch64' || {
        echo "FAIL: not aarch64"; fail=1;
    }
    file -b "$dir/gen_snapshot" | grep -q 'stripped' || {
        echo "FAIL: binary is not stripped (unexpected size/regression)"; fail=1;
    }

    # Must have android/compressed-pointers config (not linux desktop).
    strings "$dir/gen_snapshot" | grep -q 'compressed-pointers' || {
        echo "FAIL: no compressed-pointers support"; fail=1;
    }
    strings "$dir/gen_snapshot" | grep -qi 'os_android\|utils_android' || {
        echo "WARN: no android source paths found";
    }

    # Check expected interpreter.
    INTERP=$(readelf -lW "$dir/gen_snapshot" 2>/dev/null | grep -io 'interpreter: [^]]*' | head -1 || true)
    echo "  interpreter: $INTERP"
    case "$LIBC" in
      bionic)
        echo "$INTERP" | grep -q 'linker64' || {
            echo "FAIL: bionic build should use /system/bin/linker64"; fail=1;
        }
        ;;
      glibc)
        echo "$INTERP" | grep -q 'ld-linux-aarch64' || {
            echo "FAIL: glibc build should use /lib/ld-linux-aarch64.so.1"; fail=1;
        }
        ;;
    esac
done

if [ "$fail" -ne 0 ]; then
    echo "VERIFICATION FAILED" >&2
    exit 1
fi
echo "VERIFICATION OK"
