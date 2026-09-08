# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-13

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
