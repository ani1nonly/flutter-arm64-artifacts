#!/usr/bin/env bash
# Package verified artifacts into a tarball with checksums.
# Usage: bash scripts/package-artifacts.sh <bionic|glibc> <flutter-tag>
set -euo pipefail

LIBC="${1:?usage: package-artifacts.sh <libc> <tag>}"
TAG="${2:?usage: package-artifacts.sh <libc> <tag>}"
DIST="$PWD/dist/$LIBC"
OUT="$PWD/dist/$LIBC"
ARCHIVE="$OUT/flutter-gen_snapshot-${LIBC}-${TAG}-aarch64.tar.gz"

# Build an installable layout:
#   <archive>/linux-arm64-android-release/gen_snapshot
#   <archive>/linux-arm64-android-profile/gen_snapshot
#   <archive>/install.sh          (patches flutter_tools + installs wrappers)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

for mode in release profile; do
    src="$DIST/linux-arm64-android-$mode"
    [ -f "$src/gen_snapshot" ] || continue
    mkdir -p "$STAGE/linux-arm64-android-$mode"
    cp "$src/gen_snapshot" "$STAGE/linux-arm64-android-$mode/gen_snapshot"
    cp "$src/engine.version" "$STAGE/linux-arm64-android-$mode/engine.version" 2>/dev/null || true
    cp "$src/manifest.json" "$STAGE/linux-arm64-android-$mode/manifest.json" 2>/dev/null || true
done

cat > "$STAGE/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Install Android-target gen_snapshot into an existing Flutter SDK.
# Usage: bash install.sh /path/to/flutter
set -euo pipefail
FL="${1:?usage: install.sh <flutter-sdk-dir>}"
E="$FL/bin/cache/artifacts/engine"
HERE="$(cd "$(dirname "$0")" && pwd)"

for mode in release profile; do
    [ -f "$HERE/linux-arm64-android-$mode/gen_snapshot" ] || continue
    D="$E/linux-arm64-android-$mode"
    mkdir -p "$D"
    cp "$HERE/linux-arm64-android-$mode/gen_snapshot" "$D/gen_snapshot.real"
    if [ -x /system/bin/linker64 ]; then
        # Bionic binary on an Android-hosted userland — needs linker wrapper.
        cat > "$D/gen_snapshot" <<EOF
#!/bin/sh
exec /system/bin/linker64 "$D/gen_snapshot.real" "\$@"
EOF
    else
        # Standard glibc aarch64 Linux — binary runs directly.
        cp "$HERE/linux-arm64-android-$mode/gen_snapshot" "$D/gen_snapshot"
    fi
    chmod +x "$D/gen_snapshot" "$D/gen_snapshot.real"
done

# Patch flutter_tools artifacts.dart (idempotent).
A="$FL/packages/flutter_tools/lib/src/artifacts.dart"
python3 - "$A" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
marker = '// Cortex: Android AOT requires an Android-target gen_snapshot'
if marker in s:
    print('artifacts.dart already patched'); sys.exit(0)
needle = """        final String hostPlatformName = hostPlatform.cliName;
        return _fileSystem.path.join(engineDir, hostPlatformName, artifact.getFileName(_platform));"""
patch = """        // Cortex: Android AOT requires an Android-target gen_snapshot
        // (target_os=android, compressed-pointers). The Linux desktop binary
        // produces snapshots the Android VM rejects (white screen).
        final String androidSnapshot = _fileSystem.path.join(
          _fileSystem.directory(engineDir).parent.path,
          'linux-arm64-android-${mode.cliName}',
          artifact.getFileName(_platform),
        );
        if (_fileSystem.file(androidSnapshot).existsSync()) {
          return androidSnapshot;
        }

""" + needle
if needle not in s:
    sys.exit('ERROR: artifacts.dart needle not found')
open(p, 'w').write(s.replace(needle, patch, 1))
print('patched artifacts.dart')
PY
rm -f "$FL/bin/cache/flutter_tools.stamp" "$FL/bin/cache/flutter_tools.snapshot"
echo "Done. Run 'flutter clean' then rebuild your APK."
INSTALL
chmod +x "$STAGE/install.sh"

cat > "$STAGE/README.md" <<EOF
# Android-target gen_snapshot for Flutter ($LIBC, aarch64)

Built for Flutter $TAG.

## Install
\`\`\`bash
bash install.sh /path/to/flutter
cd your-app && flutter clean && flutter build apk --release --target-platform android-arm64
\`\`\`

## Contents
- \`linux-arm64-android-release/gen_snapshot\` — release AOT snapshot compiler
- \`linux-arm64-android-profile/gen_snapshot\` — profile AOT snapshot compiler
- \`install.sh\` — installer + flutter_tools patcher
EOF

tar -czf "$ARCHIVE" -C "$STAGE" .
# Write the checksum with a relative (basename) path so the installer's
# `sha256sum -c` works after downloading both files into one cache dir.
(cd "$OUT" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
echo "packaged: $ARCHIVE"
ls -lh "$ARCHIVE" "$ARCHIVE.sha256"
