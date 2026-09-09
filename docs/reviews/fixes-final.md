# Final Integration — UI Wiring, Release Engineering, OSS Readiness

Scope: `Sources/Sweep/Views/**`, `Sources/Sweep/Models/L10n.swift` (additions only),
`Support/Resources/*.lproj/Localizable.strings`, `Makefile`, `.github/**`, `docs/**`,
`README.md`, `README.fr.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
`CHANGELOG.md`. Services, `AppModel`, `ScanItem`, `Package.swift` and
`Support/Info.plist` (read-only) were not modified. No commit was made.

## 1. UI wired on the new core API

### Cleaning state (`Views/CategoryDetailView.swift`)

- `CleanBar` reads `model.isCleaning(category)`. While a clean runs, the Clean /
  Empty Trash button is replaced in place by a small `ProgressView`, the
  `cleanbar.cleaning` label and an `action.cancel` button wired to
  `model.cancelClean(category)` (tooltip `cleanbar.cleaning.help`).
- Select-all / select-safe, the flagged capsule, the flagged filter bar, the
  large-files controls and the item list are disabled during the clean; the
  item list is disabled so a row cannot be toggled mid-clean.
- The global Scan and Scan All toolbar buttons are disabled while
  `model.isAnyCleaning` (and while scanning, as before).

### Partial results (`Views/CategoryDetailView.swift`, `Views/StateViews.swift`)

- `.done` + `result.partialFailure` now renders `PartialScanBanner` above the
  list; the existing `.failed` + items path uses the same banner (dead path with
  the current core, kept for robustness).
- `PartialScanBanner` takes the structured `DiskScanner.ScanDiagnostics`:
  - up to two `path — reason` lines from `rootFailures`, with the reason
    localized via the new `scan.issue.*` keys (`unreadable` keeps the system
    error description);
  - a summary line for hidden roots (`scan.roots.*`) and skipped children
    (`scan.skipped.*`, `L10n.skippedRoots/skippedItems`);
  - the “Open Full Disk Access…” action only when a root failed with
    `.unreadable` (a permission error), not for symlink / missing /
    not-a-folder / policy refusals.
- The banner remains a discreet, non-blocking strip with Try Again.

### Cleaning report (`Views/Sheets.swift`)

- `CleanReportView` now headlines `report.movedToTrash` with
  `report.metric.trash` (“Moved to the Trash (recoverable)”) for recoverable
  cleans, and `report.freed` with `report.metric.permanent` (“Permanently
  deleted”) for the Trash category.

### Localization

- 12 new keys in all four `.lproj` files: `scan.issue.symlink`,
  `scan.issue.notDirectory`, `scan.issue.missing`, `scan.issue.notAllowed`,
  `scan.skipped.one/other`, `scan.roots.one/other`, `cleanbar.cleaning`,
  `cleanbar.cleaning.help`, `report.metric.permanent`, `report.metric.trash`.
- `L10n.skippedItems(_:)` and `L10n.skippedRoots(_:)` added.
- Parity checked: 162 keys per language, no duplicates, keys and format
  specifiers identical across EN/FR/DE/ES.

## 2. OSS finalization

- **Emails** — `SECURITY.md` now names GitHub private vulnerability reporting as
  the only channel (no email); `CODE_OF_CONDUCT.md` points enforcement at
  [@DavidMolinari](https://github.com/DavidMolinari) and the private reporting
  channel, and the maintainer placeholder note is gone. No invented address.
- **Makefile** — `VERSION` is read from `Support/Info.plist`
  (`CFBundleShortVersionString`, single source). `build` attempts a universal
  build (`--arch arm64 --arch x86_64`) and falls back to the native
  architecture. `app` picks the universal product when present and prints
  `lipo -info`. `release` runs `--selftest` (aborts on failure), `plutil -lint`,
  `codesign --verify --deep --strict`, stages `Sweep.app` + `LICENSE` +
  `README.md`, archives with `ditto -c -k --norsrc`, writes the SHA-256 and
  re-verifies it. `build`/`app`/`run`/`install`/`clean` keep working.
- **CI release** — new `.github/workflows/release.yml` on `v*` tags:
  tag↔Info.plist version guard, `make release`, CHANGELOG section extraction
  (fallback body), draft release via `softprops/action-gh-release@v2` with
  `GITHUB_TOKEN` only; `permissions: contents: write`, no cancel-in-progress.
- **Runbook** — `docs/RELEASING.md` rewritten: version single-sourcing, what
  `make release` now enforces, universal `lipo` check, full notarization
  sequence (Developer ID + `--options runtime --timestamp` sign → zip → submit →
  `stapler staple` → `stapler validate` → `spctl -a -vv` → **re-zip after
  staple** → regenerate checksum), and an explicit “no entitlements, no
  `disable-library-validation`” statement. `xattr -d com.apple.quarantine` is no
  longer recommended anywhere.
- **Governance/links** — `.github/CODEOWNERS` (`* @DavidMolinari`); the broken
  relative security link in `bug_report.yml` is now the absolute
  `https://github.com/DavidMolinari/sweep/security/policy`; README/CONTRIBUTING
  GitHub URLs verified consistent.
- **Docs coherence** — README/README.fr selftest sections now show the real
  twelve-check output (byte-identical to the binary), `make release` and the
  universal build are described, the `xattr` advice is removed, the PR template
  and issue form ask for the selftest output; `CHANGELOG.md` has an `Unreleased`
  section listing this wave.

## Verification

- `swift build -c release`: clean, 0 warnings.
- `make app`: universal `Sweep.app` (x86_64 + arm64), ad-hoc signed.
- `./dist/Sweep.app/Contents/MacOS/Sweep --selftest`: twelve checks, `0
  failures`, exit 0.
- `./dist/Sweep.app/Contents/MacOS/Sweep --scan caches logs`: exit 0.
- `plutil -lint` + `codesign --verify --deep --strict`: pass.
- `make -n release`: universal build → bundle → selftest → plist/signature →
  archive (`LICENSE`, `README.md`) → sha256 → checksum verification.
- Localization: 162 keys × 4, strict parity, matching format specifiers.
- Visual (window-only captures, own binary, instance killed afterwards):
  - partial-scan banner from a temporary symlinked developer-cache root
    (“lien symbolique refusé”, no FDA action) — fixture removed;
  - partial-scan banner from denied TCC roots on Large Files, showing
    “Ouvrir l’accès complet au disque…” plus the diagnostics summary — prompts
    answered “Ne pas autoriser”;
  - cleaning state during a temporary 20k-file fixture clean: spinner +
    “Nettoyage…” + Annuler, other actions dimmed;
  - report sheet: “20,97 Go · 1 élément supprimé — Déplacés vers la corbeille
    (récupérables)”. The fixture was removed from the Trash; no real data was
    cleaned.

## Remaining (out of this perimeter)

- Notarization credentials, private vulnerability reporting / Discussions
  enablement, issue labels, repository publication, and the `v*` tag are owner
  actions (the full `make release` was intentionally not executed locally; CI
  runs it on the tag).
- Actions are still pinned to major tags (`@v4`, `@v2`) to match `ci.yml`; SHA
  pinning plus Dependabot is a follow-up.
- `PartialScanBanner`’s `.failed` + items branch is currently unreachable with
  the core’s `readNothing → empty items` mapping; kept for future `.partial`
  states.
- `--scan` still exits 0 when roots are unreadable (diagnostics only), as
  documented by the core pass.
- Homebrew cask, x86_64 CI smoke job, and the filesystem-identity hardening
  noted in the core review remain future work.
