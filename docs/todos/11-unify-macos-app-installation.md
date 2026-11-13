# Unify macOS app installation

## Outcome

Share application discovery and Homebrew cask installation across Ghostty,
Herdr app, Raycast, and FlashSpace while preserving their individual validation
requirements and existing manual installations.

## Current evidence

`install.sh` uses `has_macos_app` and `install_macos_app` for Raycast and
FlashSpace. Ghostty and Herdr app have separate discovery functions and repeat
the cask installation and missing-application checks.

Their discovery requirements differ. Ghostty accepts `ghostty` on PATH or
`Ghostty.app/Contents/MacOS/ghostty`; Herdr accepts `herdr-app` on PATH or
`Herdr.app/Contents/MacOS/Herdr`. The shared helper currently assumes that the
bundle and executable names match. Ghostty and Herdr also validate minimum
versions before any configuration links change.

## Scope and boundaries

Unify the common discovery and installation behavior without changing package
ownership, compatibility minimums, application settings, or Linux behavior.
Keep JetBrains Mono's font detection separate. Preserve the self-contained
installer and its non-destructive contract.

## Open decision

Ghostty currently attempts a cask installation when its bundle exists without
an executable; the other three applications stop with a repair message.
Choose a consistent policy that preserves existing user content and reports
incomplete installations clearly.

## Acceptance criteria

- All four applications share common discovery and cask provisioning behavior,
  with support for their different bundle, executable, and CLI names.
- Existing PATH-first discovery for Ghostty and Herdr, configured application
  search directories, and paths containing spaces continue to work.
- Valid manual installations remain untouched; stale Homebrew receipts,
  incomplete bundles, failed installs, and missing post-install applications
  receive clear errors before configuration linking.
- Ghostty and Herdr retain their existing version checks before linking.
  Raycast and FlashSpace do not acquire unnecessary version checks or GUI
  launch requirements.
- Repeated installation remains a no-op, and Linux skips these applications.
- Tests cover these behaviors for all four applications.

## Verification

Run `./tests/install_test.sh`, `bash -n install.sh tests/install_test.sh`, and
`git diff --check`. Retain coverage of manual installations, compatibility
failures, damaged bundles, failed provisioning, and unchanged second runs.

## Starting points

- [`install.sh`](../../install.sh)
- [`tests/install_test.sh`](../../tests/install_test.sh)
- [`AGENTS.md`](../../AGENTS.md) — dependency ownership and Install Contract
- [`README.md`](../../README.md#dependency-ownership) — managed applications
