# 01 — Performance & Memory

Context (review date 2026-09-13): Sweep is a macOS 14 SwiftUI app (SPM, ~2.9k LOC) that walks
`~/Library/Caches`, `~/Library/Logs`, `~/.Trash`, a fixed developer-cache list and user media
folders, then deletes selected entries via `FileManager`. This review focuses on scan hot paths
(`DiskScanner`), `CategoryResult` derived state, SwiftUI invalidation and the clean path.
Measurements are from a release build (`make app`, Swift 5.9) on a 12-core Apple Silicon Mac
(8P+4E, APFS SSD, warm metadata cache) using the read-only headless mode:
`/usr/bin/time -l ./dist/Sweep.app/Contents/MacOS/Sweep --scan <category>` (never deletes).
Reference data points: `~/Library/Caches` = 64,780 files / 9,012 dirs / 9.6 GB; `~/.Trash` =
19 items / 4.88 GB; `largeFiles` walks Downloads/Desktop/Documents/Movies/Pictures/Music and
found 21 items ≥ 100 MB (10.2 GB). Headless end-to-end for `logs` is 0.10 s, and the app does
not scan at launch (`AppModel.init` only reads prefs and one free-space query), so startup is
healthy — no action needed there.

## Findings

### [P1] `Cleaner.clean` executes synchronously on the main actor — the UI freezes while cleaning
`AppModel` is `@MainActor` (Sources/Sweep/Models/AppModel.swift:74) and `performClean` creates a
plain `Task { … }` (AppModel.swift:244-246), which inherits MainActor isolation. Calling the
synchronous `Cleaner.clean` (Sources/Sweep/Services/Cleaner.swift:31) therefore runs every
`trashItem`/`removeItem` on the main thread. Impact: the window stops redrawing and stops
responding to events for the whole clean, with no progress or cancel path; a 4.88 GB directory
currently sitting in `~/.Trash` is removed recursively by `removeItem` (Cleaner.swift:53), and
items on external/network volumes can stall for seconds to minutes. The 350 ms delay at
AppModel.swift:253 and the report sheet only appear after everything is already done.
Recommendation: run the clean in `Task.detached(priority: .userInitiated)` (or a nonisolated
async clean function) and hop back to the main actor to publish the report; `Cleaner` already
checks `Task.isCancelled` (Cleaner.swift:39), so cancellation becomes usable once detached.

### [P1] `largeFiles` walk is single-threaded and drives RSS to ~3–4× the scan baseline
`scanLargeFiles` iterates the six roots sequentially (Sources/Sweep/Services/DiskScanner.swift:372-383)
and `walkLargeFiles` is a synchronous recursive DFS (DiskScanner.swift:385-451) with no
`autoreleasepool` and with each stack frame keeping its `entries: [URL]` alive across the
recursive call at DiskScanner.swift:430. Measured with `/usr/bin/time -l`:
`--scan largeFiles` = 2.96 s cold / 1.59–2.10 s warm with only 0.91 s user + 0.76 s sys
(≈ 0.6–0.9 cores of 12), and **max RSS 106–125 MB vs 31–38 MB for `caches`/`logs`/`trash`/
`developer`**, confirmed by 50 ms RSS sampling (growth from ~13 MB to ~96–120 MB during one
run). For comparison, `--scan` (all five categories, sequential) peaks at 130.6 MB. On a
100k+ file tree, both the wall time and the memory spike grow linearly; the UI stays alive
(it is off-main) but shows the spinner for an unnecessarily long time.
Recommendation: process the six roots concurrently with a bounded `withTaskGroup` (width 4,
give each root its own collector and merge the results), and wrap each directory-body in
`autoreleasepool { }` (or convert to an explicit stack) to bound peak memory. Expected
3–5× wall-time reduction on multi-root scans and a flat memory profile.

### [P1] `scanAll()` has no global concurrency budget — up to 33 simultaneous blocking enumerations
`scanAll` starts one scan per category concurrently (AppModel.swift:139-141). Each of `caches`,
`logs`, `trash` and `developer` opens its own task group capped at `maxConcurrentScans = 8`
(DiskScanner.swift:41, 209-230, 298-319), and `largeFiles` adds its own blocking walk: worst case
4 × 8 + 1 = 33 concurrent synchronous enumerations, each issuing `getattrlist`/`readdir`
syscalls. The per-category cap is not a process-wide cap. Measured single-category behaviour
already shows the ceiling: `--scan caches` (224 children, 64,780 files) takes 0.52 s wall for
1.83 s user+sys, i.e. only **~3.5× speedup with 8 workers**, so adding four more competing scans
cannot scale and mostly adds kernel/IO contention and latencies. On spinning disks or network
volumes the effect is worse.
Recommendation: introduce a process-wide async semaphore (budget ≈ active core count, e.g. 6–8)
shared by all enumeration tasks, and either serialize `scanAll` categories or run at most two at
a time; keep `largeFiles` outside the `scanChildren` budget but still under the global limiter.

### [P2] `CategoryDetailView.body` rebuilds filtered collections on every model publication
The body recomputes `flagged` and `runningCount` with two full `filter` passes
(Sources/Sweep/Views/CategoryDetailView.swift:10-13) and `CleanBar` adds a third pass plus
`allSatisfy` (CategoryDetailView.swift:371-372) on every evaluation. With `AppModel` publishing
on every selection toggle and every progress flush, this is O(n) per repaint, and `scanChildren`
has no item cap: a `~/.Trash` or cache folder with 100k top-level entries makes each toggle
traverse 3–4 arrays of 100k `ScanItem` values. `AppModel.result(for:)` also default-constructs
a `CategoryResult` on each access (AppModel.swift:125-127) — harmless today, but any stored
derived state must stay cheap to create. Recommendation: compute `flagged`, `flaggedCount` and
`selectable` once inside `CategoryResult.refreshTotals` (AppModel.swift:40-55) and store them;
views then read precomputed values. Effort S, removes all per-frame filtering.

### [P2] Every selection toggle copies the whole `[ScanItem]` array and recomputes all totals
`toggleSelection` copies the `CategoryResult` (AppModel.swift:205), mutates one element inside
`mutateItems` (AppModel.swift:208, 35-38), which triggers copy-on-write of the entire array, then
`refreshTotals` (AppModel.swift:40-55) does a full O(n) sum and rebuilds `selectedItems` from
scratch. `toggleSelectAll` does the same over the full array (AppModel.swift:212-231). At today's
sizes (≤ 224 top-level cache entries, `largeFiles` capped at 500 via `prefix(500)` at
DiskScanner.swift:382) this is ~10–50 µs; with an uncapped 100k-item listing it becomes a
multi-MB memcpy plus 100k-iteration scan per click, i.e. visible lag and churn. Recommendation:
maintain running `totalSize`/`selectedSize`/`selectedItems` incrementally on single-item toggles
and only do a full `refreshTotals` after `replaceItems`/`removeItems`; keep an `id → index` map
if `firstIndex(where:)` (AppModel.swift:206) ever shows up in profiles.

### [P2] `liveBytes` progress publications invalidate the entire view graph at up to 50 Hz
`AppModel` is one `ObservableObject`; `liveBytes` is a dictionary published as a whole
(AppModel.swift:78). `ProgressReporter` flushes at most every 100 ms per scan (DiskScanner.swift:21)
and each flush wraps the update in a fresh `Task { @MainActor … }` (AppModel.swift:166-170), so a
`scanAll()` produces up to 5 × 10 = 50 object-wide invalidations per second. Every observer —
`SidebarView` rows, `SidebarFooter`, `CategoryDetailView`, `CategoryHeader`, `CleanBar` — re-runs
its body each time even though only one category's byte counter changed. These bodies are cheap
today (findings above), so this is currently a battery/CPU cost rather than a frame drop, but it
is the multiplier that makes the O(n) body work above expensive. Recommendation: model progress
per category (small `ObservableObject` per scan, or migrate `AppModel` to `@Observable` on
macOS 14 so only views reading `liveBytes[category]` are tracked) and/or throttle publications to
~5 Hz for the numeric text. Effort M, biggest structural win for UI cost.

### [P2] Running-apps snapshot is taken on the main actor once per category scan
`scan(_:)` calls `NSWorkspace.shared.runningApplications` on the MainActor for every category
(AppModel.swift:156-157); `scanAll` repeats it five times. This call is documented to be
potentially slow (LaunchServices snapshot) and is pure overhead duplicated per category.
Recommendation: take one snapshot per user action (`scanAll` passes it down) and/or refresh it
from `NSWorkspace` launch/terminate notifications in the background. Effort S.

### [P2] Large-files walk micro-costs: per-entry suffix scan and duplicate metadata lookups
`isProjectFolder` (DiskScanner.swift:453-460) runs for every non-root directory
(DiskScanner.swift:402) and, for every entry, linearly scans all 12 `projectMarkerSuffixes`
with `hasSuffix`; using `entry.pathExtension.lowercased()` against a `Set` is O(1). Separately,
`scanChild` fetches `childKeyArray` values (DiskScanner.swift:243) and then `size(of:)`
re-fetches `metadataKeys` (DiskScanner.swift:162-171), which are not among the prefetched keys,
adding one extra stat per top-level child. Neither dominates (metadata-bound walk), but both are
free wins inside the hottest loop. Recommendation: replace the suffix loop with an extension
`Set`, and have `scanChild` pass the already-fetched directory flag / allocated size into a
`size(of:values:)` overload to avoid the second lookup. Effort S.

### [P2] `ItemRow` re-renders and reformats on every list invalidation
`ItemRow` (CategoryDetailView.swift:221-361) is not `Equatable` and is not wrapped in
`.equatable()`, and each body invocation formats `item.size` (CategoryDetailView.swift:266) and
the `modified` date (CategoryDetailView.swift:259) from scratch. `ScanItem`'s `==` is
deliberately cheap (id + selection, Sources/Sweep/Models/ScanItem.swift:84-86), but nothing uses
it during diffing; every model change re-renders all visible rows. With `LazyVStack`
(CategoryDetailView.swift:208) only ~15–25 rows are live, so impact is small; it scales with the
list size only if the caps are lifted. Recommendation: precompute formatted strings on
`ScanItem` (they are immutable) or conform `ItemRow` to `Equatable` and apply `.equatable()` so
row bodies are skipped when `id`/`isSelected` are unchanged. Effort S/M.

### [P2] `Cleaner` re-resolves the same root path for every item
`refusalReason` calls `resolvingSymlinksInPath().standardizedFileURL` on the item and on
`item.root` for every item (Cleaner.swift:110-112), even though all items of a category share
the same root, then scans 27 forbidden prefixes twice per item (Cleaner.swift:116). Cleaning a
100k-item Trash does 300k+ path resolutions before deletion. Recommendation: resolve the root
once per `clean` call, hoist the prefix check into precomputed `[String]` comparisons and pass
the resolved root into `refusalReason`. Effort S; matters most once cleaning is moved off the
main thread (finding 1), where it bounds throughput instead of freezing the UI.

## Recommendations

Priority order (quick wins first). Effort: S < half a day, M ≈ 1–2 days, L > 2 days.

| # | Action | Addresses | Effort | Quick win |
|---|--------|-----------|--------|-----------|
| 1 | Move `Cleaner.clean` to `Task.detached`, publish report on MainActor | P1 clean freeze | S | yes |
| 2 | Wrap `walkLargeFiles` directory bodies in `autoreleasepool`, convert to iterative stack | P1 memory | S | yes |
| 3 | Parallelize the six `largeFiles` roots with a bounded task group (width 4), merge per-root results | P1 serial walk | M | |
| 4 | Add a process-wide concurrency budget shared by every enumeration task; cap `scanAll` at 1–2 concurrent categories | P1 concurrency burst | M | |
| 5 | Snapshot `NSWorkspace.runningApplications` once per user action | P2 duplicate main-thread work | S | yes |
| 6 | Store `flagged`, `flaggedCount`, `selectable` in `CategoryResult.refreshTotals` | P2 body filtering | S | yes |
| 7 | Make selection totals incremental (delta updates, id → index map) | P2 O(n) per toggle | M | |
| 8 | Split or throttle progress publications (per-category observable, or 5 Hz coalescing) | P2 50 Hz invalidation | M | |
| 9 | Replace `projectMarkerSuffixes` linear scan with `pathExtension` in a `Set`; avoid duplicate stat in `scanChild` | P2 walk micro-costs | S | yes |
| 10 | Resolve the item root once per `Cleaner.clean` call | P2 clean throughput | S | yes |
| 11 | Precompute formatted size/date on `ScanItem` and make `ItemRow` equatable | P2 row re-render | S/M | yes |

Re-measure after changes with:
`make app && /usr/bin/time -l ./dist/Sweep.app/Contents/MacOS/Sweep --scan largeFiles`
(watch real/user/sys and `maximum resident set size`) and
`./dist/Sweep.app/Contents/MacOS/Sweep --scan` for the aggregate. Today's release baseline on
this machine: `largeFiles` ≈ 1.6–3.0 s / 106–125 MB; all categories sequential ≈ 3.6 s / 130 MB;
`caches` ≈ 0.5 s / 38 MB. The GUI `scanAll` path also needs Instruments (Time Profiler +
Allocations) because it is concurrent, unlike the sequential headless run.

## References

Files read for this review:

- `Package.swift`, `Makefile`
- `Sources/Sweep/SweepApp.swift`
- `Sources/Sweep/HeadlessMode.swift`
- `Sources/Sweep/Models/AppModel.swift`
- `Sources/Sweep/Models/ScanItem.swift`
- `Sources/Sweep/Models/SpaceCategory.swift`
- `Sources/Sweep/Models/L10n.swift`
- `Sources/Sweep/Services/DiskScanner.swift`
- `Sources/Sweep/Services/Cleaner.swift`
- `Sources/Sweep/Views/ContentView.swift`
- `Sources/Sweep/Views/CategoryDetailView.swift`
- `Sources/Sweep/Views/SidebarView.swift`
- `Sources/Sweep/Views/StateViews.swift`
- `Sources/Sweep/Views/LargeFilesControls.swift`
- `Sources/Sweep/Views/Sheets.swift`
- `Sources/Sweep/Views/SettingsView.swift`
- `Sources/Sweep/Views/DesignSystem.swift`
- `Sources/Sweep/Views/BrandPalette.swift`
- `Sources/Sweep/Views/AboutView.swift`
- `docs/DESIGN.md` (partial), `docs/RELEASING.md` (partial)
