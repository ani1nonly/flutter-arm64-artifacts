# Flutter linux-arm64 host artifacts

Build the **missing host artifacts** for Flutter on aarch64 Linux hosts — both
**bionic** (Termux / Android-hosted userlands) and **glibc** (generic ARM64 Linux)
— and publish them as installable patch packages that work with any stock
Flutter SDK.

## Why

Flutter does not publish Android-target `gen_snapshot` binaries for linux-arm64
hosts. Without them, `flutter build apk --release/--profile` compiles AOT
snapshots tagged `arm64 linux no-compressed-pointers`, which the Android VM
rejects → **white-screen app**. Only debug (JIT) works.

This project fills that gap by:

1. Tracking **latest Flutter stable** automatically (weekly canary + manual).
2. Cross-compiling the Android-target `gen_snapshot` from x86_64 CI runners:
   - **bionic** flavor via the Termux sysroot + NDK (from `flutter-for-termux`)
   - **glibc** flavor via `--host-cpu=arm64` (from upstream PR #187591)
3. Verifying each binary's interpreter and snapshot configuration.
4. Packaging a tarball with an `install.sh` that patches `flutter_tools` and
   installs the binaries into a stock Flutter SDK.

## Repository layout

```
.github/workflows/build.yml   CI: detect → build → verify → package → release
config/build.toml             build matrix + compatibility settings
config/gclient                gclient config (engine patches via custom_hooks)
config/package-termux.yaml    full .deb packaging (optional, from upstream repo)
patches/                      engine.patch, dart.patch, skia.patch (bionic/Termux)
scripts/
  sync.sh                     checkout Flutter + gclient sync + patch
  sysroot.py                  assemble Termux sysroot (from flutter-for-termux)
  build-one.sh                build one gen_snapshot variant
  verify-artifacts.sh         verify interpreter + config strings
  package-artifacts.sh        package tarball + checksums
  build-termux.py             monolithic build driver (reference)
```

## CI flow

| Job | What it does |
|---|---|
| `detect` | Resolves latest Flutter stable tag; skips if a release for that tag exists |
| `build-bionic` | Termux sysroot + NDK → bionic `gen_snapshot` (release + profile) |
| `build-glibc` | `--host-cpu=arm64` cross-compile → glibc `gen_snapshot` (release + profile) |
| `release` | Uploads both tarballs to a GitHub release for the Flutter tag |

Trigger with `workflow_dispatch` to build a specific tag or only one libc.

## When Flutter updates

CI checks for a new Flutter stable tag every Monday (`schedule`) and on pushes
to `main`. If no GitHub release exists for the newly resolved tag, it builds
both bionic and glibc artifacts and publishes them automatically. You can also
dispatch the workflow manually from the Actions tab if you don't want to wait.

On the device, after upgrading Flutter:

```bash
# If `flutter upgrade` complains about local changes, either:
flutter upgrade --force
# or revert our patch first:
git -C "$FLUTTER_HOME" checkout -- packages/flutter_tools/lib/src/artifacts.dart
flutter upgrade

# Then (re)install the matching artifacts:
curl -fsSL https://raw.githubusercontent.com/ani1nonly/flutter-arm64-artifacts/main/install.sh | bash

cd your-app
flutter clean
flutter build apk --release --target-platform android-arm64
```

The installer resolves the newest published release tag, compares it with the
installed SDK, and (with consent) updates Flutter first if needed. It then
auto-detects bionic vs glibc, verifies checksums, installs the binaries, and
re-applies the `artifacts.dart` patch. The patch is intentionally treated as a
regenerable local modification, so `--force` upgrades are safe.

If a new Flutter tag is installed before CI has published matching artifacts,
wait for the scheduled run or dispatch the workflow manually. Do not install
artifacts from an older Flutter tag — engine hashes must match.

If a build fails, the workflow uploads diagnostics as a job artifact; download
them from the failing run. Patch rebases (`engine.patch`, `dart.patch`,
`skia.patch`) are usually what a Flutter/engine change requires.

## Local usage

```bash
# 1. Install dependencies
sudo apt install -y git curl python3-pip ninja-build pkg-config
pip3 install -r requirements.txt

# 2. Set up depot_tools
git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git ~/depot_tools
export PATH="$HOME/depot_tools:$PATH"

# 3. Sync + patch
bash scripts/sync.sh 3.50.1

# 4. Build (bionic example)
python3 scripts/sysroot.py sync
bash scripts/build-one.sh bionic arm64 release
bash scripts/build-one.sh bionic arm64 profile

# 5. Verify + package
bash scripts/verify-artifacts.sh bionic
bash scripts/package-artifacts.sh bionic 3.50.1
```

The resulting `dist/bionic/flutter-gen_snapshot-bionic-3.50.1-aarch64.tar.gz`
can be copied to any device and installed:

```bash
tar -xzf flutter-gen_snapshot-bionic-3.50.1-aarch64.tar.gz
cd extracted
bash install.sh /path/to/flutter
cd your-app && flutter clean && flutter build apk --release --target-platform android-arm64
```

## Setup speed / "preconfigured VM"

GitHub-hosted runners are **fresh VMs on every run**, so a customized VM cannot
be kept between runs. Instead, this workflow caches the expensive setup:

| Cache | Key | What it saves |
|---|---|---|
| `~/.cache/pip` | `requirements.txt` hash | pip downloads |
| `~/depot_tools` | `depot-tools-v1` | depot_tools clone |
| `flutter-src` | Flutter tag + patch hash | **~5 GB engine checkout + 10–20 min `gclient sync`** |
| `sysroot` | `scripts/sysroot.py` hash | Termux sysroot assembly |

On a cache hit, `scripts/verify-sync.sh` confirms the checkout is complete and
still patched, then skips `gclient sync` entirely. Any patch edit changes the
cache key and forces a fresh sync automatically.

### Optional: container image (fully preconfigured)

`Dockerfile` bakes apt packages, Python deps, and depot_tools into an image.
Publish it once to GHCR, then add `container:` to both build jobs and delete
the "Install host dependencies" / "Set up depot_tools" steps:

```bash
docker build -t ghcr.io/ani1nonly/flutter-arm64-artifacts:latest .
echo "$GITHUB_TOKEN" | docker login ghcr.io -u ani1nonly --password-stdin
docker push ghcr.io/ani1nonly/flutter-arm64-artifacts:latest
```

```yaml
    container:
      image: ghcr.io/ani1nonly/flutter-arm64-artifacts:latest
```

Note: the container removes ~1 min of apt/pip setup, but `gclient sync` and the
engine compile (the real cost) are handled by the caches above. A **self-hosted
runner** is the only way to keep a truly warm machine.

## Known maintenance burden

- The 3 patches (`engine.patch`, `dart.patch`, `skia.patch`) are **hand-maintained
  diffs** against a specific engine commit. Every Flutter stable release needs a
  rebase. The weekly CI canary detects breakage but cannot auto-fix conflicts.
- The glibc cross-compile needs the `host_clang_cpu` GN arg from upstream PR
  #187591. If that PR is ever merged, the local patch can be dropped.
- This project is a **companion** to Flutter's official artifacts, not a
  replacement. It only covers the linux-arm64 host gap.

## Relation to upstream

- [flutter/flutter#75864](https://github.com/flutter/flutter/issues/75864) — Linux ARM64 host support (open since 2021)
- [flutter/flutter#187591](https://github.com/flutter/flutter/pull/187591) — upstream attempt, closed by maintainers ("no official tooling yet")
- [GeneralKaos666/flutter-for-termux](https://github.com/GeneralKaos666/flutter-for-termux) — source of the bionic patches and build approach
