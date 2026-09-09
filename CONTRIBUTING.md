# Contributing to Sweep

Thanks for taking the time to contribute. Sweep is a small, dependency-free
macOS app; keeping it that way is part of the design.

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 15 or later (Swift 5.9 toolchain, `swift` on `PATH`)

No package manager, no third-party dependency, no code generation step.

## Setup

```sh
git clone https://github.com/DavidMolinari/sweep.git
cd sweep
make run
```

`make run` builds the release binary, assembles `dist/Sweep.app`, signs it
ad-hoc, and opens it.

## Useful commands

| Command | Effect |
| --- | --- |
| `make build` | `swift build -c release` |
| `make app` | Assemble and ad-hoc sign `dist/Sweep.app` |
| `make run` | `make app` then open the bundle |
| `make install` | Copy the bundle to `/Applications` |
| `make release` | Build a zip of the app plus a SHA-256 checksum in `dist/` |
| `make clean` | Remove build products and `dist/` |
| `swift build` | Fast debug build |

## Tests

There is no XCTest target. The safety guards are covered by the app's
self-test, which runs against temporary fixtures in `~/Library/Caches` and
`~/.Trash` and cleans up after itself:

```sh
make app
./dist/Sweep.app/Contents/MacOS/Sweep --selftest
```

All twelve checks must pass before a pull request is merged; the final line of
the output reports `0 failures`:

```
move-to-trash  outside-root  trash-outside  empty-trash  symlink-root
trash-resolved  large-roots  case-fold  trash-app-protected
select-all-preserve  select-all-clear
```

`case-fold` is skipped (and does not count as a failure) on a case-sensitive
volume.

For a manual smoke test of the scan pipeline:

```sh
./dist/Sweep.app/Contents/MacOS/Sweep --scan caches logs
```

## Safety invariants

These are load-bearing; pull requests that weaken them will not be merged.

1. Every category except `trash` moves items to the Trash with
   `FileManager.trashItem`; only the `trash` category may delete permanently,
   and only inside `~/.Trash`.
2. The deletion mode is decided in code by `SpaceCategory.isPermanentDeletion`,
   never by the UI.
3. A `ScanItem` may only be cleaned if it is a strict descendant of its scan
   root, after resolving symlinks.
4. Symlinks are never followed, for scanning or cleaning.
5. Protected locations (`/`, `~/Library`, `~/Documents`, `/Applications`, …)
   and sensitive subtrees (`Containers`, `Mail`, `Safari`, `Keychains`, …) are
   always refused.
6. Large-file scans never descend into project subtrees (marker detection) and
   never propose sensitive bundles (`.app`, `.framework`, photo libraries, VM
   disks, backups, …).
7. Items flagged `caution` stay unchecked by default; "select all" only selects
   items flagged `safe`.

Add or extend a check in `HeadlessMode.runSelfTestIfRequested()` when you touch
these paths.

## Style

- Swift 5.9, SwiftUI + AppKit, Apple frameworks only. Adding a third-party
  dependency requires a prior discussion in an issue and an entry in
  `THIRD_PARTY_LICENSES.md`.
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
  Match the existing file layout and naming: one concern per file, `enum`
  namespaces for stateless helpers.
- No comments unless they explain a non-obvious safety decision.
- UI strings go through `String(localized:)` and `Support/Resources/*.lproj`.
  Adding or changing a key means updating **all four** `.lproj` files
  (English, French, German, Spanish). The English file is the base.
- Keep the app free of networking, telemetry, analytics, and update checks.

## Commits

Short imperative subject, optionally scoped, in the spirit of Conventional
Commits:

```
fix(cleaner): refuse items whose resolved path leaves the scan root
feat(scanner): add Bun cache to developer caches
docs: document the release process
```

One logical change per commit. Do not mix formatting or refactors with behavior
changes.

## Pull requests

1. Open an issue first for anything larger than a bug fix or a new cache path.
2. Keep the diff focused; describe what changes and why, not how.
3. Fill in the pull request template. State that `--selftest` reports
   `0 failures`.
4. Update `README.md`, `README.fr.md`, and `CHANGELOG.md` when behavior or
   commands change.
5. UI changes need a screenshot of the app window (light or dark) showing the
   result.

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE), and you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Release process

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md).
