# Core Safety & Robustness Fixes (P0/P1)

Scope: `Cleaner.swift`, `DiskScanner.swift`, `ScanItem.swift`, `AppModel.swift`,
`HeadlessMode.swift`. No view, support file, package manifest or existing review was
modified. All changes are additive or tightening; no existing refusal was relaxed.

Verification: `swift build -c release` (0 warnings), `make app`,
`./dist/Sweep.app/Contents/MacOS/Sweep --selftest` (12/12),
`./dist/Sweep.app/Contents/MacOS/Sweep --scan caches logs developer largeFiles`.

## P0 fixes

### 1. Symlinked scan roots refused; Trash double verification (review 06)

- `DiskScanner.rootValidationFailure(for:missingIsError:)` — DiskScanner.swift:217.
  `lstat`-based (`resourceValues` on the URL itself) probe returning `symlink`,
  `notDirectory`, `missing`, `notAllowed` or `unreadable`. Called before every root is
  walked: `scanChildren` (DiskScanner.swift:263), developer entries
  (DiskScanner.swift:406), large-file candidates (DiskScanner.swift:203).
  A symlinked root is never followed; it produces a `ScanDiagnostics.RootFailure`
  which `AppModel.scan` maps to `ScanState.failed` (AppModel.swift:200).
- `Cleaner.refusalReason` (Cleaner.swift:118) now:
  - fails closed when the lstat probe errors (`invalidPath` instead of assuming "not a
    symlink", Cleaner.swift:120-122);
  - rejects a root whose standardized and symlink-resolved paths differ
    (`resolvedRoot == rootPath`, Cleaner.swift:137);
  - for `.trash`, requires `~/.Trash` itself to be non-aliased
    (`trashPath == resolvedTrash`, Cleaner.swift:145) and requires the item to be under
    `~/.Trash` in both the standardized non-resolved and the resolved spelling
    (Cleaner.swift:146-147).
- Selftest: `symlink-root:` (Scanner refuses a symlinked root),
  `trash-resolved:` (an item spelled under `~/.Trash` but resolving elsewhere is
  refused, target intact), existing `trash-outside:`/`outside-root:` unchanged.

### 2. Case-insensitive denylists (review 06)

- `DiskScanner.foldedPath` (DiskScanner.swift:668) normalizes with canonical
  precomposition, case folding and diacritic folding, and strips trailing slashes
  (`path(percentEncoded:)` appends one for directories — this was the actual bypass).
- `Cleaner.forbiddenPaths`/`forbiddenPrefixes` store folded entries
  (Cleaner.swift:84, 95) and compare both the standardized and resolved item paths
  (Cleaner.swift:133-135). `isAllowedLargeFileRoot` folds the home and candidate paths
  (DiskScanner.swift:473).
- Selftest: `case-fold:` creates a fixture through the lowercase spelling
  `~/library/application support/…` and asserts the clean is refused
  (`protectedLocation`) and the file intact. `large-roots:` asserts
  `~/library` is refused.

### 3. Custom large-file root policy aligned between scanner and cleaner (reviews 05, 07)

- `isAllowedLargeFileRoot` (DiskScanner.swift:473) is now an allowlist:
  strict descendants of `$HOME` (excluding `~/Library` and `~/.Trash`) or strict
  descendants of `/Volumes` (`/Volumes/X`, external/removable volumes). It refuses `/`,
  `$HOME` itself, `/Users`, `/Users/<other>`, `/Volumes` (root), `/private`, `/tmp`,
  `/dev`, `/home`, `/Network`, `/cores` and system locations.
- `Cleaner.refusalReason` (Cleaner.swift:148) accepts a `.largeFiles` root outside
  `$HOME` when it passes `isAllowedLargeFileRoot`, and every other category still
  requires a `$HOME`-contained root. No existing refusal was removed.
- A persisted `largeCustomRoot` is re-validated at launch and dropped from
  `UserDefaults` when no longer allowed (AppModel.swift:116-123).
- Selftest: `large-roots:` covers slash/users/volumes/home/library refusal plus a home
  descendant being allowed.

### 4. `ItemSafety.protected` is now live (reviews 04, 06)

- `DiskScanner.protectedSafety(for:category:)` (DiskScanner.swift:367) returns
  `.protected(ext)` for the existing `protectedExtensions` (`.app`, `.photoslibrary`,
  `.sparsebundle`, VM disks, `.plugin`, `.kext`, …) in every `scanChildren` category
  (caches, logs, trash); large files keep skipping them as before. Items are
  unselectable and never pre-selected (`isSelected: safety.isSafe && defaultSelected`,
  DiskScanner.swift:359).
- `Cleaner.clean` already refuses `item.safety.isProtected` before any mutation
  (Cleaner.swift:41); that guard is now reachable.
- Selftest: `trash-app-protected:` classifies a `.app` fixture in Trash as
  `.protected("app")` and asserts the clean is refused and the bundle intact.

## P1 fixes

### 5. Scan errors surfaced instead of "Nothing to clean"

- `DiskScanner.ScanDiagnostics` (DiskScanner.swift:7): `attemptedRoots`,
  `rootFailures: [RootFailure(path:issue:)]`, `skippedItems`, with
  `hadErrors`/`readNothing`.
- `DiskScanner.scan` returns `(items, root, diagnostics)` (DiskScanner.swift:151).
  Root enumeration errors (`contentsOfDirectory` `try?` swallowing) now record a
  failure; per-child metadata failures are counted in `skippedItems`.
- `AppModel.scan` maps `readNothing` (all attempted roots failed, e.g. symlinked Trash
  or TCC denial) to `ScanState.failed(message)`; otherwise a completed scan sets
  `CategoryResult.partialFailure` and stores `CategoryResult.diagnostics`
  (AppModel.swift:199-207). No new UI was added; `FailureView` already renders
  `.failed`.
- `HeadlessMode --scan` prints `[unreadable] path: reason` lines for every root
  failure (HeadlessMode.swift:190-192).
- Remaining: the failure messages are composed from structured issues plus
  `error.localizedDescription`; localized strings for `symlink`/`notDirectory`/
  `missing`/`notAllowed` still need to be added to `Support/Resources` by the owner of
  that directory (no new keys could be added here). `partialFailure` is not yet
  rendered by the UI.

### 6. Cleaning is off the main actor, with per-category state

- `AppModel.performClean` (AppModel.swift:285) runs `Cleaner.clean` inside
  `Task.detached(priority: .userInitiated)` and returns to the MainActor via
  `completeClean` (AppModel.swift:303). Cancelling the stored task makes the existing
  `Task.isCancelled` checkpoint in `Cleaner.clean` effective.
- `isCleaning(_:)` / `isAnyCleaning` / `cleaningCategories` (AppModel.swift:136-142)
  are published; `requestClean` and `performClean` refuse a second concurrent clean of
  the same category. `cancelClean(_:)` (AppModel.swift:299) is available.
- The 350 ms `Task.sleep(nanoseconds:)` was replaced with
  `Task.sleep(for: .milliseconds(350))`.
- `Cleaner.Report` is `Sendable`; `ScanItem`/`ItemSafety`/`CautionReason` are
  `Sendable` (ScanItem.swift:3, 28, 59).

### 7. "Select all" no longer steals manual flagged selection

- `AppModel.toggleSelectAll` (AppModel.swift:259):
  - if not all safe items are selected: select every safe item, leave flagged items
    exactly as the user left them;
  - if all safe items are selected: deselect everything selectable.
- Selftest: `select-all-preserve:` (a manually checked caution item survives the
  additive pass) and `select-all-clear:` (second call clears safe + flagged).

### 8. Scan cancellation with generation tokens

- `scan(_:)` (AppModel.swift:162) stores `(id: UUID, task:)`; the commit and every
  progress increment are gated on the token, so a late/cancelled scan can never
  overwrite a newer one or leave a non-zero `liveBytes`.
- `cancelScan(_:)` (AppModel.swift:218) cancels, immediately frees the slot, and resets
  the category to `.idle` with cleared items/diagnostics (no half states).
- `isAnyScanning` is driven by the live task table (AppModel.swift:132).

### 9. Honest size accounting at clean time

- `Cleaner.measuredSize` (Cleaner.swift:71) measures the item with
  `DiskScanner.size(of:)` immediately before removal (best effort, falling back to the
  scan-time size); failed items never contribute. `Report.movedToTrash`
  (Cleaner.swift:27) splits the recoverable subset from permanent deletions;
  `CleanReport.movedToTrash` exposes it to the UI (AppModel.swift:71).
- Remaining: `CleanReportView` still headlines `freed` for both modes; the UI owner
  should use `movedToTrash`/`permanent` to label the metric ("moved to Trash" vs
  "freed").

## API added for the views owner

- `AppModel.isCleaning(_:) -> Bool`, `AppModel.isAnyCleaning: Bool`,
  `AppModel.cancelClean(_:)`.
- `CategoryResult.partialFailure: Bool`, `CategoryResult.diagnostics:
  DiskScanner.ScanDiagnostics` (path/issue per failed root, `skippedItems`).
- `CleanReport.movedToTrash: Int64`.
- `DiskScanner.ScanDiagnostics`, `DiskScanner.rootValidationFailure(for:missingIsError:)`
  and `DiskScanner.protectedSafety(for:category:)` are internal and usable by tests.
- `Cleaner.refusalReason(for:category:)` is now internal (was private) for tests.

## Remaining work (out of this perimeter)

- Localized strings for the new diagnostics and a `partialFailure` banner/state in the
  views.
- Report UI split between `freed` and `movedToTrash`; selection semantics caption.
- Treat `NSFileNoSuchFile` on clean as idempotent success (review 07 P1) — not in the
  assigned fix list, current behavior is an explicit failure line.
- Filesystem-identity (`st_dev`, `st_ino`) binding and fd-relative permanent deletion
  (review 06 recommendations 1/5) remain future hardening; the string checks here are
  deliberately fail-closed in the meantime.
- `--scan` still exits 0 when roots are unreadable; it prints diagnostics only.
