# 08 — UX & Accessibility

Sweep is a SwiftUI macOS 14+ disk cleaner whose central promise is safety: safe items are pre-checked, risky items are flagged, and nothing is permanent except emptying the Trash. This review is a source-level UX/accessibility audit (no build, no VoiceOver runtime pass — read-only constraint), covering EN/FR/DE/ES strings, the light/dark screenshots, and all view/model source.

Method: every finding cites the exact source line; contrast ratios are computed from the brand tokens in `BrandPalette.swift` and standard macOS semantic colors. The app's own accessibility rules (`DESIGN.md` §7) are used as the acceptance bar.

## User flows evaluated

**1. First launch → scan.** The window opens on Caches with a centered "No scan yet" state and a prominent Scan button (`StateViews.swift:26`); the toolbar exposes "Scan All" (⇧⌘R) and "Scan" (⌘R) with tooltips. Discoverability of the Analyser action is good. Two friction points: the bottom bar already displays a disabled "Clean" button before anything is scanned (visible in `docs/assets/sweep-light.png`), and nothing explains the safety model or why Full Disk Access matters — FDA is only a `.link`-style button in the sidebar footer (`SidebarView.swift:45`). No `.failed` state can ever be produced (see P1-04), so an empty scan due to permissions is indistinguishable from "nothing to clean."

**2. Scan → progress → cancel.** Progress is a live checked-bytes counter shown in three places (header, detail, sidebar) with a spinning ring (`DesignSystem.swift:115`, `StateViews.swift:38`). Cancel exists only as a button inside the scanning category's detail view (`StateViews.swift:64`); there is no Esc shortcut, no menu command, and no "Cancel All" for the Scan All burst. The app does not respect Reduce Motion despite `DESIGN.md:222` mandating it.

**3. Review → selection → flagged filtering.** Rows show name, path, an inline orange caution sentence, a badge, modified date and size — a clear at-a-glance review. The flagged filter (`CategoryDetailView.swift:83`) only appears when flagged items exist, and duplicates the same state as the orange capsule in the CleanBar (`CategoryDetailView.swift:388`). Its picker label is a missing localization key. "Select All" is where the safety story breaks: see P0-01/P1-03.

**4. Confirmation → clean.** The sheet states count/size and, for Trash, an irreversible warning; Esc cancels correctly. But Return is bound to the destructive button even for "Empty the Trash" (P0-02), and performing the clean has no progress state at all (P1-06).

**5. Report.** Success/partial titles, freed bytes and a failure list are present, but the report offers no Esc-to-close, no copy/export, and no way to locate or retry a failed item (`Sheets.swift:65`).

**6. Large files.** The min-size picker, 6-month toggle and folder picker are grouped above the list (`LargeFilesControls.swift`), items are size-sorted and unchecked by default. Changes auto-trigger a rescan without notice or debounce, results are silently capped at 500, and the reset-folder affordance is an unlabeled icon button.

## Findings

### [P0] Checkbox state and row semantics are invisible to VoiceOver — `Sources/Sweep/Views/CategoryDetailView.swift:221-361`

The row is a single `Button` (`:229`) whose label is composed from child views; the checkbox is two `Circle` shapes plus a checkmark image (`:300-325`) with no accessibility value, and there is no `.accessibilityValue`, `.accessibilityAddTraits(.isSelected)`, or hint anywhere in the row. A VoiceOver user hears "name, path, caution, Flagged item, date, size, button" but **cannot tell whether the item is checked** — the core review step before deletion. Protected rows add `.disabled(!isSelectable)` (`:281`), which removes them from keyboard tab order entirely, so the one state most in need of explanation ("Protected — never offered for deletion") becomes unreachable for keyboard-only users. The `.accessibilityLabel` on the nested badge images (`:338`, `:348`) is also unreliable inside a button label because SwiftUI merges button children heuristically.

**Recommendation:** make each row an explicit accessibility element: `.accessibilityElement(children: .ignore)`, `.accessibilityLabel(name)`, `.accessibilityValue` combining path, size, modified date and safety (`Selected` / `Not selected` / `Protected`), `.accessibilityHint` for the toggle, and add `.isSelected` when checked. Do not disable protected rows; keep them focusable and expose the refusal as value/hint. Hide decorative shapes (`.accessibilityHidden(true)`) and move "Reveal in Finder"/"Copy Path" to `.accessibilityAction`s.

### [P0] Return permanently deletes in the "Empty the Trash?" sheet — `Sources/Sweep/Views/Sheets.swift:49-56`

`Button(...).keyboardShortcut(.defaultAction)` is attached to the destructive button regardless of category (`:56`). In the Trash sheet the red "Empty Trash" button is therefore the default: pressing Return anywhere in the sheet irreversibly deletes the user's Trash, in violation of the macOS HIG rule that destructive actions are never the default button. Esc works (`:47`) but Return is the habitual confirmation key.

**Recommendation:** for `pending.category.isPermanentDeletion`, remove `.defaultAction` (or move it to Cancel) and require an explicit click/Space; optionally add a second confirmation (type-to-confirm) for very large deletions. Keep Esc on Cancel.

### [P1] "Select All" silently unchecks manually-reviewed flagged items and can become a no-op — `Sources/Sweep/Models/AppModel.swift:212-231`, `Sources/Sweep/Views/CategoryDetailView.swift:379-386`

When not everything is selected, `toggleSelectAll` sets `items[index].isSelected = items[index].safety.isSafe` (`AppModel.swift:226`). Any flagged item the user deliberately checked while reviewing is therefore reset to unchecked. Worse, because flagged items remain unchecked and `allSelected` requires *every selectable* item to be selected (`:215`), the button label never flips to "Deselect All" while flagged items exist: pressing "Select All" after it has already selected the safe set does nothing, and there is no one-click way to clear the safe selection.

**Recommendation:** make the additive action never clear existing checks (only set `true` for safe items). Drive the label from `selectedItems.isEmpty` (any selection → "Deselect All") or split into two explicit controls: "Select Safe Items" and "Deselect All". See P1-09 for making the semantics visible.

### [P1] Scan failures are silent and the FailureView is unreachable — `Sources/Sweep/Models/AppModel.swift:5-10, 143-188`, `Sources/Sweep/Services/DiskScanner.swift:200-204, 395-399`, `Sources/Sweep/Views/StateViews.swift:94`

`ScanState.failed` exists and `FailureView` is wired (`CategoryDetailView.swift:75`), but no code path ever assigns `.failed`; on scan completion the state is always `.done` (`AppModel.swift:178`). All directory-read errors are swallowed by `(try? fm.contentsOfDirectory(...)) ?? []` (`DiskScanner.swift:200`, `:395`) and `errorHandler: { _, _ in true }` (`:180`), so an unreadable/denied location produces an empty list and the UI says "No items found in this category" (`StateViews.swift:94`). Users without Full Disk Access are told there is nothing to clean when in fact folders were skipped — the opposite of the app's safety posture.

**Recommendation:** propagate a partial/failed status from `DiskScanner` (count skipped locations, return the first error), assign `.failed` or add a "some folders were skipped" banner with an "Open Full Disk Access" call to action. Reuse the existing `FailureView`.

### [P1] Reduce Motion is ignored — `Sources/Sweep/Views/DesignSystem.swift:115-135`

`SpinningRing` starts a `.linear(duration: 0.9).repeatForever(autoreverses: false)` animation on appear (`:130`) and is used simultaneously in the header, sidebar rows and scanning view. `DESIGN.md:222-223` explicitly requires a static track under Reduce Motion, and no `@Environment(\.accessibilityReduceMotion)` exists anywhere in the codebase.

**Recommendation:** gate the rotation on `accessibilityReduceMotion` (draw a static 30% arc or a determinate-capable `ProgressView`), and gate the numeric `contentTransition` animations and hover/spring animations likewise.

### [P1] Orange caution text and capsules fail contrast in light mode — `Sources/Sweep/Views/CategoryDetailView.swift:249-250, 340-346, 392-399`

The per-row caution sentence is `.caption2` (11 pt) in system orange (`:250`); system orange `#FF9500` on a white window is ≈2.2:1, far below the 4.5:1 required for small text and 3:1 for graphics. The warning badge icon and its `Color.orange.opacity(0.15)` circle (`:342-346`) and the orange flagged capsule label on a 14% orange capsule over `.ultraThinMaterial` (`:392-399`) fail the same way. Only dark mode passes (≈8:1). The app's own rule "never encode state by color alone" is respected via icons, but the text remains unreadable in the default light appearance.

**Recommendation:** introduce a semantic caution color pair in `BrandPalette` (e.g. dark orange `#B45309`/`#C2410C` for light mode, system orange for dark), use it for the text/icon/capsule label, and verify with Accessibility Inspector in both appearances and with Increase Contrast.

### [P1] Tertiary metadata and checkbox border are below the 3:1 graphical minimum — `Sources/Sweep/Views/CategoryDetailView.swift:261, 307`

The modified date is `.caption` in `.tertiary` (`:261`, ≈2.3:1 in light mode; it is also the metadata used to judge "old" files in the Large Files flow) and the unchecked checkbox border is `Color.secondary.opacity(0.45)` (`:307`, ≈2:1), below the 3:1 needed for UI component boundaries. Protected rows additionally apply `.opacity(0.72)` (`:282`), compounding both.

**Recommendation:** use `.secondary` for the date and a ≥3:1 border token (or a filled neutral circle) for the unchecked state; avoid whole-row opacity for disabled states — dim only the fill, not borders/text.

### [P1] No busy state during cleaning; the clean action can be triggered twice — `Sources/Sweep/Models/AppModel.swift:239-263`, `Sources/Sweep/Views/CategoryDetailView.swift:421-435`

`performClean` closes the sheet immediately and runs asynchronously; there is no `isCleaning` flag, no progress, no cancel. `CleanBar`'s Clean button is only disabled when the selection is empty or `.scanning` (`:432`), so during a long permanent Trash deletion the button is live again and the user can launch a second clean of the same items (the second pass then reports spurious failures). The report is additionally delayed by an unexplained 350 ms sleep (`AppModel.swift:253`).

**Recommendation:** add an `isCleaning` state per category, show an in-place busy/progress UI (items removed / total, `ProgressView`), disable Scan/Clean/select-all while cleaning, allow cancel, and show the report when done instead of the artificial delay.

### [P1] Localization key `filter.title` is missing in all four languages — `Sources/Sweep/Views/CategoryDetailView.swift:92`

The segmented filter's `Picker("filter.title", …)` has `.labelsHidden()`, and `filter.title` exists in none of `Support/Resources/{en,fr,de,es}.lproj/Localizable.strings` (verified). The segment values are localized, but the picker's accessibility label will be the raw key `filter.title` for VoiceOver. There is also no visible/announced explanation that "flagged" excludes protected items and that Select All only checks safe ones.

**Recommendation:** add `filter.title` (e.g. "Show") to all four string files, add an explicit `.accessibilityLabel("filter.title")`, and add a "Check localization keys in CI" test comparing keys used in code with the base strings file.

### [P1] A running scan cannot be cancelled from the keyboard — `Sources/Sweep/Views/StateViews.swift:64`, `Sources/Sweep/SweepApp.swift:22-33`

The only cancel affordance is the in-view `Button("action.cancel")` with no `.keyboardShortcut(.cancelAction)`. Esc does nothing; the View menu has Scan commands but no "Cancel Scan" (⌘.); with Scan All running, each category must be found and cancelled individually. For a potentially long read-only operation this is a standard macOS expectation gap.

**Recommendation:** add `.keyboardShortcut(.cancelAction)` to the scanning cancel button, add a "Cancel Scan" menu command (⌘.) acting on the selected/all scanning categories, and disable the menu Scan commands while scanning.

### [P2] Safety-critical semantics live only in hover tooltips — `Sources/Sweep/Views/CategoryDetailView.swift:383-385, 402`, `Sources/Sweep/Views/LargeFilesControls.swift:27-40`

`.help()` is pointer-hover only. The fact that "Select All only checks items without a warning" (`cleanbar.selectAll.warningHelp`) is the single most important sentence about the selection model and is invisible to keyboard and touch-only users; same for the flagged capsule explanation and the unlabeled reset-folder icon button (`LargeFilesControls.swift:30-40`, icon has no `accessibilityLabel`).

**Recommendation:** surface the select-all semantics as a persistent `.caption` line next to the button whenever `flaggedCount > 0`, give the reset button a text label or at least an `accessibilityLabel` + `.help`, and keep tooltips as secondary reinforcement.

### [P2] Long-list ergonomics: no sort/search, hidden 500-item cap, no scanned-at — `Sources/Sweep/Services/DiskScanner.swift:382`, `Sources/Sweep/Models/AppModel.swift:180`, `Sources/Sweep/Views/CategoryDetailView.swift:201-219`

Lists are `ScrollView` + `LazyVStack` sorted once by size; there is no sort control, no search, no timestamp ("scanned at"), and Large Files silently truncates to the first 500 matches (`prefix(500)`, `DiskScanner.swift:382`) with a UI that still reads "N items". `scannedAt` is stored (`AppModel.swift:180`) but never displayed, so stale results are indistinguishable from fresh ones. Row actions (reveal/copy) are context-menu only, with no double-click or keyboard shortcut.

**Recommendation:** add a sort menu (size/date/name), a search field for Large Files/Caches, show "Scanned at HH:MM" in the header, and if the cap is kept, state "Top 500 by size" explicitly. Add ⌘⇧R-style shortcuts or toolbar equivalents for Reveal in Finder.

### [P2] Fixed font sizes, fixed widths and German strings will clip — `Sources/Sweep/Views/CategoryDetailView.swift:143, 174, 185, 249`, `LargeFilesControls.swift:15`, `SettingsView.swift:16`, `SidebarView.swift:39-43`

The header's 24/30 pt numbers use fixed `.system(size:)` and do not scale with text size; `.caption2` (`:249`) violates `DESIGN.md:159` ("never below .caption"); the subtitle and path are `.lineLimit(1)`. Fixed frames — `Picker` 190 pt, sheets 450 pt, Settings 560×430 — do not accommodate longer German: `safety.caution.running` is 93 chars and is clipped by `.lineLimit(2)` (`:247`), `settings.largeFiles.oldOnly` ("Nur Dateien, die vor mehr als 6 Monaten geändert wurden"), `sidebar.freeSpace.unavailable` ("Freier Speicher nicht verfügbar", `.lineLimit(1)` in a 240 pt sidebar) and `settings.storage.fullDiskAccess.open` are the risky ones.

**Recommendation:** replace fixed `.system(size:)` with semantic styles plus `@ScaledMetric` for the numeric displays, raise the caution line to `.caption` and 3 lines (full text stays available to VoiceOver), make fixed frames flexible, and add a DE pseudo-locale/longest-string test at the 980 pt minimum window width.

### [P2] CleanBar is rendered (disabled) before a scan and during scans — `Sources/Sweep/Views/CategoryDetailView.swift:34-39, 421-435`, `docs/assets/sweep-light.png`

In `.idle` the bottom bar shows a disabled "Clean" primary button with no explanation; during scanning, select-all and the flagged capsule are hidden but the bar still occupies space. This is visual noise on the first screen and competes with the real call to action ("Scan").

**Recommendation:** hide `CleanBar` unless `result.state == .done && !result.items.isEmpty`, or replace it with a one-line safety hint in idle ("Files are always moved to the Trash — nothing is erased").

### [P2] "Scan All" has no aggregate progress or cancel; up to 5 × 8 concurrent operations — `Sources/Sweep/Models/AppModel.swift:139-141`, `Sources/Sweep/Services/DiskScanner.swift:41`

`scanAll()` starts all five category scans in parallel; each category runs up to `maxConcurrentScans = 8` tasks (`DiskScanner.swift:41`), i.e. up to ~40 concurrent directory walks, with no global progress display and no way to stop everything. On battery or spinning disks this is heavy and opaque; per-category spinners are only visible if the user opens each sidebar row.

**Recommendation:** scan categories sequentially (or cap global concurrency), surface a global "Scanning 3/5 — Cancel All" strip, and consider remembering the last scan completion per category in the sidebar.

### [P2] Large Files controls trigger full rescans on every change — `Sources/Sweep/Views/LargeFilesControls.swift:60-65`, `Sources/Sweep/Views/SettingsView.swift:141-146`

Every threshold pick or 6-month toggle immediately re-walks the filesystem; the screen swaps to the scanning state with no notice that the controls caused it. A user comparing thresholds can repeatedly kick off multi-second scans. (Also, settings changes silently affect the same re-scan.)

**Recommendation:** debounce or require an explicit "Apply/Rescan" action, and show an inline "Settings changed — rescanning…" message; disable the controls while a scan runs.

### [P2] Report sheet lacks Esc, copy/export and failed-item actions — `Sources/Sweep/Views/Sheets.swift:85-117`

Close only has `.defaultAction` (`:116`), so Esc does not dismiss; failure lines (name + reason, `:91-96`) cannot be copied, revealed in Finder, or retried. For a cleaner whose promise is "you can always recover and understand", the report dead-ends.

**Recommendation:** add `.keyboardShortcut(.cancelAction)` to Close, a "Copy Report" button, and per-failure "Reveal in Finder" plus a "Try Again" that re-selects only the failed items.

### [P2] No first-run safety-model or Full Disk Access onboarding — `Sources/Sweep/Views/StateViews.swift:17-23`, `Sources/Sweep/Views/SidebarView.swift:45-52`

The empty state repeats the header subtitle verbatim and never states the two facts a first-time user needs: what will happen to selected files (Trash, recoverable) and why some folders may be missing from results (Full Disk Access / TCC). The FDA entry point is a small link in the sidebar footer with tooltip-only detail.

**Recommendation:** add a one-line safety statement to the idle empty state ("Checked items are moved to the Trash — nothing is erased, except when you empty the Trash"), and after a scan that found zero items in a potentially protected root, show an inline "Some folders were skipped — grant Full Disk Access" banner with an action.

### [P2] Trash permanence is only revealed at confirmation — `Sources/Sweep/Views/CategoryDetailView.swift:424-431`, `Sources/Sweep/Views/Sheets.swift:19, 30-34`

Before selection, the only cue that this category deletes permanently is the red "Empty Trash" button and tooltip; the row list and select-all look identical to recoverable categories. A user who habituates to "Clean = recoverable" could confirm without reading the sheet body.

**Recommendation:** show a persistent caption/banner in the Trash detail ("Items deleted here cannot be recovered") and make the CleanBar's destructive styling unmistakable; consider an additional "Type EMPTY to confirm" for >10 GB or >100 items.

### [P2] Dynamic values are not announced, and the copy confirmation is silent — `Sources/Sweep/Views/StateViews.swift:56-61`, `Sources/Sweep/Views/CategoryDetailView.swift:176-177, 408-418`, `Sources/Sweep/Views/AboutView.swift:104-112`

Live byte counters, selection totals and the "Copied" button state change visually only; VoiceOver gets no announcements, and the continuously updating text is not marked `.updatesFrequently` or summarized as a progress value. The copied state also may be missed since the button label reverts after 1.6 s.

**Recommendation:** attach a concise `.accessibilityValue` to the scanning group and post `AccessibilityNotification.Announcement` sparingly (scan finished, clean finished, copy confirmed); mark live counters appropriately rather than letting them re-announce on every update.

## Recommendations (prioritized)

**Do first — safety/accessibility blockers**
1. Remove `.defaultAction` from the irreversible "Empty Trash" button; keep Esc on Cancel. `Sheets.swift:56` — **S**
2. Expose row state to accessibility: ignore/combine children, label + value + selected trait + hint; stop `.disabled` on protected rows; hide decorative shapes. `CategoryDetailView.swift:221-361` — **M**
3. Fix `toggleSelectAll` to be additive and give the button a working, accurately-labeled toggle ("Select Safe Items" → "Deselect All"); show the "warning items are left unchecked" caption when flagged items exist. `AppModel.swift:212-231` — **S**

**High value**
4. Respect Reduce Motion in `SpinningRing` and all repeat animations. `DesignSystem.swift:115-135` — **S**
5. Contrast pass: light-mode caution color token, date/checkbox/border minimums, remove whole-row opacity. `CategoryDetailView.swift:249-307, 392-399` — **M**
6. Cleaning state: `isCleaning`, in-place progress, disabled actions, cancel, report on completion. `AppModel.swift:239-263` — **M**
7. Surface scan failures and skipped folders; make `FailureView` reachable and add an FDA call to action. `DiskScanner.swift`, `StateViews.swift` — **M**
8. Add `filter.title` to all `.lproj` files + picker accessibility label + a CI string-key check. — **S**
9. Keyboard completeness: Esc cancels scans, "Cancel Scan" (⌘.) menu command, disabled menu states, explicit row focus styling/arrow navigation. `StateViews.swift:64`, `SweepApp.swift:22-33` — **M**

**Polish**
10. Replace hover-only safety explanations with visible captions; label the reset-folder button. — **S**
11. Long-list tools: sort menu, search, "Top 500" disclosure, "Scanned at" timestamp. — **M**
12. Report actions: Esc close, copy report, reveal/retry failures. — **S**
13. Large Files: debounce/apply changes, rescan notice, disable controls while scanning. — **S**
14. Dynamic Type + German: semantic fonts, `@ScaledMetric`, flexible frames, 3-line caution text, longest-string layout test. — **M/L**
15. First-run safety sentence + FDA banner when results look truncated. — **S**
16. Trash permanence banner before selection. — **S**
17. Scan All orchestration: sequential/global cap + aggregate progress/cancel. — **M**
18. Announce state changes (scan done, clean done, copied) via accessibility notifications. — **S**
19. CleanBar visibility tied to `.done`. — **S**

## References — files read

- `Sources/Sweep/SweepApp.swift`, `Sources/Sweep/HeadlessMode.swift`
- `Sources/Sweep/Models/AppModel.swift`, `ScanItem.swift`, `SpaceCategory.swift`, `L10n.swift`
- `Sources/Sweep/Services/DiskScanner.swift`, `Cleaner.swift`
- `Sources/Sweep/Views/ContentView.swift`, `SidebarView.swift`, `CategoryDetailView.swift`, `StateViews.swift`, `Sheets.swift`, `LargeFilesControls.swift`, `SettingsView.swift`, `AboutView.swift`, `DesignSystem.swift`, `BrandPalette.swift`
- `Support/Resources/en.lproj/Localizable.strings`, `fr.lproj`, `de.lproj`, `es.lproj` (all 159 keys compared against code usage)
- `Support/Info.plist`, `DESIGN.md`, `README.md`, `docs/assets/sweep-light.png`, `docs/assets/sweep-dark.png`
