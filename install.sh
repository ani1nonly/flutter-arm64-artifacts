#!/usr/bin/env bash
# ============================================================================
# flutter-arm64-artifacts — one-line installer
# ============================================================================
# What it does:
#   1. Finds the required Flutter version (from this repo's latest release).
#   2. Detects any existing Flutter SDK on the device.
#   3. If an older/incompatible version is found: informs you and (with your
#      consent) updates Flutter to the required version FIRST.
#   4. Downloads the matching prebuilt artifacts (bionic or glibc, auto-detected).
#   5. Verifies checksums, installs the binaries, and patches flutter_tools.
#
# ONE-LINE INSTALL (auto-detects everything, prompts only if update needed):
#   curl -fsSL https://raw.githubusercontent.com/ani1nonly/flutter-arm64-artifacts/main/install.sh | bash
#
# NON-INTERACTIVE (auto-accept update):
#   curl -fsSL .../install.sh | bash -s -- --yes
#
# OPTIONS:
#   --flutter-dir DIR   Use this existing Flutter SDK (skip auto-detection)
#   --install-dir DIR   Where to clone a new SDK if none found (default: $HOME/flutter)
#   --tag TAG           Force a specific Flutter tag (default: latest release)
#   --repo OWNER/REPO   GitHub repo hosting releases (default: ani1nonly/flutter-arm64-artifacts)
#   --yes, -y           Auto-accept the Flutter update prompt
#   --no-update         Never update an existing Flutter SDK; abort if mismatched
#   --force             Reinstall artifacts even if already present
#   --prefix PREFIX     Override install prefix (Termux: $PREFIX)
#   --help              Show this help
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via flags or environment)
# ---------------------------------------------------------------------------
REPO="${ARTIFACTS_REPO:-ani1nonly/flutter-arm64-artifacts}"
BRANCH="${ARTIFACTS_BRANCH:-main}"
BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"
RELEASES_API="https://api.github.com/repos/$REPO/releases"
TAG=""
FLUTTER_DIR="${FLUTTER_ROOT:-}"
INSTALL_DIR="${HOME}/flutter"
PREFIX_DIR="${PREFIX:-}"
AUTO_YES=false
NO_UPDATE=false
FORCE=false

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    \033[1;32mOK\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;33mWARN\033[0m %s\n' "$*" >&2; }
err()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
prompt() {
    # Read from /dev/tty so this works even when piped via curl|bash.
    if [ -r /dev/tty ]; then
        read -r -p "    $1 [y/N] " ans < /dev/tty || ans=""
    else
        read -r -p "    $1 [y/N] " ans || ans=""
    fi
    case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --flutter-dir)  FLUTTER_DIR="${2:?--flutter-dir needs a path}"; shift 2 ;;
        --install-dir)  INSTALL_DIR="${2:?--install-dir needs a path}"; shift 2 ;;
        --tag)          TAG="${2:?--tag needs a value}"; shift 2 ;;
        --repo)         REPO="${2:?--repo needs OWNER/REPO}"; shift 2; BASE_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"; RELEASES_API="https://api.github.com/repos/$REPO/releases" ;;
        --prefix)       PREFIX_DIR="$2"; shift 2 ;;
        --yes|-y)       AUTO_YES=true; shift ;;
        --no-update)    NO_UPDATE=true; shift ;;
        --force)        FORCE=true; shift ;;
        --help|-h)      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)              err "unknown option: $1 (try --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Step 0 — Environment check
# ---------------------------------------------------------------------------
log "Step 0/7: Environment check"
for c in curl tar sha256sum git; do
    command -v "$c" >/dev/null 2>&1 || err "required command not found: $c"
done
info "repo        : $REPO"
info "branch      : $BRANCH"
info "install dir : $INSTALL_DIR"
ok "environment OK"

# ---------------------------------------------------------------------------
# Step 1 — Resolve required Flutter tag
# ---------------------------------------------------------------------------
log "Step 1/7: Resolve required Flutter version"
if [ -z "$TAG" ]; then
    info "querying GitHub releases for $REPO ..."
    TAG=$(curl -fsSL "$RELEASES_API?per_page=100" \
        | grep -m1 '"tag_name"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)
    [ -n "$TAG" ] || err "could not resolve latest release tag from $RELEASES_API
  → pass --tag TAG explicitly (e.g. --tag 3.50.1)"
fi
info "required Flutter tag: $TAG"

# Determine host libc (bionic if Android linker is present, else glibc).
if [ -x /system/bin/linker64 ]; then
    LIBC=bionic
    info "host libc     : bionic (Android/Termux host detected)"
else
    LIBC=glibc
    info "host libc     : glibc (generic Linux host)"
fi
ok "target artifacts: $LIBC"

# ---------------------------------------------------------------------------
# Step 2 — Detect existing Flutter SDK
# ---------------------------------------------------------------------------
log "Step 2/7: Detect existing Flutter SDK"
CANDIDATES=""
add_candidate() {
    case " $CANDIDATES " in
        *" $1 "*) return 0 ;;
    esac
    CANDIDATES="${CANDIDATES:+$CANDIDATES }$1"
}
[ -n "$FLUTTER_DIR" ] && add_candidate "$FLUTTER_DIR"
[ -d "$HOME/flutter" ] && add_candidate "$HOME/flutter"
if [ -n "$PREFIX_DIR" ] && [ -x "$PREFIX_DIR/opt/flutter/bin/flutter" ]; then
    add_candidate "$PREFIX_DIR/opt/flutter"
fi
if command -v flutter >/dev/null 2>&1; then
    FP=$(readlink -f "$(command -v flutter)" 2>/dev/null || true)
    if [ -n "$FP" ]; then
        add_candidate "$(dirname "$(dirname "$FP")")"
    fi
fi

EXISTING=""
EXISTING_VER=""
for c in $CANDIDATES; do
    if [ -x "$c/bin/flutter" ]; then
        v=$(cat "$c/version" 2>/dev/null || true)
        if [ -z "$v" ] && [ -d "$c/.git" ]; then
            v=$(git -C "$c" describe --tags --exact-match 2>/dev/null || true)
        fi
        [ -n "$v" ] || v="unknown"
        info "found SDK at $c (version $v)"
        if [ -z "$EXISTING" ]; then
            EXISTING="$c"
            EXISTING_VER="$v"
        fi
    fi
done

if [ -n "$EXISTING" ]; then
    info "selected SDK: $EXISTING (version $EXISTING_VER)"
else
    info "no existing Flutter SDK found"
fi

# ---------------------------------------------------------------------------
# Step 3 — Version check and optional update
# ---------------------------------------------------------------------------
log "Step 3/7: Version compatibility check"
NEED_CLONE=false
if [ -z "$EXISTING" ]; then
    info "no Flutter SDK present → will clone $TAG into $INSTALL_DIR"
    NEED_CLONE=true
elif [ "$EXISTING_VER" = "$TAG" ]; then
    ok "Flutter version already $TAG"
    FLUTTER_DIR="$EXISTING"
else
    warn "version mismatch: installed=$EXISTING_VER required=$TAG"
    if $NO_UPDATE; then
        err "existing Flutter is $EXISTING_VER but artifacts require $TAG.
  → re-run without --no-update, or pass --tag $EXISTING_VER if artifacts exist."
    fi
    if $AUTO_YES || prompt "Update Flutter from $EXISTING_VER to $TAG?"; then
        if [ -d "$EXISTING/.git" ]; then
            info "updating Flutter in $EXISTING to $TAG ..."
            (
                cd "$EXISTING"
                if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
                    git fetch --depth 1 origin tag "$TAG" || git fetch --depth 1 origin "$TAG"
                fi
                git checkout --detach "$TAG"
            ) || err "Flutter update failed"
            EXISTING_VER=$(git -C "$EXISTING" describe --tags --exact-match 2>/dev/null || echo "$TAG")
            ok "Flutter updated to $EXISTING_VER"
            FLUTTER_DIR="$EXISTING"
        else
            warn "$EXISTING is not a git checkout — cannot update in place."
            info "will clone a fresh Flutter $TAG into $INSTALL_DIR instead"
            NEED_CLONE=true
        fi
    else
        warn "update declined."
        info "you can manually update later with:"
        info "  cd $EXISTING && git fetch --depth 1 origin tag $TAG && git checkout $TAG"
        err "aborting: artifacts for $TAG would be incompatible with Flutter $EXISTING_VER"
    fi
fi

# If we need a fresh clone, do it now.
if $NEED_CLONE; then
    mkdir -p "$(dirname "$INSTALL_DIR")"
    info "cloning Flutter $TAG into $INSTALL_DIR (this may take a while) ..."
    git clone --depth 1 --branch "$TAG" https://github.com/flutter/flutter.git "$INSTALL_DIR" \
        || err "git clone failed"
    FLUTTER_DIR="$INSTALL_DIR"
    ok "Flutter cloned"
fi

[ -x "$FLUTTER_DIR/bin/flutter" ] || err "Flutter SDK not found at $FLUTTER_DIR"
ok "using Flutter SDK: $FLUTTER_DIR"

# ---------------------------------------------------------------------------
# Step 4 — Download artifacts + checksum
# ---------------------------------------------------------------------------
log "Step 4/7: Download artifacts"
ASSET="flutter-gen_snapshot-${LIBC}-${TAG}-aarch64.tar.gz"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flutter-arm64-artifacts"
mkdir -p "$CACHE"
OUT="$CACHE/$ASSET"

# Skip download if we already have a verified copy (unless --force).
if [ -s "$OUT" ] && [ -s "$OUT.sha256" ] && ! $FORCE; then
    (cd "$CACHE" && sha256sum -c "$ASSET.sha256") && info "using cached artifact"
else
    info "downloading $ASSET_URL ..."
    curl -fL --retry 3 -o "$OUT" "$ASSET_URL" \
        || err "download failed. Check that release $TAG contains $ASSET"
fi

if [ ! -s "$OUT.sha256" ] || $FORCE; then
    info "downloading checksum ..."
    curl -fL --retry 3 -o "$OUT.sha256" "${ASSET_URL}.sha256" \
        || err "checksum download failed"
fi
(cd "$CACHE" && sha256sum -c "$ASSET.sha256") || err "CHECKSUM MISMATCH — refusing to install"
ok "artifact downloaded and verified: $OUT"

# ---------------------------------------------------------------------------
# Step 5 — Extract and install
# ---------------------------------------------------------------------------
log "Step 5/7: Install artifacts into Flutter SDK"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
tar -xzf "$OUT" -C "$STAGE"
[ -f "$STAGE/install.sh" ] || err "archive missing install.sh"
bash "$STAGE/install.sh" "$FLUTTER_DIR" || err "artifact installer failed"
ok "artifacts installed"

# ---------------------------------------------------------------------------
# Step 6 — Make it survive app-data wipes (portable persistence, optional)
# ---------------------------------------------------------------------------
log "Step 6/7: Persistence setup"
if [ -d /sdcard ]; then
    PDIR="/sdcard/cortex/flutter-arm64-artifacts"
    mkdir -p "$PDIR"
    cp -f "$OUT" "$PDIR/$ASSET" 2>/dev/null || true
    cp -f "$OUT.sha256" "$PDIR/$ASSET.sha256" 2>/dev/null || true
    cp -f "$STAGE/install.sh" "$PDIR/install-artifacts.sh" 2>/dev/null || true
    ok "copied artifacts + installer to $PDIR"
else
    info "no /sdcard found; artifacts cached at $CACHE"
fi

# ---------------------------------------------------------------------------
# Step 7 — Final verification
# ---------------------------------------------------------------------------
log "Step 7/7: Final verification"
E="$FLUTTER_DIR/bin/cache/artifacts/engine"
for mode in release profile; do
    GS="$E/linux-arm64-android-$mode/gen_snapshot"
    if [ -x "$GS" ]; then
        ok "$mode gen_snapshot installed"
        "$GS" --version 2>&1 | head -1 | sed 's/^/       /' || true
    else
        warn "$mode gen_snapshot missing"
    fi
done

cat <<EOF

$(printf '\033[1;32m')============================================================$(printf '\033[0m')
  INSTALL COMPLETE
$(printf '\033[1;32m')============================================================$(printf '\033[0m')

  Flutter SDK : $FLUTTER_DIR   (version $TAG)
  Artifacts   : $LIBC / aarch64   (from release $TAG)
  Cache       : $CACHE

  Next steps:
    cd your-flutter-app
    flutter clean
    flutter build apk --release --target-platform android-arm64
    flutter build apk --profile --target-platform android-arm64

  If you ever wipe app data, re-run this same one-line command:
    curl -fsSL $BASE_URL/install.sh | bash

  To force a specific version:
    curl -fsSL $BASE_URL/install.sh | bash -s -- --tag $TAG --yes
EOF
