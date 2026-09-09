# 07 — Error Handling & Edge Cases

Context: Sweep scans `~/Library/Caches`, `~/Library/Logs`, `~/.Trash`, fixed developer
caches and user-selected large-file roots, then moves items to the Trash
(`FileManager.trashItem`) or permanently deletes only inside `~/.Trash` (`Cleaner.swift`).
It is unsandboxed, ad-hoc signed, and relies on TCC/Full Disk Access for protected
locations. The app declares `ScanState.failed` and a `FailureView`, but the scanner has no
error channel — every filesystem error is discarded locally with `try?` and the UI has no
reachable failure path. This review traces every failure between scan and clean.

## Findings

### [P0] TCC / permission failures are swallowed and rendered as a successful empty scan

- **Edge case**: First scan of Desktop / Documents / Downloads before TCC is granted (or
  after the user denies the prompt), unreadable roots (other users, denied, unmounted
  volume), or any unreadable subdirectory.
- **File:line**: `DiskScanner.swift:200-204` (`(try? fm.contentsOfDirectory(...)) ?? []`),
  `DiskScanner.swift:395-399` (`guard let entries = try? … else { return }`),
  `DiskScanner.swift:154` (roots filtered only by policy, never validated),
  `DiskScanner.swift:243-244` (`try?` per child silently drops the item).
- **Current behavior**: all I/O errors collapse to `[]`. `AppModel.scan` always sets
  `.done` (`AppModel.swift:172-186`); `ScanState.failed` is never assigned anywhere in the
  codebase (the `FailureView` at `CategoryDetailView.swift:75-78` is unreachable dead
  code). The category then shows the success checkmark "Nothing to clean"
  (`StateViews.swift:10-13`, `CategoryDetailView.swift:68-71`). A user who denied the
  Desktop prompt sees "nothing to clean" while the folder was never read. Same for
  `root.largeFiles.default`: the label stays "Downloads, Desktop, Documents…" even when
  5 of 6 roots were unreadable.
- **Desired behavior**: distinguish "empty" from "unreadable"; show a failed or partial
  scan state per category with an actionable, localized message and the existing Full
  Disk Access deep-link (`AppModel.openFullDiskAccessSettings`), instead of a success
  empty state.
- **Recommendation**: change the scan result to `(items, root, diagnostics)` where
  diagnostics aggregates unreadable root/dir counts and the first `CocoaError`; map
  `NSFileReadNoPermissionError`/EPERM to a localized FDA hint; assign `ScanState.failed`
  (or a `.partial` variant) and make `EmptyStateView` never display a success checkmark
  when diagnostics are non-empty.

### [P1] A custom large-file root outside `$HOME` can be scanned but never cleaned

- **Edge case**: user picks an external/removable volume (or any folder outside the home
  directory) via `NSOpenPanel` as the Large Files root.
- **File:line**: `DiskScanner.swift:351-362` (`isAllowedLargeFileRoot` explicitly permits
  `/Volumes/...`), `Cleaner.swift:127-131` (`guard isDescendant(resolvedRoot, of: home)
  else { return .unauthorizedRoot }`), `Info.plist:46-47`
  (`NSRemovableVolumesUsageDescription` advertises removable volumes).
- **Current behavior**: items are scanned, listed as selectable, preselected, and the
  confirmation sheet offers to clean them; every single clean is then refused with
  `unauthorizedRoot` and the report lists all items as "not deleted"
  (`Cleaner.swift:46-49`, `:116-118`). README's "user-chosen folder" claim does not hold
  for anything outside `~`.
- **Desired behavior**: either (a) allow cleaning items whose resolved path is a
  descendant of the *authorized scan root* (plus the existing forbidden-paths/prefixes
  guard), or (b) reject such a root at selection time with the existing
  "Protected folder" alert and never list items.
- **Recommendation**: persist the authorized root at scan time and make the cleaner use
  it as the containment reference (option a), or gate `chooseLargeFilesFolder` on
  `isAllowedLargeFileRoot` **and** `isDescendant(root, home)` (option b). Option (a)
  matches the product intent.

### [P1] Cleaning runs synchronously on the main actor — UI freeze, no progress, no cancel

- **Edge case**: clean a large selection (hundreds of cache directories, large Trash) —
  each `trashItem`/`removeItem` is a synchronous filesystem call.
- **File:line**: `AppModel.swift:244-245` (`Task { let outcome = Cleaner.clean(...) }`
  inside a `@MainActor` class inherits main-actor isolation), `Cleaner.swift:38-63`
  (synchronous `for`/`do/catch` loop).
- **Current behavior**: the whole deletion loop executes on the main thread; the
  window/app beachballs with no progress and no way to cancel. The cancellation guards
  are dead code: `Cleaner.swift:39` can never observe cancellation because the task is
  never stored or cancelled, and `AppModel.swift:246` (`if Task.isCancelled { return }`)
  is equally unreachable. `CleanReportView` only appears after the whole loop
  (`AppModel.swift:253-260`).
- **Desired behavior**: run the clean loop off the main actor, publish per-item progress
  on the main actor, and either support cancellation between items (removing already
  processed IDs) or explicitly document that a clean is atomic once confirmed.
- **Recommendation**: use `Task.detached` (or a nonisolated async `Cleaner.clean` with a
  `@MainActor` progress callback). If cancellation is not desired, delete the misleading
  `Task.isCancelled` checks and show a determinate/indeterminate progress state.

### [P1] Cancelling a scan discards partial results with no message

- **Edge case**: user clicks Cancel during a long scan (or a rescan replaces an in-flight
  one).
- **File:line**: `AppModel.swift:173-176` and `:190-192`; `DiskScanner.swift:232`
  (`slots.compactMap` drops cancelled children).
- **Current behavior**: on cancellation, items and root are cleared and the state goes
  back to `.idle` — the UI shows "No scan yet" as if nothing had happened. Work already
  done is thrown away with no explanation and no way to resume. Cancellation is also
  slow: task-group children keep running until each finishes its current directory.
- **Desired behavior**: keep the partial items with an "incomplete scan" banner and a
  Rescan button (localized string), or at minimum show a "scan cancelled" notice.
- **Recommendation**: add a `cancelled`/`.partial` state to `ScanState` (or a
  `wasCancelled` flag on `CategoryResult`), keep `output.items`, and render a warning
  banner; have `scanChildren` check `Task.isCancelled` before adding the next child.

### [P1] Items already deleted between scan and clean are reported as failures and stay listed

- **Edge case**: another process (or Finder, or the user) removes a cache file after the
  scan but before the clean; a directory is renamed/replaced; an iCloud file is evicted.
- **File:line**: `Cleaner.swift:51-62` (`catch` appends a failure), `AppModel.swift:249`
  (`removeItems` only receives `outcome.removedIDs`).
- **Current behavior**: `trashItem` throws `NSFileNoSuchFileError`; the item is reported
  as "not deleted" (`clean.failure.reason` with the raw system message), remains selected
  in the list, and `freed` is not credited. A file that is already gone is presented as
  an error the user must act on.
- **Desired behavior**: treat "no longer exists" as idempotent success: remove it from
  the list without counting it as a failure (or show it as "already removed — skipped").
- **Recommendation**: catch `CocoaError.fileNoSuchFile` (`NSFileNoSuchFileError`) and
  `NSFileReadNoSuchFileError` before the generic catch, add the ID to `removedIDs` (or a
  dedicated `skipped` bucket) and keep the failure list for real errors.

### [P2] The failure report is name-only, non-actionable, and duplicate names break the list

- **Edge case**: two failures with the same file name (common: `Caches/foo`, `Caches/bar`
  both contain `Cache.db`); long failure lists; user wants to fix a failure.
- **File:line**: `Cleaner.swift:67-69` (`failureLine` formats only
  `lastPathComponent: reason`), `Sheets.swift:91` (`ForEach(report.failures, id: \.self)`
  on `[String]`), `Sheets.swift:85-105` (fixed 110 pt scroll box, no selection/copy).
- **Current behavior**: the report shows `name: reason` lines with no path, no Reveal in
  Finder action and no retry button; SwiftUI receives duplicate `id`s when two identical
  strings occur (undefined list behavior). `CleanReportView` has no retry path — the user
  must guess and rescan.
- **Desired behavior**: a structured failure model with stable identity
  (`id: UUID`, `url`, `name`, `reason`, `recoverable`) and per-row actions (Reveal, Copy
  path), so errors can be triaged after the fact.
- **Recommendation**: change `Cleaner.Report.failures` to `[CleanFailure]`; display the
  truncated path under the name; add "Reveal in Finder" and a "Retry failed items"
  action that re-selects the still-listed items.

### [P2] Raw system errors are shown instead of mapped, actionable messages

- **Edge case**: permission denied, read-only/exFAT volume, disk full, locked file,
  volume unmounted mid-clean, sandbox/TCC denial.
- **File:line**: `Cleaner.swift:61` (`error.localizedDescription`),
  `Support/Resources/en.lproj/Localizable.strings:30` (`"clean.failure.reason %@ %@"`).
- **Current behavior**: refusal reasons are properly localized in all four languages
  (`refusal.*`, verified key parity across en/fr/de/es, UTF-8) but I/O errors fall back
  to Foundation's `localizedDescription`, which is locale-dependent system wording ("The
  file couldn't be completed because…") and never tells the user what to do (grant FDA,
  eject/unlock, free space). Disk-full and read-only cases need no special deletion logic
  (trash is a same-volume rename; permanent delete only frees) but the message is
  unhelpful when they do fail.
- **Desired behavior**: map the common `CocoaError` codes
  (`fileWriteNoPermission`, `fileWriteVolumeReadOnly`, `fileNoSuchFile`,
  `fileReadUnknown`) and `NSPOSIXErrorDomain` ENOSPC to stable localized strings with an
  actionable hint, keeping the technical detail available (tooltip/log).
- **Recommendation**: add a `localizedReason(for error:)` mapper in `Cleaner` and
  dedicated keys in all four `Localizable.strings`.

### [P2] A missing / unmounted scan root silently scans as empty and stays persisted

- **Edge case**: the ExternalVolume chosen as Large Files root is ejected; the folder is
  deleted/renamed; Downloads does not exist (fresh machine).
- **File:line**: `AppModel.swift:91-93` and `:111-113` (custom root persisted in
  `UserDefaults`), `DiskScanner.swift:154` (root filter checks policy, not existence),
  `DiskScanner.swift:395-399` (walk failure → `return`).
- **Current behavior**: `scanLargeFiles` produces `(items: [], root: <stale path>)`; the
  UI shows `.done` + "Nothing to clean" with the success checkmark and the unmounted
  volume path in the header. No hint that the root is unreachable.
- **Desired behavior**: validate each root before walking (exists, is a directory,
  readable); if none are available, surface `.failed` with "folder not available" and a
  one-click reset to user folders.
- **Recommendation**: return per-root diagnostics from `scanLargeFiles` and check
  `FileManager.fileExists` + `isReadableFile` at scan start; clear or flag
  `largeCustomRoot` when the volume disappears.

### [P2] Size computation failures silently become 0 bytes and skew totals

- **Edge case**: an item's metadata cannot be read (permission on a child, broken
  resource values), or an enumerator hits unreadable descendants.
- **File:line**: `DiskScanner.swift:163` (`guard let values = try? … else { return 0 }`),
  `DiskScanner.swift:179-180` (error handler `{ _, _ in true }` swallows every
  enumeration error), `DiskScanner.swift:254` (`reporter.add(total)` with 0),
  `DiskScanner.swift:330` (`guard total > 0 else { return nil }` hides existing entries).
- **Current behavior**: items are listed as "0 bytes", category totals and the header
  understate real usage, and `Cleaner` credits `item.size` (0) to `freed` even when a
  directory is successfully trashed (`Cleaner.swift:59`).
- **Desired behavior**: represent "size unknown" explicitly (e.g. `Int64?`), exclude
  unknown sizes from totals with a count of unmeasured items, and do not hide existing
  developer entries just because their size could not be computed.
- **Recommendation**: make `size(of:)` return `Int64?` and propagate; optionally recount
  `freed` from the trashed path before deletion when size is unknown.

### [P2] Symlink check fails open and has a TOCTOU window before deletion

- **Edge case**: stat on the item fails while it is actually a symlink; a parent
  directory is swapped for a symlink after the refusal check but before the mutation;
  a dangling symlink.
- **File:line**: `Cleaner.swift:107-108` (`(try? url.resourceValues(...))?.isSymbolicLink`
  — nil on error passes the check), `Cleaner.swift:51-57` (actual
  `trashItem`/`removeItem` after the check), `Cleaner.swift:110-112`
  (`resolvingSymlinksInPath` resolves at check time only).
- **Current behavior**: a failed symlink probe is treated as "not a symlink" (fail-open),
  and the time gap between the check and the `removeItem`/`trashItem` call allows a
  parent-component swap. The per-item window is small and the item-level symlink case is
  safe (`removeItem`/`trashItem` act on the link itself), but parent swaps can redirect
  the mutation outside the scan root.
- **Desired behavior**: fail closed — refuse whenever the symlink/`lstat` probe errors;
  re-validate realpath + `lstat` immediately before the mutation and compare it to the
  validated path, or delete via a file descriptor (`O_NOFOLLOW`, `unlinkat`).
- **Recommendation**: treat probe errors as `.symlink`/`.invalidPath` refusals now
  (cheap), and add an immediate `realpath` recheck before `trashItem`; file-descriptor
  based deletion can remain a later hardening step.

### [P2] In-use / actively-written files rely only on a heuristic app-name match

- **Edge case**: an app or launchd daemon is actively writing a cache/log while the user
  cleans it; background agents are not in `NSWorkspace.runningApplications`; a locked
  file (`uchg`) or a file held open by another process.
- **File:line**: `DiskScanner.swift:479-511` (token matching against bundle IDs and
  localized names), `DiskScanner.swift:248-251` (`appRunning` caution),
  `AppModel.swift:156-157` (source of the running set).
- **Current behavior**: token matching is fuzzy in both directions (false negatives for
  daemons/helpers, false positives for short names) and only drives a non-blocking
  caution. Trashing a file held open or locked by another process succeeds or fails at
  the OS level and is only reported after the fact; the app may immediately recreate the
  cache. This is recoverable-by-design (Trash), but the caution can be misleading.
- **Desired behavior**: keep the safe default (never preselected when unsure) and add an
  mtime-based "recently written" caution (e.g. modified in the last 10 minutes) that is
  independent of the running-app heuristic; document that Trash is the recovery path for
  locked/in-use files.
- **Recommendation**: add a `recentlyWritten` `CautionReason` computed from
  `contentModificationDate`; label it in all four language files.

### [P2] Dead error/safety paths hide regressions

- **Edge case**: any future change assuming `ScanState.failed` is exercised or that
  `.protected` items exist.
- **File:line**: `ScanState.failed` declared `AppModel.swift:9`, rendered
  `CategoryDetailView.swift:75-78`, never assigned; `ItemSafety.protected` declared
  `ScanItem.swift:28-31`, checked in `Cleaner.swift:41-44`,
  `CategoryDetailView.swift:329-338`, `HeadlessMode.swift:100-101`, never constructed by
  the scanner; `FailureView` (`StateViews.swift:71-98`) unreachable.
- **Current behavior**: the UI appears to have an error contract that does not exist; the
  cleaner's `isProtected` refusal can never trigger. `rescanIfDone` handles `.failed`
  (`AppModel.swift:197`) for a state that cannot occur.
- **Desired behavior**: either wire these states to real conditions (see P0/P1 above) or
  remove them so the code does not advertise unhandled behavior.
- **Recommendation**: implement the diagnostics model and use `.failed`; either construct
  `.protected` (e.g. for `protectedExtensions` matched outside large files) or delete the
  enum case and its checks.

### [P2] Very long names and control characters in failure lines

- **Edge case**: file names containing newlines/tabs, 255-byte names, RTL/CJK names.
- **File:line**: `Cleaner.swift:67-69` (`failureLine` embeds the raw
  `lastPathComponent`), `ScanItem.swift:80-81` (`name`/`path`),
  `Sheets.swift:89-105` (fixed-height scroll box; `Text(line)` wraps freely).
- **Current behavior**: UI display truncates names with `.middle` and handles Unicode,
  but a name containing `\n` injects fake report lines, and very long names make the
  110 pt failure box hard to read. Paths are never shown, so duplicates of long names are
  indistinguishable.
- **Desired behavior**: sanitize control characters before display/formatting, truncate
  middle, and show the parent path as secondary text.
- **Recommendation**: strip `CharacterSet.controlCharacters` from `name` in
  `ScanItem.init` (or at display time) and back the report with the structured model from
  the finding above.

### [P2] Headless `--scan` cannot signal failures

- **Edge case**: CI/scripts use `--scan` to detect what Sweep sees; a root is unreadable.
- **File:line**: `HeadlessMode.swift:87-113` (prints counts and `exit(0)` unconditionally).
- **Current behavior**: unreadable roots print `0 items` and the process exits 0; an
  automated consumer cannot distinguish "clean" from "permission denied".
- **Desired behavior**: print the diagnostics from the P0 recommendation and exit
  non-zero when a requested root could not be read.
- **Recommendation**: reuse the scan diagnostics and add a `--strict` (or always)
  non-zero exit on unreadable roots.

### [P2] Ad-hoc signature amplifies the silent-failure problem across rebuilds

- **Edge case**: user grants Full Disk Access, then runs `make app` / installs an update.
- **File:line**: `Makefile:24` (`codesign --force --sign -`), `README.md:151` (documented
  re-prompt), `README.md:81` (releases are ad-hoc, not notarized).
- **Current behavior**: the TCC grant is keyed to the code signature; after every
  rebuild the permission is silently lost and, because of the P0 finding, scans just
  return empty — the user has no signal that access regressed.
- **Desired behavior**: once the P0 failure state exists, the app itself reports the
  regression and offers the FDA deep-link; ideally release builds use a stable Developer
  ID signature.
- **Recommendation**: ship the P0 fix (primary), keep the README note, and plan
  Developer ID signing + notarization for releases.

### Verified OK (no action)

- Permanent deletion is confined to `~/.Trash` and the "Empty Trash" flow is announced
  as irreversible (`Cleaner.swift:122-126`, `Sheets.swift:18-42`); the refusal matrix
  (symlink, invalid path, protected location, outside scan root, unauthorized root) is a
  strong, non-destructive default.
- `~/Library/Logs/DiagnosticReports` is scanned as a normal child of Logs, moves to Trash
  (recoverable, regenerated by macOS) — no special handling needed.
- Localization files are all UTF-8 and have identical key sets across en/fr/de/es; all
  refusal/report keys are translated. Disk-full is not destructive (Trash is a rename);
  failures surface through the report, though with poor wording (see P2 mapping).
- `ProgressReporter` is correctly locked and flushes its tail (`DiskScanner.swift:7-39`);
  free-space read failure degrades to a localized "Unavailable" (`SettingsView.swift:187-190`).

## Recommendations

Prioritized. Effort: S = hours, M = 1-2 days, L = multi-day.

1. **(P0, M)** Add a scan diagnostics channel: `DiskScanner` returns unreadable-root/dir
   counts + first error; `AppModel` maps them to a real `.failed`/partial state; wire the
   existing `FailureView` and stop rendering the success checkmark for scans that read
   nothing. Map EPERM/TCC to a localized Full Disk Access message.
2. **(P1, S)** Treat already-deleted items as idempotent success in `Cleaner`, remove
   them from the list, and reserve failure lines for real errors.
3. **(P1, S/M)** Fix the external custom-root policy: authorize the scanned root (or
   reject it at selection time) so `/Volumes/...` items can actually be cleaned.
4. **(P1, M)** Move `Cleaner.clean` off the main actor with progress reporting; remove or
   implement the dead cancellation checks.
5. **(P1, S/M)** Preserve partial results on scan cancellation with an "incomplete scan"
   banner and rescan CTA.
6. **(P2, M)** Replace `[String]` failures with a structured `CleanFailure` (id, url,
   reason, recoverable), add Reveal/Copy/Retry, and fix the `id: \.self` duplicate-ID
   issue.
7. **(P2, M)** Add a localized error mapper for `CocoaError`/ENOSPC cases
   (permission → FDA, read-only volume, disk full, locked, missing).
8. **(P2, S)** Validate roots at scan start and surface missing/unmounted roots instead
   of an empty success; reset stale `largeCustomRoot` when the volume disappears.
9. **(P2, S)** Represent unknown sizes explicitly instead of `0`, and sanitize control
   characters in names used for display/reporting.
10. **(P2, S)** Fail closed on symlink-probe errors and re-validate realpath immediately
    before the mutation (file-descriptor deletion as later hardening).
11. **(P2, S)** Add an mtime-based "recently written" caution independent of the running
    app heuristic.
12. **(P2, S)** Make `--scan` exit non-zero and print diagnostics for unreadable roots.
13. **(P2, M)** Add tests: refusal matrix unit tests (already partially covered by
    `--selftest`), scanner fixtures with an unreadable directory (chmod 000 / EPERM),
    cancelled scan, and already-deleted item. Extend `--selftest` or add a test target.
14. **(P2, S/L)** Keep the ad-hoc/TCC note in the README; plan Developer ID signing for
    release builds so grants survive updates.

## References

Files read:

- `Sources/Sweep/Services/DiskScanner.swift`
- `Sources/Sweep/Services/Cleaner.swift`
- `Sources/Sweep/Models/AppModel.swift`
- `Sources/Sweep/Models/ScanItem.swift`
- `Sources/Sweep/Models/SpaceCategory.swift`
- `Sources/Sweep/Models/L10n.swift`
- `Sources/Sweep/Views/ContentView.swift`
- `Sources/Sweep/Views/CategoryDetailView.swift`
- `Sources/Sweep/Views/StateViews.swift`
- `Sources/Sweep/Views/Sheets.swift`
- `Sources/Sweep/Views/SettingsView.swift`
- `Sources/Sweep/Views/LargeFilesControls.swift`
- `Sources/Sweep/Views/SidebarView.swift`
- `Sources/Sweep/Views/AboutView.swift`
- `Sources/Sweep/SweepApp.swift`
- `Sources/Sweep/HeadlessMode.swift`
- `Support/Info.plist`
- `Support/Resources/{en,fr,de,es}.lproj/Localizable.strings` (key parity checked)
- `Makefile`, `Package.swift`, `README.md`, `SECURITY.md`, `DESIGN.md`
