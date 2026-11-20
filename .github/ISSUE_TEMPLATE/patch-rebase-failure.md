---
name: Patch rebase failure on new Flutter release
about: Report that the CI canary failed to apply patches to a new Flutter stable tag
title: 'Patch rebase: Flutter <tag>'
labels: patch-rebase, ci-failure
assignees: ''
---

## Summary

The weekly CI canary (`build.yml` → `detect` job) resolved a new Flutter stable
tag, but the patch set failed to apply / the build failed.

**Flutter tag:** <!-- e.g. 3.51.0 -->
**Engine hash (`bin/internal/engine.version`):** <!-- if available -->
**Failed job:** <!-- build-bionic / build-glibc / verify / detect -->
**CI run URL:** <!-- paste the Actions run link -->

## What happened

<!-- Paste the relevant CI log excerpt around the failure. Include the
     `git apply` error (patch hunk + line numbers) or the build error. -->

```text

```

## Patch status

| Patch | Applies? | Notes |
|---|---|---|
| `patches/engine.patch` | ? | |
| `patches/dart.patch` | ? | |
| `patches/skia.patch` | ? | |

## Likely cause

- [ ] Flutter engine DEPS roll changed a patched file
- [ ] `host_clang_cpu` GN arg (PR #187591) conflict with upstream changes
- [ ] Termux GN args renamed or removed
- [ ] Skia/Dart source refactor changed patch context
- [ ] Build target name changed (`gen_snapshot`, `clang_arm64/gen_snapshot`)
- [ ] Other (describe below)

## What's needed to fix

<!-- If you already know which hunk needs updating, describe it here. -->

## Environment (if reproduced locally)

- Host OS / arch:
- Python / depot_tools version:
- Command that failed:

## Checklist

- [ ] I included the exact Flutter tag
- [ ] I included the CI run URL or full error log
- [ ] I checked whether an issue for this tag already exists
