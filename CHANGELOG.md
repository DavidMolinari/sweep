# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-09-09

### Added

- Per-category cleaning state: the clean bar shows a cleaning indicator with a
  Cancel action, and selection, scan, and select-all controls are disabled while
  a clean is in progress.
- Partial-scan banner: locations that could not be read (for example under TCC)
  are listed above the results, with a Full Disk Access shortcut when a
  permission error is detected, instead of silently reporting a complete scan.
- Localized scan-failure labels and skipped-item counts in English, French,
  German, and Spanish.
- Tag-triggered release workflow that verifies the tag against
  `Support/Info.plist`, builds, self-tests, packages, checksums, and opens a
  draft GitHub release.
- `.github/CODEOWNERS`.

### Changed

- `make release` now runs the self-test (aborting on failure), lints the bundle
  and verifies its signature, ships `LICENSE` and `README.md` in the archive,
  reads the version from `Support/Info.plist` (single source), tries a universal
  build (arm64 + x86_64) with a native fallback, and re-verifies the SHA-256.
- The cleaning report distinguishes “moved to the Trash (recoverable)” from
  “permanently deleted”, showing the bytes for the mode that actually ran.
- The self-test covers a broad guardrail suite instead of four scenarios:
  symlinked roots, case-insensitive protected paths, custom large-file roots,
  protected bundles in the Trash, and select-all semantics.
- Release runbook completed: staple and validate the notarization ticket,
  re-zip after stapling, regenerate the checksum, and check Gatekeeper; no
  entitlements are required.
- Community files use GitHub private vulnerability reporting and the maintainer
  profile instead of placeholder email addresses; release and build docs
  describe the universal build and the actual self-test output.

### Fixed

- Cleaning runs off the main thread with per-category state, cancellation, and
  no concurrent clean of the same category.
- Scan failures are surfaced instead of showing “Nothing to clean”.
- Case-insensitive denylists, custom large-file root policy alignment, live
  protected-item handling, honest size accounting at clean time, and additive
  select-all semantics.

## [1.0.0] - 2026-09-08

First public release.

### Added

- Native SwiftUI app for macOS 14+ with a sidebar covering five cleaning
  categories: caches, logs, trash, developer caches, and large files.
- Real on-disk sizes measured with allocated blocks, not logical sizes.
- Developer cache scanning: Xcode DerivedData and DeviceSupport, CoreSimulator,
  Homebrew, CocoaPods, SwiftPM, pip, npm/yarn/pnpm, Gradle, Cargo, Go, and
  Hugging Face caches.
- Large file scan across Downloads, Desktop, Documents, Movies, Pictures, and
  Music, or a custom folder, with configurable size threshold, an "older than
  6 months" filter, and descending size sort.
- Safety model: every category except Trash moves items to the Trash with
  `FileManager.trashItem`; emptying the Trash is the only permanent action and
  is announced as irreversible.
- Anti-breakage protections: project subtrees (`Package.swift`, `.git`,
  `package.json`, `Cargo.toml`, `*.xcodeproj`, …) are never scanned, sensitive
  bundles (`.app`, `.framework`, photo libraries, VM disks, …) are never
  proposed, and the cleaner refuses protected locations, symlinks, and any item
  outside its scan root.
- Caution flags for archives, disk images, databases, running applications,
  debug symbols, and AI models; the corresponding items are unchecked by
  default.
- Localization in English, French, German, and Spanish, following the system
  language.
- Headless command line: `--scan [category …]` for scriptable reports and
  `--selftest` for the four guardrail tests.
- Ad-hoc signed app bundle built with Swift Package Manager, no third-party
  dependencies.
