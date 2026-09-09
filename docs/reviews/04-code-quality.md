# 04 — Code Quality & Idiomatic Swift

**Context** — Sweep 1.0.0 is a dependency-free SwiftUI/AppKit disk cleaner for macOS 14+, built with SPM (~2,900 lines across 18 files in `Sources/Sweep`, plus a 458-line icon-generation script). This read-only review audits naming, API design, dead code, duplication, function complexity, error handling, numeric typing and tooling; no build or lint tool was run. No P0 (data-loss or safety-hole) defect was found, but several P1s affect accuracy, responsiveness and pre-open-source hygiene.

## Findings

### [P1] `Cleaner.clean` executes on the main actor, freezing the UI
`AppModel` is `@MainActor`, so the `Task { ... }` in `performClean` inherits MainActor isolation and the entire synchronous deletion loop runs on the main thread — AppModel.swift:239-263, Cleaner.swift:31-65.

Why it matters: cleaning thousands of files performs blocking file-system calls while the run loop is blocked; the progress UI cannot redraw and the app appears hung for seconds.

Proposed fix — hop off the main actor and make the payload `Sendable`:

```swift
func performClean(_ pending: PendingClean) {
    confirmation = nil
    let items = pending.items
    let category = pending.category
    Task {
        let outcome = await Task.detached(priority: .userInitiated) {
            Cleaner.clean(items: items, category: category)
        }.value
        // … update results / report on the main actor
    }
}
```

(`ScanItem`, `SpaceCategory` and `Cleaner.Report` are value types; declare them `Sendable` explicitly.)

### [P1] Scan errors are silently swallowed and `.failed` is unreachable
`DiskScanner.scanChildren` converts a failed directory read into an empty result: `(try? fm.contentsOfDirectory(...)) ?? []` (DiskScanner.swift:200-204), same in `walkLargeFiles` (395-399). `AppModel.scan` only ever assigns `.done` or `.idle` (AppModel.swift:172-183), so `ScanState.failed` (AppModel.swift:9), `FailureView` (StateViews.swift:71-97) and the `failure.title` string are dead code.

Why it matters: without Full Disk Access, unreadable roots such as `~/Library/Caches` render “Nothing to clean” (StateViews.swift:17-24) instead of an error — a trust-breaking false negative for a disk cleaner.

Proposed fix — fail on the root, tolerate per-child errors:

```swift
enum ScanError: LocalizedError { case unreadableRoot(URL, underlying: Error) }
static func scan(...) async throws -> ScanResult
// scanChildren: guard let children = try? … else { throw ScanError.unreadableRoot(root, underlying: error) }
```

Then map the thrown error to `result.state = .failed(error.localizedDescription)` in `AppModel.scan`.

### [P1] Scan policy and deletion policy disagree
`DiskScanner.isAllowedLargeFileRoot` (DiskScanner.swift:351-362) accepts any folder outside a short forbidden list, so the picker validation (AppModel.swift:274) allows `/Volumes/Extern` or `/Users/other`. `Cleaner.refusalReason` then refuses every item whose resolved root is not a descendant of the current user's home (`.unauthorizedRoot`, Cleaner.swift:127-131). The user can scan and select items that can never be cleaned.

The same forbidden-location knowledge is also duplicated between `DiskScanner.isAllowedLargeFileRoot` and `Cleaner.forbiddenPaths`/`forbiddenPrefixes` (Cleaner.swift:71-100) — exactly the kind of safety list that drifts.

Proposed fix — one shared policy used by scanner, picker and cleaner:

```swift
enum PathPolicy {
    static func isAllowedScanRoot(_ url: URL) -> Bool
    static func refusalReason(for url: URL, root: URL, category: SpaceCategory) -> Cleaner.RefusalReason?
}
```

and delete the scanner-local copy.

### [P1] The “freed” figure is not freed space
`Cleaner.Report.freed += item.size` (Cleaner.swift:59) is the sum of scanned allocated sizes, not a measurement. Except for Trash, files are moved to `~/.Trash` on the same volume: zero bytes are reclaimed until the user empties the Trash, yet `CleanReportView` presents that number as the headline result next to “Cleaning complete” (Sheets.swift:78-83, AppModel.swift:254-260).

Proposed fix (pick one):
- measure `URLResourceValues.volumeAvailableCapacityForImportantUsage` before/after and report the delta only for permanent deletions;
- or split the metric by mode (`movedToTrash: Int64` vs `freed: Int64`) and adjust the strings accordingly.

### [P1] `filter.title` is missing from all four localizations
`Picker("filter.title", …)` (CategoryDetailView.swift:92) has no matching key in any `.lproj`. The 141 keys per language are otherwise perfectly in sync (verified EN/FR/DE/ES, `Localizable.strings` and `InfoPlist.strings`). The label is hidden (`.labelsHidden()`, line 97), so the only impact is the accessibility name, but this is the single gap in an otherwise clean localization set.

Fix — add to the four files (per CONTRIBUTING.md:92-94): `"filter.title" = "Show";` / `"Afficher"` / `"Anzeigen"` / `"Mostrar"`.

### [P2] Dead code inventory (remove or wire up)
- `ItemSafety.protected(String)` is never constructed — `DiskScanner` only emits `.safe`/`.caution`; the lock affordances (CategoryDetailView.swift:317-321, 329-338), `isProtected`, the `safety.protected.*` strings and `refusal.protectedItem` are unreachable.
- `ScanItem.isDirectory` (ScanItem.swift:64) is written but never read.
- `CategoryResult.scannedAt` (AppModel.swift:17, set at 180) is never read.
- Unused design tokens: `SpaceCategory.tint` (SpaceCategory.swift:42-50), `CategoryStyle.brand`/`.danger` (DesignSystem.swift:44, 50), `BrandPalette.Semantic.brand`/`.danger` (BrandPalette.swift:89-107), `Radius.inset`/`.chip`/`.field` (BrandPalette.swift:112-114).
- `CategoryDetailView.itemCountLabel` (196-198) is a pass-through wrapper around `L10n.itemCount`.

Why it matters: for an imminent open-source release, unreachable safety UI is worse than no UI — contributors will assume `.protected` is a live path. Either emit `.protected` for the bundles the scanner currently skips silently, or delete the case, the badge and the strings.

### [P2] Duplicated sliding-window task-group pattern (~25 lines, twice)
`scanChildren` (DiskScanner.swift:209-230) and `scanDeveloperCaches` (298-319) implement the same bounded-concurrency map plus `slots` array.

Proposed fix:

```swift
private static func concurrentMap<T, R: Sendable>(
    _ inputs: [T],
    width: Int = maxConcurrentScans,
    _ transform: @Sendable @escaping (T) -> R
) async -> [R?]
```

### [P2] `walkLargeFiles` is too long and mixes concerns
DiskScanner.swift:385-451 is 67 lines with four nesting levels, mixing traversal, package handling, threshold filtering, cutoff logic, `ScanItem` construction and progress reporting, with magic values `4_000_000` (line 392), `-6` months (line 375) and `prefix(500)` (line 382).

Proposed fix: extract `handlePackage(_:state:reporter:)`, `handleFile(_:state:reporter:)`, `shouldSkipDirectory(named:)` and hoist constants into `ScanDefaults`; consider a `LargeFileWalker` struct to hold `state` instead of `inout` plumbing.

### [P2] Thresholds and picker options are duplicated magic numbers
`100 * 1024 * 1024` appears in AppModel.swift:109, AppModel.swift:294 and HeadlessMode.swift:89; the five-value option list is copied in LargeFilesControls.swift:8-14 and SettingsView.swift:103-109.

Proposed fix:

```swift
enum ScanDefaults {
    static let largeFileThreshold: Int64 = 100 * 1024 * 1024
    static let largeFileThresholdOptions: [Int64] = [10, 50, 100, 250, 500].map { Int64($0) * 1024 * 1024 }
    static let oldFileMonths = 6
    static let maxLargeFileResults = 500
    static let progressFlushInterval: TimeInterval = 0.1
}
```

### [P2] Deprecated `Task.sleep(nanoseconds:)`
AppModel.swift:253 (`350_000_000`) and AboutView.swift:109 (`1_600_000_000`) use the API deprecated since macOS 13. Use `try? await Task.sleep(for: .milliseconds(350))` and `try? await Task.sleep(for: .seconds(1.6))`.

### [P2] Force unwraps and silent `try?` in safety-relevant spots
- `AppInfo.githubURL = URL(string: "https://…")!` (AboutView.swift:23) — build it with an explicit fallback or a non-optional helper.
- `generate-icon.swift` force-unwraps `CGColorSpace`/`CGGradient`/`CGContext`/`makeImage` (lines 23, 61, 375, 381); script code, but throwing instead removes four crash sites cheaply.
- `Cleaner.refusalReason` treats a failed `resourceValues` as “not a symlink” (Cleaner.swift:107). This is a safety gate: prefer `guard let … else { return .invalidPath }`.
- `matchesCutoff` returns `true` when the modification date is unknown (DiskScanner.swift:513-517), so unknown-age files pass the “older than 6 months” filter. Decide and document (the safe default is to exclude).
- `size(of:)` (DiskScanner.swift:162-171) enumerates *through* directory symlinks (`fileExists` follows the link, then `directorySize`), while every other code path skips symlinks — this contradicts safety invariant #4 (CONTRIBUTING.md:70). Return `0` for any symlink.

### [P2] Surprising `Equatable` on `ScanItem`
`==` compares only `id` and `isSelected` (ScanItem.swift:84-86), and no call site appears to need value equality (SwiftUI diffing uses `id`). Either drop the conformance or make the semantics explicit (`hasSameSelection(as:)` / comment), otherwise a future `contains`/`removeAll` will silently use partial equality.

### [P2] Display concerns leak into model APIs
- `DiskScanner.scan` returns `(items: [ScanItem], root: String)` where `root` is sometimes a localized label, sometimes a filesystem path (DiskScanner.swift:117, 129/138/148/152/157), consumed directly by `CategoryHeader` (CategoryDetailView.swift:140). Prefer `struct ScanResult { let items: [ScanItem]; let source: ScanSource }` and localize at the view layer.
- A persisted custom root is not re-validated at launch (AppModel.swift:111-113); if it later becomes forbidden, the label falls back to `""` (DiskScanner.swift:157).
- `SpaceCategory` imports SwiftUI only for `symbol`/`tint` (SpaceCategory.swift:1, 32-50); move presentation into `DesignSystem.swift` and keep the model framework-light.

### [P2] Two stacked sheets plus a 350 ms sleep race
`ContentView` declares `.sheet(item:)` twice (lines 23-29) and `performClean` sleeps 350 ms (AppModel.swift:253) so the confirmation sheet can dismiss before the report appears. Replace with a single presentation route:

```swift
enum ActiveSheet: Identifiable { case confirm(PendingClean), report(CleanReport) /* … */ }
@Published var activeSheet: ActiveSheet?
```

and delete the sleep.

### [P2] Naming and storage-key inconsistencies
- `runningBundleIDs` actually receives bundle identifiers *and* localized names (AppModel.swift:157, DiskScanner.swift:115); rename to `runningAppTokens` or split, since `DiskScanner.runningTokens(from:)` already treats them as tokens.
- UserDefaults keys are split between a private `Keys` enum and the public `AppModel.defaultCategoryKey` (AppModel.swift:95-101), while `SettingsView` repeats `SpaceCategory.caches.rawValue` twice (SettingsView.swift:32, 75). Centralize in one `DefaultsKey` namespace plus `static let defaultCategory`.
- `HeadlessMode.runSelfTestIfRequested()` vs `runIfRequested()` (HeadlessMode.swift:5, 65) — make the latter `runScanIfRequested()`.
- Unknown `--scan` names are silently dropped (`compactMap`, HeadlessMode.swift:72); print an error and exit non-zero, as already done for the empty case.

### [P2] No formatter/linter; a handful of long lines
No `.swift-format`/SwiftLint config and no lint step in CI (`.github/workflows/ci.yml` builds and self-tests only). The style is already very consistent, so adoption is mechanical. Lines >140 chars: SidebarView.swift:39 (184), DiskScanner.swift:166 (157), CategoryDetailView.swift:408 (150), StateViews.swift:56 (142), AppModel.swift:289 (142), HeadlessMode.swift:27/34/47/50 (163/171/162/170), plus the intentional MIT blob (AboutView.swift:156, 160).

Quick win:

```json
// .swift-format
{ "version": 1, "lineLength": 140, "indentation": { "spaces": 4 } }
```

CI: `xcrun swift-format lint --strict --recursive Sources` (toolchain-provided, so it does not violate the “no third-party dependency” rule of CONTRIBUTING.md:85-87).

### [P2] Stated design rules not enforced in code
- DESIGN.md:159 “Never set text below `.caption`” — caution text uses `.caption2` (CategoryDetailView.swift:249).
- DESIGN.md:174-175 destructive affordances should use `danger`/`warning` tokens — `ConfirmCleanView` builds `.warning` for permanent deletion (Sheets.swift:13-14) and literal `.red` (29, 34, 55); `CleanBar` tints `.red` (431); `CategoryStyle.danger` exists and is unused.
- DESIGN.md:222 says `SpinningRing` should honor Reduce Motion (DesignSystem.swift:115-135) — `accessibilityReduceMotion` is not read anywhere.
- `Cleaner.forbiddenPaths` hard-codes `~/Projects` (Cleaner.swift:75), a personal-layout path that does not belong in a public app; generalize or drop it.

### [P2] App-target organisation vs CONTRIBUTING “one concern per file”
- `AppModel` is a 301-line god object mixing scan orchestration, cleaning, preference persistence, `NSOpenPanel` and System Settings URLs. Split into `PreferencesStore`, `ScanCoordinator`, `CleanCoordinator` (extensions in separate files at minimum).
- `AboutView.swift` holds `AppInfo`, `AboutMenuButton`, `AboutView` and `MITLicenseSheet`, with the MIT text embedded in code (151-161) duplicating `LICENSE`.
- `SettingsView.swift` hosts four private panes (237 lines); one file per pane matches the stated layout rule.
- `HeadlessMode` ships in the app target and its self-test writes fixtures into the real `~/Library/Caches` and `~/.Trash` (HeadlessMode.swift:11-12, 53-60). A separate `sweep-cli` executable target would isolate CLI/selftest code from the UI binary.

### [P2] Developer builds lose localization resources
`Package.swift` (10-13) declares no `resources`, and `Makefile:17` copies `Support/Resources/*.lproj` into the bundle manually. `swift run` / VS Code debug builds therefore render raw keys (`category.caches.title`) instead of localized text. Either move the `.lproj` folders under `Sources/Sweep/Resources` and declare `.process(...)`, or document `make run` as the only supported dev loop.

## Recommendations

Prioritised; effort S/M/L.

1. **S** — Add `.swift-format` (line length 140) and a strict lint step to CI; run one formatting pass over `Sources` (the diff will be small).
2. **S** — Introduce `ScanDefaults` and replace the duplicated thresholds/options in AppModel, LargeFilesControls, SettingsView and HeadlessMode.
3. **S** — Add the missing `filter.title` key to all four `.lproj` files.
4. **S** — Mechanical cleanup: replace deprecated `Task.sleep(nanoseconds:)`, remove the `URL(string:)!`, drop the `itemCountLabel` wrapper, delete unused members (`tint`, `CategoryStyle.brand`/`.danger`, `Semantic.brand`/`.danger`, `Radius.inset`/`.chip`/`.field`, `isDirectory`, `scannedAt`).
5. **S** — Rename ambiguous APIs: `runningBundleIDs` → `runningAppTokens`, `oldOnly` → `onlyOldFiles`/`modifiedBefore`, `runIfRequested` → `runScanIfRequested`; merge UserDefaults keys into one namespace.
6. **M** — Extract the `concurrentMap` helper shared by `scanChildren`/`scanDeveloperCaches`, and decompose `walkLargeFiles` into small handlers.
7. **M** — Unify safety policy into `PathPolicy` (scan roots, forbidden locations, deletion refusals) and re-validate the persisted custom root at launch.
8. **M** — Add error propagation to the scan pipeline (`throws` + `.failed` UI); keep per-item `try?` only after a successful directory read.
9. **M** — Move `Cleaner.clean` off the main actor and report real reclaimed space (or rename the metric per mode).
10. **M** — Add a `SweepTests` XCTest target for pure logic (`Cleaner.refusalReason`, selection rules, `L10n` plurals, `ScanDefaults`), keeping `--selftest` for integration coverage.
11. **L** — Split `AppModel` into stores/coordinators, isolate CLI/selftest in a second executable target, and enable strict concurrency (then Swift 6 language mode) to catch the actor-boundary and `@unchecked Sendable` issues early.
12. **L** — Decide `.protected` semantics before release: either emit it from the scanner for protected bundles, or delete the state, badge and strings.

Mechanical quick wins (no design decision required): `xcrun swift-format format --in-place --recursive Sources`; Ctrl-F for `Task.sleep(nanoseconds:`; add `.swift-format`; add `filter.title`; wrap the >140-char lines; delete pass-through wrappers; centralise the two threshold pickers into a `ForEach(ScanDefaults.largeFileThresholdOptions)`.

## References

Files read for this review:

- `Package.swift`
- `Sources/Sweep/SweepApp.swift`
- `Sources/Sweep/HeadlessMode.swift`
- `Sources/Sweep/Models/AppModel.swift`, `ScanItem.swift`, `SpaceCategory.swift`, `L10n.swift`
- `Sources/Sweep/Services/DiskScanner.swift`, `Cleaner.swift`
- `Sources/Sweep/Views/ContentView.swift`, `SidebarView.swift`, `CategoryDetailView.swift`, `LargeFilesControls.swift`, `StateViews.swift`, `Sheets.swift`, `SettingsView.swift`, `AboutView.swift`, `DesignSystem.swift`, `BrandPalette.swift`
- `Support/Branding/generate-icon.swift`
- `Support/Info.plist`, `Support/Resources/{en,fr,de,es}.lproj/{Localizable,InfoPlist}.strings`
- `Makefile`, `.github/workflows/ci.yml`
- `CONTRIBUTING.md`, `DESIGN.md`, `CHANGELOG.md`, `LICENSE`
