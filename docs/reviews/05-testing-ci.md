# 05 — Testing Strategy & CI

Scope: read-only review of the Sweep codebase (`/Users/david/Projects/sweep`) focused on
testability of `DiskScanner` / `Cleaner` / `AppModel`, the `--selftest` CLI, and the
GitHub Actions pipeline. No source file was modified; findings are based on static
reading only, nothing was built or executed against the repository.

Sweep is a destructive, open-source macOS disk cleaner whose entire value proposition
rests on a small set of documented safety invariants (`CONTRIBUTING.md:59-81`). Today
those invariants are defended by a single 4-scenario CLI self-test plus a single
macOS-15 CI job. This report maps the resulting blind spots and proposes a concrete,
dependency-free test plan.

---

## Current state

### What is tested

- **`--selftest`** (`Sources/Sweep/HeadlessMode.swift:5-63`) runs four in-process
  scenarios against fixtures created in the real `~/Library/Caches` and `~/.Trash`,
  using a random token in the fixture name, then cleans up and calls
  `exit(failures == 0 ? 0 : 1)`:
  - `move-to-trash` — clean a `~/Library/Caches` fixture under `.caches`, expect
    `trashItem` to remove it (asserts `removedIDs == 1`, no failures, file gone;
    `HeadlessMode.swift:26-31`).
  - `outside-root` — item whose root is a sibling directory must be refused with the
    `.outsideScan` reason (`HeadlessMode.swift:33-38`).
  - `trash-outside` — a `.trash` item whose path is not inside `~/.Trash` must be
    refused (`.outsideTrash`, `HeadlessMode.swift:40-44`).
  - `empty-trash` — a `~/.Trash` fixture under `.trash` must be permanently removed and
    report `permanent == true` (`HeadlessMode.swift:46-51`).
- **`--scan`** (`HeadlessMode.swift:65-114`) is documented as a manual smoke test
  (`CONTRIBUTING.md:53-57`): it exercises the whole scanner read path, prints a TSV
  summary plus 12 items with safety tags, and exits 0/1. CI never runs it, and its
  output is not asserted anywhere.
- **CI** (`.github/workflows/ci.yml`): one job `Build and self-test` on `macos-15`
  (`ci.yml:21`), 30-minute timeout, `contents: read`, cancel-in-progress concurrency.
  Steps: `swift --version` → `make build` → `make app` → `--selftest` → `make release`
  → `shasum -c` → upload `Sweep-*.zip` + `.sha256` as an artifact on **every** push and
  PR (`ci.yml:24-53`).
- **Safety invariants** are enforced by code inspection and code review only:
  `CONTRIBUTING.md:59-81` lists seven load-bearing invariants; contributors are asked to
  "add or extend a check in `HeadlessMode.runSelfTestIfRequested()`".

### What is not tested

- `Package.swift:9-14` declares a single `.executableTarget`; there is no test target,
  and `CONTRIBUTING.md:38` states it explicitly ("There is no XCTest target"). No file
  in the repository matches `Tests/`, `@Test`, or `XCTestCase`.
- `DiskScanner` classification logic is entirely uncovered: running-app matching
  (`runningTokens`/`isRunning`, `DiskScanner.swift:468-511`), protected/caution
  extension sets (`:96-108`, `:462-466`), project-folder detection (`:453-460`), the
  6-month cutoff (`:513-517`), default-selection semantics (`:235-265`), the
  large-files walk (`:372-451`), and `isAllowedLargeFileRoot` (`:351-362`).
- Four of the six `Cleaner.RefusalReason` cases have no automated test:
  `.symlink`, `.invalidPath`, `.protectedLocation`, `.unauthorizedRoot`
  (`Cleaner.swift:4-22`). The `.protected` item path (`Cleaner.swift:41-44`) is also
  untested.
- `AppModel` is completely uncovered: scan state machine (`AppModel.swift:143-188`),
  selection rules (`:204-231`), preference load/persist/reset (`:107-119`, `:293-300`),
  clean orchestration (`:239-263`).
- `ProgressReporter` throttling (`DiskScanner.swift:7-39`), localization parity
  (`Support/Resources/*.lproj`, 141 keys × 4 locales, currently identical), CLI
  category parsing (`HeadlessMode.swift:69-77`), and every UI affordance are uncovered.

### Coverage map against the documented invariants

| Invariant (`CONTRIBUTING.md:59-81`) | Covered by | Gap |
| --- | --- | --- |
| 1. Only `.trash` deletes permanently | `empty-trash` asserts `permanent == true` | `move-to-trash` never asserts `permanent == false`; a non-trash category made permanent would pass the self-test |
| 2. Deletion mode from `isPermanentDeletion`, not UI | Prose only | No test that `.trash` is the only permanent category |
| 3. Item must be strict descendant of its root | `outside-root` | No test for symlink-resolved escapes, root == home, non-home roots |
| 4. Symlinks never followed | None | Scanner and cleaner symlink paths untested |
| 5. Protected / sensitive paths refused | None | `.protectedLocation`, `.invalidPath` untested |
| 6. Large-file scan guards (markers, bundles) | None | Whole large-files path untested |
| 7. Caution unchecked, select-all = safe only | None | `ItemSafety` / `toggleSelectAll` untested |

---

## Findings

### [P0] There is no unit-test target, and the self-test cannot run inside one

Evidence: `Package.swift:9-14`; `CONTRIBUTING.md:38`; `HeadlessMode.runSelfTestIfRequested()`
calls `exit()` (`HeadlessMode.swift:62`) and is invoked from `SweepApp.init`
(`SweepApp.swift:10`). Everything of value lives in the executable target and is
private or `@MainActor`-bound.

Risk: no test can import and invoke the safety logic in isolation. CI can only test a
freshly assembled, ad-hoc signed `.app`, so `swift test` never exists and every new
guard requires another bespoke process-level scenario.

Recommendation: split `Sources/Sweep` into `SweepCore` (Models, Services, Headless
logic, no `@main`, no AppKit UI) and `Sweep` (SwiftUI entry point + Views), add a
`SweepCoreTests` test target, and extract the self-test into
`SelfTest.run(in environment:) -> SelfTestReport` returning data instead of calling
`exit()`. Keep `--selftest` as a thin CLI wrapper over that function.

### [P0] The "recoverable except trash" invariant is not asserted

Evidence: the `move-to-trash` scenario prints `removed`, `failures`, `gone` but never
inspects `trashReport.permanent` (`HeadlessMode.swift:28-31`), while `empty-trash`
asserts `permanent == true` (`:51`). If `SpaceCategory.isPermanentDeletion`
(`SpaceCategory.swift:52`) returned `true` for `.caches`, or if `Cleaner.clean`
swapped `trashItem` for `removeItem` (`Cleaner.swift:51-58`), the self-test would
still print a green run.

Risk: this is the single most important user-facing promise of the app (README
"everything recoverable except the explicit empty trash"); a regression silently
converts every clean into permanent deletion.

Recommendation: immediately add `permanent == false` to the `move-to-trash` assertion,
and add a parameterized unit test asserting `Cleaner.Report.permanent` for every
`SpaceCategory` (true only for `.trash`). Extend the test to assert that non-trash
categories call the trash-performing path (injectable performer), not `removeItem`.

### [P0] Four of six cleaner refusal paths and the protected-item path are untested

Evidence: `Cleaner.refusalReason` (`Cleaner.swift:104-134`) handles `.symlink`,
`.invalidPath`, `.protectedLocation`, `.outsideScan`, `.outsideTrash`,
`.unauthorizedRoot`; only the two "outside" cases have scenarios. `Cleaner.clean` also
refuses `item.safety.isProtected` before any path check (`Cleaner.swift:41-44`), which
is never exercised.

Risk: the guard order is load-bearing (e.g. symlink check must precede path checks,
`pathComponents.count >= 4` must fire before prefix checks). A refactor that reorders
or drops a branch can reopen a data-loss path with no failing test.

Recommendation: one test per `RefusalReason` (parameterized over a fixture table), plus
`cleanRefusesProtectedItem` with `isSelected == true`. Structure the tests so the
scenario name and expected reason are data, not code, so every enum case must have a
row.

### [P1] Scanner safety classification is untested, including running-app matching

Evidence: `runningTokens(from:)` builds tokens from bundle identifiers and localized
names with length thresholds (4 for whole normalized identifiers and first words,
6 for dotted components) and a `genericTokens` denylist
(`DiskScanner.swift:468-496`); `isRunning(_:tokens:)` then compares exact normalized
names, per-component for dotted names, and substring containment for plain names
(`:498-511`). None of this is testable today: both functions are `private`.
`scanChild` derives `isSelected` and `.caution(.appRunning)` from it
(`:246-263`).

Risk: a false negative marks a cache directory of a running app as `.safe` and
pre-selected, inviting the user to move live app data to the Trash. False positives
degrade the product but are recoverable; false negatives are not.

Recommendation: move matching into an internal `RunningAppMatcher` type with pure
static functions, keep the existing behavior as a golden contract, and test a fixture
table of (identifiers, cache name, expected result) covering exact IDs, dotted
components, localized names ("Google Chrome" → first word), the 4/6-char thresholds,
the generic denylist (`Helper`, `Updater`, `Cache`, …), the dotted-name early return,
and problematic negatives such as `com.foo.helper` vs `com.bar.helper`.

### [P1] `isAllowedLargeFileRoot` accepts `$HOME`, but `Cleaner` can never clean a `$HOME`-rooted item

Evidence: `isAllowedLargeFileRoot` (`DiskScanner.swift:351-362`) only rejects
`$HOME/Library`, `$HOME/.Trash` and system roots; the home directory itself is allowed.
`Cleaner.refusalReason` requires the resolved scan root to be a *strict* descendant of
home (`Cleaner.swift:128-131` + `isDescendant` at `:136-139`), so an item whose root is
`$HOME` always fails with `.unauthorizedRoot`. `AppModel.chooseLargeFilesFolder`
(`AppModel.swift:265-286`) opens an `NSOpenPanel` and accepts any root that passes
`isAllowedLargeFileRoot`, so the user can select their home folder, get a full scan,
select files, and then have every deletion refused.

Risk: silent no-op clean with confusing per-item failures; the anti-break model is
inconsistent between scanner and cleaner.

Recommendation: pick one contract and test both sides against it — either forbid
`$HOME` (and `$HOME`-equal symlinked paths) in `isAllowedLargeFileRoot`, or let
`Cleaner` accept `root == home` for non-trash categories. Add a table-driven test over
roots: `~/Downloads`, `~/Desktop`, `~`, `~/Library`, `~/.Trash`, `/System`, `/Library`,
`/Applications`, `/private/...`, `/usr`, `/etc`, `/var`, and a symlink resolving into
a forbidden root.

### [P1] CI only runs macOS 15 and does not pin the toolchain

Evidence: `runs-on: macos-15` (`ci.yml:21`) with a code comment suggesting `macos-14`
as a fallback; the deployment target is macOS 14 (`Package.swift:7`,
`LSMinimumSystemVersion 14.0` in `Support/Info.plist`); no `xcode-select` or
`setup-swift` step, so the Swift version silently follows runner image rollouts.

Risk: an API or dispatch difference that is fine on the current Xcode/macOS 15 image
can break the app on macOS 14, and nothing checks the 14 floor. Unpinned toolchains
also mean Swift Testing availability and diagnostics vary over time.

Recommendation: matrix `macos-14` + `macos-15`, pin Xcode explicitly (e.g.
`maxim-lobanov/setup-xcode` or `sudo xcode-select -s /Applications/Xcode_16.x.app`)
once Swift Testing is adopted. If Intel coverage is desired, add an Intel runner label
(e.g. `macos-15-intel`); otherwise document that release artifacts are arm64-only.

### [P1] Localization key drift is unguarded

Evidence: all four locales are currently in perfect sync — 141 keys each, identical key
sets and identical printf specifier signatures (verified by parsing
`Support/Resources/{en,fr,de,es}.lproj/Localizable.strings`) — but `CONTRIBUTING.md:92-94`
merely asks contributors to update "all four" files, and CI has no check. Keys with
positional interpolation such as `clean.failure.reason %@ %@` are easy to mistype
because the Swift call site reads `String(localized: "clean.failure.reason \(name) \(reason)")`
(`Cleaner.swift:68`), which maps to a `%@ %@` key at runtime.

Risk: a missing key silently renders the key itself in the UI for one language; a
specifier mismatch (`%lld` vs `%@`) can crash or garble counts.

Recommendation: add a `LocalizationTests` suite that parses the `.lproj` files from
`#filePath`-relative paths and asserts: identical key sets across en/fr/de/es, no empty
values, identical specifier signatures per key, `.one`/`.other` plural pairs present,
and a source inventory check (regex over `String(localized:` and `Text("…")`) against
the English table. Once `SweepCore` owns resources, also resolve a curated key list
through `Bundle.module` to catch mistyped runtime lookups.

### [P2] AppModel is untestable by construction

Evidence: `AppModel` reads `UserDefaults.standard` (`AppModel.swift:108-117`), calls
`NSWorkspace.shared.runningApplications` (`:156-157`), calls
`DiskScanner.scan` directly (`:160-170`), calls `Cleaner.clean` directly (`:245`),
sleeps 350 ms to sequence the report (`:253`), and reaches into `NSOpenPanel` /
`NSAlert` (`:266-286`). There is no seam for a fake scanner, fake cleaner, fake
running-apps set, fake clock, or an isolated `UserDefaults` suite.

Risk: the scan state machine and the selection rules (invariants 3 and 7) cannot be
tested or refactored safely; the 350 ms sleep makes any future test slow and flaky.

Recommendation: introduce narrow protocols/closures — `RunningAppsProviding`,
`ScanProviding`, `Cleaning`, `Clock` (for the report delay and the 6-month cutoff), a
`HomeProviding`, and an injected `UserDefaults` suite — then unit-test the state
machine, selection, persistence, and report planning without touching disk. Keep only
`NSOpenPanel`/`NSAlert` in a thin, untested UI shell.

### [P2] The self-test writes to the real home and is not sandboxable

Evidence: fixtures are created under `NSHomeDirectory()/Library/Caches` and
`~/.Trash` (`HeadlessMode.swift:10-24`), and the fixture cleanup enumerates the real
`~/.Trash` (`:56-60`). `Cleaner` refuses `/private/` and computes its forbidden paths
from the real `NSHomeDirectory()` (`Cleaner.swift:71-100`), so the standard
`FileManager.default.temporaryDirectory` (`/private/var/folders/...`) cannot host
success-path cleaner tests without tripping `.protectedLocation`.

Risk: any test harness reusing this pattern mutates the developer's real cache/Trash
state; a bug in cleanup leaves debris. It also prevents hermetic tests.

Recommendation: inject the home/root into `Cleaner` and `DiskScanner` (default
`NSHomeDirectory()` for production), add a `SWEEP_SELFTEST_ROOT`/`SWEEP_HOME` override
honored by the CLI, and build tests on a `TestSandbox` helper that creates a unique
directory, asserts every path it passes to `Cleaner` is prefixed by that directory, and
deletes it in a teardown/deinit. A defensive `precondition` in the helper that no test
path contains `/.Trash` or `/Library/` of the real home is cheap and worthwhile.

### [P2] CI hygiene: artifacts on every PR, no caching, no test reporting

Evidence: `make release` and `upload-artifact` run for every `pull_request` and
`workflow_dispatch` (`ci.yml:40-53`) with `if-no-files-found: error`; no
`actions/cache` for `.build`; no `swift test` step; no debug build; no Xcode result
bundle or test summary; no `retention-days`.

Risk: forked PRs publish unsigned zips as artifacts, CI time is spent packaging on
every commit, and there is no machine-readable record of what passed.

Recommendation: split jobs — `test` (matrix, `swift test`, debug and one release
config), `package` (only on `main` pushes/tags: `make app`, `--selftest`,
`make release`, checksum, upload with `retention-days`), optional `strict` job
(`-strict-concurrency=complete`, sanitizers) non-blocking. Cache `.build` keyed on
`Package.swift` plus source hash. Consider `swift test --enable-code-coverage` and
publish the summary only (no external service required).

### [P2] CLI parsing is untested and ambiguous for mixed unknown categories

Evidence: `--scan caches bogus` silently drops `bogus` via `compactMap`
(`HeadlessMode.swift:69-73`) and exits 0; only when *all* names are unknown does it
print the category list and exit 1 (`:74-77`). `--scan` hardcodes a 100 MB threshold
(`:89`) regardless of the user's stored preference.

Risk: scripts and docs may rely on behavior that can change unnoticed; a typo in a
category name is silently ignored in a mixed list.

Recommendation: decide and test the contract: reject any unknown token (exit 2 with a
message), keep the hardcoded headless threshold documented, and add tests for the
argument parser (no args = all cases, valid subset, unknown, empty string). Extract
parsing into a pure function to make this trivial.

### [P2] No UI or accessibility regression coverage

Evidence: destructive affordances live in SwiftUI views: pre-selection rules in
`ScanItem.isSelected` (`DiskScanner.swift:262`, `:340`, `:423`), select-all in
`AppModel.toggleSelectAll` (`AppModel.swift:212-231`), the confirmation sheet
(`Views/Sheets.swift`), and the clean button's disabled state
(`CategoryDetailView.swift:421-435`). `DESIGN.md:224` explicitly asks to test EN/FR/DE/ES
layouts, and `DESIGN.md:222-223` asks for Reduce Motion handling; neither is automated.

Risk: a UI change can pre-select caution items or enable Clean while scanning without
any test failing.

Recommendation: prefer logic extraction over view testing — pull the derived rules
(`canClean`, `selectAllTitle`, `isAllSelected`, filtered counts) into small testable
structs in `SweepCore` and unit-test them. Optional, effort L: `ImageRenderer`-based
snapshot tests for 3-4 canonical states (idle, scanning, done with caution, confirm
sheet × light/dark) with a tolerance-based PNG diff stored in test resources — no
third-party dependency needed, at the cost of some macOS-version flakiness. Full
XCUITest would require an Xcode project and is likely not worth it for this app size.

### [P2] `ProgressReporter` concurrency and throttling are untested

Evidence: `ProgressReporter` is `@unchecked Sendable`, guarded by `NSLock`, and
throttles at 0.1 s using `Date()` (`DiskScanner.swift:7-39`).

Risk: the `@unchecked Sendable` promise is only as good as the lock usage; the
throttle timing is nondeterministic and would make naive tests flaky.

Recommendation: inject a clock (or accept a `now: () -> Date`) and test: first `add`
flushes immediately, subsequent adds within 100 ms accumulate, `flush` emits the
pending total, and concurrent `add` calls from multiple tasks never lose bytes.

---

## Proposed test plan

All names below are proposed `@Test`/suite names in a new `SweepCoreTests` target
(Swift Testing). Fixtures are built by a `TestSandbox` helper (`makeDir`, `makeFile(bytes:)`,
`makeSymlink`, `backdate(_:to:)`) rooted in an injected home, never the real one.

### Cleaner and safety guards (highest priority)

| Test | Target | Verifies |
| --- | --- | --- |
| `cleanRefusesAllRefusalReasons` (parameterized) | `Cleaner` | One case per `RefusalReason`: symlink, invalid path (`/x/y`, <4 components), protected location (`home/Library`, `/Applications`, `/private/...`), outside scan, outside trash, unauthorized root; file intact, `failures == 1`, `removedIDs` empty for each |
| `cleanRefusesProtectedItemEvenWhenSelected` | `Cleaner` | `ItemSafety.protected` + `isSelected == true` → refusal, no filesystem call |
| `cleanMoveToTrashIsRecoverable` | `Cleaner` | `.caches`/`.logs`/`.developer`/`.largeFiles` → `permanent == false`, item routed to trash performer, `freed` equals size |
| `emptyTrashIsPermanentAndOnlyForTrash` (parameterized) | `Cleaner`, `SpaceCategory` | `report.permanent` true only for `.trash`; `removeItem` used only for `.trash` |
| `cleanReportsIOError` | `Cleaner` + fake performer | Throwing performer → failure line recorded, `removedIDs` empty, `freed == 0`, file intact |
| `cleanFreedCountsOnlySuccesses` | `Cleaner` | Mixed success/failure batch: `freed` sum of successes only |
| `cleanRefusesSymlinkToFileOutsideRoot` | `Cleaner` | Symlink item → `.symlink`, target untouched |
| `cleanerCancellationStopsBeforeNextItem` | `Cleaner` | Cancelled task stops between items (may use `withKnownIssue` if scheduling-dependent) |
| `cleanAcceptsCautionItems` | `Cleaner` | `ItemSafety.caution` is selectable and cleanable, unlike `.protected` |
| `permanentDeletionOnlyViaCategory` | `SpaceCategory` | Exactly `.trash` has `isPermanentDeletion == true` |

### DiskScanner

| Test | Target | Verifies |
| --- | --- | --- |
| `runningTokenParsingTable` (parameterized) | `RunningAppMatcher` | Bundle IDs (`com.apple.Safari` → `safari`), localized first words (`Google Chrome` → `google`), length thresholds (3-char components dropped, 5-char components dropped for dotted IDs), generic denylist (`Helper`, `Updater`, `Cache`, `Agent`…), dotted-name early return |
| `isRunningNegativeCases` | `RunningAppMatcher` | `com.foo.helper` is not "running" when only `com.bar.helper` runs — no generic-token false positives |
| `dottedNameComponentsMatch` | `RunningAppMatcher` | Cache dir `com.google.Chrome` matches localized-name token `google`; `com.apple.Safari` matches its own ID |
| `scanChildDefaultsForRunningApp` | `DiskScanner` | Running app → `.caution(.appRunning)` and `isSelected == false` even with `defaultSelected == true` |
| `largeFilesAreNeverDefaultSelected` | `DiskScanner` | `.largeFiles` scan returns `isSelected == false` regardless of safety |
| `protectedExtensionsAreExcludedFromLargeScan` | `DiskScanner` | `.app`, `.photoslibrary`, `.sparsebundle`, `.vmdk`… skipped; `.dmg`/`.zip`/`.sql` returned with `.caution(.archiveOrDatabase)` |
| `projectFoldersAreNotTraversed` (parameterized) | `DiskScanner` | A `5 GB` file inside a folder containing `.git`, `Package.swift`, `*.xcodeproj` is not reported; the same outside is |
| `skippedDirectoryNamesAreNotTraversed` | `DiskScanner` | `node_modules`, `DerivedData`, `.build`, `venv` subtrees ignored |
| `largeFileThresholdBoundary` (parameterized) | `DiskScanner` | File exactly at threshold included (`>=`), one byte under excluded; picker values 10/50/100/250/500 MB round-trip |
| `largeFileOldOnlyCutoff` | `DiskScanner` | With an injected cutoff date: modified-before included, after excluded, missing date included (`matchesCutoff`, `DiskScanner.swift:513-517`) |
| `allowedRootsTable` (parameterized) | `DiskScanner` | `~/Downloads` allowed; `~`, `~/Library`, `~/.Trash`, `/System`, `/Library`, `/Applications`, `/private/...`, `/usr`, `/etc`, `/var` denied; symlink resolving into a denied root denied (contract TBD per P1 finding) |
| `symlinksAreNeverFollowed` | `DiskScanner` | Symlinked directory and file fixtures produce no items and no size contribution |
| `scanSortsBySizeDescending` | `DiskScanner` | `items` sorted by size, `slots.compactMap` preserves no gaps |
| `directorySizeIgnoresPackagesAndSymlinks` | `DiskScanner.size(of:)` | Regular dir sums allocated bytes; symlink dir to non-dir returns 0; package counted as file |
| `progressReporterBuffersAndFlushes` | `ProgressReporter` | First add emits, adds within 100 ms buffer, `flush` emits remainder, totals preserved under concurrent adds (clock injected) |

### AppModel

| Test | Target | Verifies |
| --- | --- | --- |
| `initFallsBackToDefaultThreshold` | `AppModel` | Empty suite → threshold 100 MB, `oldOnly == false`, selection `.caches` |
| `thresholdPersistenceRoundTrip` (parameterized) | `AppModel` | All five picker values (10/50/100/250/500 MB) persist and reload from an injected suite |
| `invalidStoredThresholdFallsBack` | `AppModel` | Stored 0 or negative → 100 MB (matches `AppModel.swift:108-109`) |
| `defaultCategoryRestoredAndReset` | `AppModel` | Valid stored category restores; `resetPreferences` clears it and rescans large files if done |
| `scanStateMachine` | `AppModel` + fake scanner | idle → scanning (items cleared, `liveBytes == 0`) → done (items, root, date); progress accumulates |
| `cancelledScanReturnsToIdle` | `AppModel` + fake scanner | Cancellation clears items/root and state `.idle`, no stale results |
| `toggleSelectionRespectsProtected` | `AppModel` | Protected item cannot be toggled; caution can |
| `selectAllSelectsOnlySafe` | `AppModel` | Mixed safe/caution/protected: first call selects safe only and deselects caution/protected; second call deselects all selectable |
| `requestCleanUsesOnlySelectedItems` | `AppModel` | `PendingClean.items` equals selected subset, size sum correct |
| `performCleanRemovesOnlyRemovedIDs` | `AppModel` + fake cleaner | Result items pruned, report fields populated, `refreshFreeSpace` invoked (fake provider) |
| `rescanIfDoneOnlyWhenDoneOrFailed` | `AppModel` | idle/scanning ignored, done/failed rescanned |
| `freeSpaceRefreshUsesInjectedProvider` | `AppModel` | nil vs value paths render/behave as expected |
| `reportDelayIsInjectable` | `AppModel` | Fake clock removes the 350 ms sleep from tests |

### Localization

| Test | Target | Verifies |
| --- | --- | --- |
| `localesHaveIdenticalKeySets` | `*.lproj` parsed from repo | en/fr/de/es key-set equality (today: 141 × 4) |
| `noEmptyTranslations` | Same | No value is `""` or whitespace |
| `formatSpecifiersMatchAcrossLocales` | Same | Per-key specifier signature parity (`%@`, `%lld`) |
| `pluralPairsAreComplete` | Same | Every `*.one` key has a matching `*.other` in all locales |
| `sourceKeysExistInEnglishTable` | Regex inventory over `Sources/**/*.swift` | Every `String(localized: "…")` / `Text("…")` key (interpolation mapped to specifiers) exists in en.lproj; catches forgotten new keys |
| `curatedRuntimeLookupsResolve` | `Bundle.module` (after resource move) | Critical keys (`refusal.*`, `safety.*`, `confirm.*`, `cleanbar.*`) resolve to non-key strings in each locale |

### Headless CLI / self-test

| Test | Target | Verifies |
| --- | --- | --- |
| `selfTestIsAllGreen` | `SelfTest.run(in:)` | Refactored report: 4/4 checks pass inside a sandboxed home |
| `selfTestAssertsRecoverability` | `SelfTest.run(in:)` | `move-to-trash` asserts `permanent == false` and the item is recoverable from the sandboxed trash |
| `selfTestCoversEveryRefusalReason` | `SelfTest.run(in:)` | Report rows cover all six reasons (parity guard with the enum via `CaseIterable`) |
| `categoryArgumentParsing` (parameterized) | CLI parser | No args → all cases; subset preserved; unknown token rejected; empty arg rejected |
| `selfTestHonorsRootOverride` | CLI parser/env | `SWEEP_SELFTEST_ROOT` keeps every created path inside the override |

### UI (optional, effort L)

| Test | Target | Verifies |
| --- | --- | --- |
| `confirmSheetDiffersForPermanentCategory` | `ConfirmCleanView` via `ImageRenderer` | Trash shows destructive copy/icon/tint, caches shows recoverable copy |
| `cleanBarDisabledWithoutSelection` | extracted `CleanBarState` | Disabled when no selection or while scanning |
| `snapshotKeyStatesLightDark` | `SidebarView`/`CategoryDetailView` static states | No clipping in EN/FR/DE/ES (DESIGN.md:224) with pixel tolerance |

---

## Recommendations

### Infrastructure

1. **Restructure SPM (M).** `SweepCore` library target (Models, Services,
   `SelfTest` core, `RunningAppMatcher`, localization resources) + `Sweep`
   executable target (SwiftUI entry point and Views) + `SweepCoreTests`. Keep the
   package dependency-free. Alternatively `@testable import` of the executable target
   is technically possible with recent SwiftPM, but it drags `@main`, AppKit and the
   `exit()` path into the test process — the library split is worth the one-time
   cost and also enables coverage tooling.
2. **Extract `SelfTest` as a value-returning API (S/M).** `SelfTest.run(in:)` returns
   a list of `(name, passed, detail)` rows; `HeadlessMode` maps that to stdout and the
   exit code. This is what makes the four existing scenarios reusable from `swift test`
   and lets CI assert their output instead of printing it.
3. **Injection seams (M).** `HomeProviding`, `RunningAppsProviding`, `ScanProviding`,
   `Cleaning` (narrow trash/remove protocol), `Clock`, and a `UserDefaults` suite.
   Default implementations preserve current production behavior. This is a
   prerequisite for every AppModel test and for the cleaner I/O-error tests.
4. **TestSandbox + fixtures (S).** One helper that creates a unique directory tree,
   injects it as home/root into scanner/cleaner, asserts every path handed to
   destructive code is inside the sandbox, and tears down. Destructive-test protection
   is then structural: tests cannot reach `~/.Trash` or `~/Library/Caches` by accident.
5. **Swift Testing vs XCTest (S).** Use Swift Testing for all unit and parameterized
   tests (`@Test(arguments:)`, `#expect`, `withKnownIssue`) once CI pins Xcode 16+;
   keep `swift-tools-version` at 5.9+ or bump with the same commit that pins the
   toolchain. XCTest only if XCUITest is ever added, which is not recommended here.
6. **Coverage and lint (S).** `swift test --enable-code-coverage`; add a non-blocking
   `-strict-concurrency=complete` build and a TSan run of the scanner tests. No
   third-party linter required.

### CI

```yaml
strategy:
  matrix:
    include:
      - { os: macos-14, xcode: "16.2" }
      - { os: macos-15, xcode: "16.4" }
jobs:
  test:      # swift test (debug) + swift test -c release; cache .build; localization tests included
  package:   # main/tags only: make app && --selftest && make release && shasum -c
             # upload artifact with retention-days; run outside forks
```

- Add the matrix above and pin Xcode before `swift --version` so the toolchain is
  reproducible and Swift Testing is guaranteed.
- Cache `.build` keyed on `Package.swift` + source hash; keep the 30-minute timeout.
- Run `--selftest` on the test job (fast, no packaging) and keep the packaged-bundle
  run on `package` only.
- Restrict artifact uploads and `make release` to `main` pushes/tags/workflow_dispatch.
- If Intel slices matter, either build `--arch arm64 --arch x86_64` in `package` or
  document arm64-only artifacts.

### Documentation to update with the change

- `CONTRIBUTING.md:36-51` — replace "There is no XCTest target" with `swift test`
  instructions and the sandbox rule for destructive tests; extend "add a check in
  `HeadlessMode`" to point at `SelfTest` and the test target.
- `.github/PULL_REQUEST_TEMPLATE.md` — the "selftest 4/4" statement should also
  require a green `swift test`.
- `README.md`/`README.fr.md` and `docs/RELEASING.md:57` — mention the test suite and
  the sandboxed self-test override.

### Effort summary

| Item | Effort |
| --- | --- |
| Library + executable split, `SelfTest` extraction | M |
| Injection seams (home, apps, scan, clean, clock, defaults) | M |
| TestSandbox + fixtures | S |
| Cleaner/guard unit tests (P0 findings) | S/M |
| RunningAppMatcher extraction + scanner tests | M |
| AppModel tests | M |
| Localization tests | S |
| CI matrix, caching, job split, Xcode pin | M |
| Snapshot tests (optional) | L |
| Strict concurrency / sanitizers (optional) | S |

---

## References

Files read for this review (no modifications made):

- `Package.swift` — single executable target, macOS 14 minimum, tools 5.9.
- `Sources/Sweep/HeadlessMode.swift` — `--selftest` (4 scenarios, real-home fixtures,
  `exit()`), `--scan` (hardcoded 100 MB threshold, category parsing).
- `.github/workflows/ci.yml` — single `macos-15` job, package + upload on every event.
- `Sources/Sweep/Services/Cleaner.swift` — refusal reasons and ordering, forbidden
  paths/prefixes, permanent-vs-trash routing, strict-descendant root rule.
- `Sources/Sweep/Services/DiskScanner.swift` — scan orchestration, selection defaults,
  running-app token matcher, extension safety sets, project markers, cutoff, allowed
  roots, `ProgressReporter`.
- `Sources/Sweep/Models/AppModel.swift` — scan state machine, selection rules,
  preferences, clean orchestration, singletons.
- `Sources/Sweep/Models/ScanItem.swift` — `ItemSafety`, `CautionReason`, `ScanItem.==`.
- `Sources/Sweep/Models/SpaceCategory.swift` — `isPermanentDeletion`.
- `Sources/Sweep/Models/L10n.swift` — plural/key helpers.
- `Sources/Sweep/SweepApp.swift` — self-test invoked from `App.init`.
- `Sources/Sweep/Views/ContentView.swift`, `CategoryDetailView.swift`, `Sheets.swift`,
  `SettingsView.swift`, `LargeFilesControls.swift` — destructive affordances, threshold
  pickers, confirm/report sheets.
- `Support/Resources/{en,fr,de,es}.lproj/Localizable.strings` — 141 keys per locale,
  verified in sync with matching format specifiers.
- `Support/Info.plist` — `LSMinimumSystemVersion 14.0`, `CFBundleLocalizations`.
- `Makefile` — build/app/selftest/release pipeline used by CI.
- `CONTRIBUTING.md` — no test target, safety invariants, localization rule.
- `README.md`, `README.fr.md` — documented self-test output and CLI behavior.
- `DESIGN.md` — localization and Reduce Motion expectations.
- `docs/RELEASING.md` — release checklist relying on `--selftest`.
