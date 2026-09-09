# Final Independent Validation — Open Source Publication

Reviewer role: adversarial, independent. This file is the only artifact produced by
this pass; no source, doc, or build file was modified, and nothing was committed.

- Repository under test: `/Users/david/Projects/sweep` (working tree, `main` unborn)
- Date: 2026-09-13
- Claimed target: public release under MIT at `github.com/DavidMolinari/sweep`
- Material reviewed: the 10 review reports (`01-*` … `10-*`), the three fix reports
  (`fixes-core.md`, `fixes-ux.md`, `fixes-final.md`), every Swift source, the Makefile,
  the workflows, `Support/**`, and all top-level/`docs` Markdown.
- Method: line-by-line code reading, fresh release build, packaged-binary runs, and an
  isolated Swift harness built in `/var/folders/.../opencode/adversarial` from **copies**
  of the sources with `NSHomeDirectory()` redirected to a fixture home via
  `SWEEP_TEST_HOME`. The repository files were never touched by the harness; the real
  `~/.Trash` was never replaced or modified.

## 0. Headline

No unresolved data-loss or safety blocking defect was found. Every adversarial scenario
requested for this pass was executed and passed, except one partial-scan visibility gap
described under finding 07-1 (unreadable *subdirectory*). The remaining open P0/P1 items
are test infrastructure, performance, structural refactoring, or owner-operational steps
— none of which can delete or misplace user data in the shipped build.

## 1. Finding-by-finding verification

Status legend: **FIXED** — implemented and verified; **PARTIAL** — the core of the
finding is addressed but a documented sub-case remains; **OPEN** — not addressed in this
wave (some are explicitly deferred to future hardening).

### 01 — Performance & memory

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 01-1 | P1 | `Cleaner.clean` runs on the main actor | **FIXED** | `AppModel.swift:292-296` runs the clean in `Task.detached(priority: .userInitiated)`; `cancelClean` stores/cancels the task (`AppModel.swift:299-301`); `Cleaner.swift:40` checkpoint is now reachable. Re-entry is blocked by `cleanTasks[category] == nil` (`AppModel.swift:289`). |
| 01-2 | P1 | `largeFiles` walk is serial and memory-heavy | **OPEN** | `DiskScanner.swift:500-528`: six roots walked sequentially, recursive DFS, no `autoreleasepool`, no task group. Measured headless `--scan largeFiles` = 2.3 s on this host. |
| 01-3 | P1 | `scanAll()` has no global concurrency budget | **OPEN** | `AppModel.swift:158-160` still starts all categories at once; `DiskScanner.swift:75` still caps per category (8), not process-wide. |

### 02 — Concurrency & Swift 6

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 02-1 | P1 | `Cleaner.clean` executes on the main actor; cancellation dead | **FIXED** | Same as 01-1. The detached handle makes `Task.isCancelled` effective; verified by code and by the clean path never touching `@MainActor` state until `completeClean` (`AppModel.swift:303-322`). |

### 03 — Architecture & testability

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 03-1 | P0 | No test target is possible without restructuring | **OPEN** | `Package.swift:10-13` is still a single `.executableTarget`; `swift test` → `error: no tests found; create a target in the 'Tests' directory`. |
| 03-2 | P0 | `DiskScanner`/`Cleaner` are static enums hardwired to the machine | **OPEN** | Still static `enum`s reading `NSHomeDirectory()` internally; no `FileSystem`/home injection. Only mitigation: `Cleaner.refusalReason` and scanner helpers are now `internal` for tests (`fixes-core.md`). The independent harness had to patch source copies to obtain a sandbox. |
| 03-3 | P1 | `AppModel` is a god-object | **OPEN** | `AppModel.swift` remains one 360-line file with scan, selection, clean, prefs, panels and alerts. |
| 03-4 | P1 | Domain model coupled to SwiftUI/localized text | **OPEN** | `SpaceCategory.swift:1,42-50` still imports SwiftUI and carries `tint`; `ScanItem.swift:9-16` localizes messages in the model; `L10n` stays in `Models/`. |
| 03-5 | P1 | Safety net writes into the real home | **OPEN** | `HeadlessMode.swift:11-14` still creates fixtures in the real `~/Library/Caches` and `~/.Trash`. No test target; the suite is still the CLI script. (I confirmed it cleans up after itself: no `sweep-selftest-*` leftovers after all runs.) |

### 04 — Code quality

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 04-1 | P1 | Clean freeze on main actor | **FIXED** | See 01-1. |
| 04-2 | P1 | Scan errors swallowed, `.failed` unreachable | **FIXED** (root level) | `DiskScanner.swift:284-296` records root read failures; `AppModel.swift:201-207` maps `readNothing` to `.failed(message)` and partial results to `partialFailure`; `FailureView` is now reachable (`CategoryDetailView.swift:85-89`). Caveat: skipped *children* alone do not set `partialFailure` — see 07-1. |
| 04-3 | P1 | Scanner policy and deletion policy disagree | **FIXED** | One policy now: `DiskScanner.isAllowedLargeFileRoot` (`DiskScanner.swift:473-490`) is applied by the picker (`AppModel.swift:333`), the scanner (`DiskScanner.swift:196-208`) and `Cleaner.refusalReason` for `.largeFiles` (`Cleaner.swift:148-149`). |
| 04-4 | P1 | “Freed” figure is not freed space | **FIXED** | `Cleaner` measures the item immediately before removal (`Cleaner.swift:52,71-74`) and splits metrics (`Cleaner.swift:27,60,63`); the report headlines `movedToTrash` for recoverable cleans and `freed` for permanent ones (`Sheets.swift:69-71,88`). |
| 04-5 | P1 | `filter.title` missing from all locales | **FIXED** | Present in EN/FR/DE/ES; parity verified (see §2.6). |

### 05 — Testing & CI

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 05-1 | P0 | No unit-test target | **OPEN** | Same as 03-1. |
| 05-2 | P0 | “Recoverable except trash” invariant not asserted | **PARTIAL** | `empty-trash` asserts `permanent == true` (`HeadlessMode.swift:58-59`), but `move-to-trash` still does **not** assert `permanent == false` (`HeadlessMode.swift:38-39`). The code is correct (`Cleaner.swift:34`, `SpaceCategory.swift:52`), only the assertion is missing. |
| 05-3 | P0 | Four of six refusal paths + protected item untested | **PARTIAL** | Now covered by `--selftest`: `.outsideScan`, `.outsideTrash`, `.protectedLocation` (case-fold), protected-item guard. Still not exercised anywhere: leaf `.symlink`, `.invalidPath`, `.unauthorizedRoot` through `Cleaner`. No unit target exists. |
| 05-4 | P1 | Running-app classification untested | **OPEN** | `runningTokens`/`isRunning` remain `private` (`DiskScanner.swift:628-660`); no tests added. |
| 05-5 | P1 | `isAllowedLargeFileRoot` accepts `$HOME` but cleaner cannot clean it | **FIXED** | `DiskScanner.swift:479` rejects home itself; aligned cleaner branch `Cleaner.swift:148-149`; asserted by selftest `large-roots` and by my harness `roots`. |
| 05-6 | P1 | CI only runs macOS 15, no toolchain pin | **OPEN** | `ci.yml:21` and `release.yml:15` both `macos-15`; no `xcode-select`/setup-swift step. |
| 05-7 | P1 | Localization key drift unguarded | **PARTIAL** | Parity is currently perfect (162 keys × 4, my script check) but there is still no CI/test guard. |

### 06 — Security & safety

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 06-1 | P0 | Symlinked scan roots allow permanent deletion outside `~/.Trash` | **FIXED** | Roots are `lstat`-validated before walking (`DiskScanner.swift:217-228,263-277,406`); `Cleaner` re-validates the leaf, rejects aliased roots (`Cleaner.swift:121-124,137`) and double-checks `.Trash` identity plus item containment before permanent deletion (`Cleaner.swift:140-147`). Independently reproduced: symlinked `.Trash` refused at scan and clean, target file intact (harness `trash-symlink`); selftest `symlink-root`/`trash-resolved`. |
| 06-2 | P1 | Case-sensitive denylists bypassable on case-insensitive APFS | **FIXED** | Unicode-folded comparisons (`DiskScanner.swift:668-675`; `Cleaner.swift:84-114,126-135`). Independently reproduced: `~/library` and `~/LIBRARY` rejected as roots and `~/library/application support/...` refused as a clean, file intact (harness `case-fold`); selftest `case-fold`. |
| 06-3 | P1 | TOCTOU window; lstat failures fail-open | **PARTIAL** | Fail-open closed: lstat error now returns `.invalidPath` (`Cleaner.swift:121-123`). The TOCTOU window between check and `trashItem`/`removeItem` remains; identity binding (`st_dev`,`st_ino`) and fd-relative deletion are explicitly deferred (`fixes-core.md`). |
| 06-4 | P1 | Root authorization is a short denylist | **FIXED** | Replaced by an allowlist: strict descendants of home (minus `~/Library`, `~/.Trash`) or of `/Volumes` (`DiskScanner.swift:473-490`). Independently reproduced: `/`, `/Users`, `/Volumes`, home, `~/Library`, `/Library`, `/private`, `/tmp`, `/dev`, `/Network` refused; `/Volumes/nom` and home subfolders accepted (harness `roots`; selftest `large-roots`). |
| 06-5 | P1 | Ad-hoc signature, no hardened runtime, `xattr` advice | **PARTIAL** | `RELEASING.md:86-128` now specifies Developer ID + `--options runtime --timestamp` + notarize + staple + validate + `spctl` + re-zip + re-checksum, and no longer recommends `xattr` (only warns against it, `RELEASING.md:77`). Shipped builds remain ad-hoc because no Developer ID credentials are available (`Makefile:24`; `README.md:83-84` honestly discloses the Gatekeeper caveat). |

### 07 — Error handling

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 07-1 | P0 | TCC/permission failures rendered as empty success | **PARTIAL** | Root-level denial is fixed and independently reproduced: unreadable `Caches` root → `readNothing` → `AppModel` `.failed(message)` (harness `unreadable`). **Gap found by this review:** an unreadable *subdirectory* only increments `skippedItems`, which does not feed `partialFailure` (`AppModel.swift:199-208` uses `hadErrors`, i.e. root failures only). Harness `partial-skipped` proved: `skippedItems=1`, `hadErrors=false`, state `.done`, `partialFailure=false` → `PartialScanBanner` is not rendered. This is the same class of silent false-completeness the review targeted. |
| 07-2 | P1 | Custom root outside `$HOME` scanned but never cleaned | **FIXED** | `Cleaner.swift:148-149` accepts `.largeFiles` roots that pass the shared allowlist, which includes `/Volumes/X` (`DiskScanner.swift:483-484`); `NSRemovableVolumesUsageDescription` matches. |
| 07-3 | P1 | Cleaning sync on the main actor | **FIXED** | See 01-1. |
| 07-4 | P1 | Cancelling a scan discards partial results silently | **OPEN** | `AppModel.cancelScan` (`AppModel.swift:218-231`) still resets to `.idle` with cleared items/diagnostics. Deliberate choice documented in `fixes-core.md` (“no half states”). |
| 07-5 | P1 | Already-deleted items reported as failures | **OPEN** | `Cleaner.swift:64-66` still routes every error, including `NSFileNoSuchFile`, to a failure line. Explicitly out of the fix perimeter (`fixes-core.md`, “Remaining work”). |

### 08 — UX & accessibility

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 08-1 | P0 | Checkbox state invisible to VoiceOver | **FIXED** | `ItemRow` is one explicit a11y element with label/value/hint and `.isSelected` (`CategoryDetailView.swift:307-317`), protected rows stay focusable, decorative shapes hidden (`:356-382,384-406`). |
| 08-2 | P0 | Return permanently deletes in “Empty the Trash” sheet | **FIXED** | `.keyboardShortcut(permanent ? nil : .defaultAction)` (`Sheets.swift:56`); Cancel keeps Escape (`:47`). Code-verified; no runtime click performed. |
| 08-3 | P1 | Select-all unchecks manually-reviewed flagged items / no-op | **PARTIAL** | Additive behaviour implemented (`AppModel.swift:259-276`) and reproduced (harness `selection`, selftest `select-all-preserve/clear`): a manually checked caution item survives the first press; the second press clears. Residual defect: when only the safe set is selected, the button label is “Select Safe Items” (`CategoryDetailView.swift:432-440` computes `allSelected` over selectable items) while the action deselects everything (`AppModel.swift:262-269`). Label and action disagree in that state. |
| 08-4 | P1 | Scan failures silent / `FailureView` unreachable | **PARTIAL** | Same as 07-1: reachable for root failures, banner unreachable for skipped children only. |
| 08-5 | P1 | Reduce Motion ignored | **FIXED** | `SpinningRing` reads `accessibilityReduceMotion` (`DesignSystem.swift:120-142`); numeric/hover/selection animations are gated in `CategoryDetailView.swift:45,187-188,198-199,294-298`, `StateViews.swift:61-62`, `SidebarView.swift:93-94`. |
| 08-6 | P1 | Orange caution fails light-mode contrast | **FIXED** | Semantic token `caution = #B45309` light / `#FF9F0A` dark (`BrandPalette.swift:109`), applied to caution text, badges and capsule (`CategoryDetailView.swift:262,399,402,471-475`). Verified contrast of `#B45309` on white ≈ 5.0:1 (AA for small text). |
| 08-7 | P1 | Tertiary date / checkbox border below 3:1 | **FIXED** | Date is `.secondary` (`CategoryDetailView.swift:273`), unchecked border is solid `Color.secondary` (`:363`), whole-row opacity removed from protected rows. |
| 08-8 | P1 | No busy state while cleaning; double-trigger | **PARTIAL** | CleanBar is replaced by a spinner + “Cleaning…” + Cancel while running (`CategoryDetailView.swift:499-541`); the list, filter bar, select-all and clean button are disabled (`:33,82,96,452,479`); `performClean` refuses a second clean of the same category (`AppModel.swift:289`). However the toolbar Scan/Scan All (`ContentView.swift:37,46`) and the menu commands (`SweepApp.swift:28-32`) are only gated on `isAnyScanning`, **not** on `isAnyCleaning` — a scan can be launched mid-clean. This contradicts `fixes-final.md` §1 (“Scan and Scan All toolbar buttons are disabled while `model.isAnyCleaning`”) and the CHANGELOG wording. |
| 08-9 | P1 | `filter.title` missing | **FIXED** | Added to all four locales and used as explicit a11y label (`CategoryDetailView.swift:112-118`). |
| 08-10 | P1 | Scan cannot be cancelled from the keyboard | **FIXED** | `.keyboardShortcut(.cancelAction)` on the ScanningView cancel button (`StateViews.swift:65-67`). No “Cancel Scan” menu command was added, but the P1 core (Escape) is done. |

### 09 — Design system & HIG

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 09-1 | P1 | Reduce Motion | **FIXED** | See 08-5. |
| 09-2 | P1 | Permission failures as “Nothing to clean” | **PARTIAL** | See 07-1. |
| 09-3 | P1 | Brand accent dead code; system accent authoritative | **OPEN** | `BrandPalette.Brand.*` still unused (`BrandPalette.swift:33-48`); interactive tint still `.accentColor` (`CategoryDetailView.swift:361,411,512`). `fixes-ux.md` declares this a deliberately deferred design decision. |
| 09-4 | P1 | Glass/material stacked in the content layer | **FIXED** | Header and large-file controls now use flat `contentSurface()` (`DesignSystem.swift:185-208`; `CategoryDetailView.swift:174`; `LargeFilesControls.swift:52`); sidebar footer material removed (`SidebarView.swift:54-57`); material kept only for the floating CleanBar (`CategoryDetailView.swift:522`). |
| 09-5 | P1 | Destructive button is the default (Return) | **FIXED** | See 08-2. |
| 09-6 | P1 | Settings window force-sized; behaviors missing | **PARTIAL** | Fixed frame replaced by min/ideal sizing, tab persisted, About pane removed (`SettingsView.swift:11,25`). Per-pane intrinsic sizing and window-title-follows-pane are still missing (`SweepApp.swift:35-38` has no `windowResizability`); `fixes-ux.md` acknowledges this. |

### 10 — Open source & release engineering

| ID | Sev | Finding | Status | Evidence |
|----|-----|---------|--------|----------|
| 10-1 | P0 | Placeholder contact addresses in policies | **FIXED** | `SECURITY.md:13-15` names GitHub private vulnerability reporting as the only channel, no email; `CODE_OF_CONDUCT.md:62-65` points at the maintainer profile + private channel. No placeholder remains anywhere (grep clean). |
| 10-2 | P0 | Repository not publishable (no commits/remote/tags) | **OPEN** | `git rev-parse HEAD` fails (unborn `main`), no remote, no tag. Also three files are still untracked (`CODEOWNERS`, `release.yml`, `fixes-final.md`) while the rest is staged. This is an owner-operational step; this validation pass is explicitly forbidden to commit. |
| 10-3 | P1 | Ad-hoc signing only | **PARTIAL** | See 06-5. |
| 10-4 | P1 | Binary arm64-only while claiming macOS 14+ | **FIXED** | `Makefile:9-18` attempts `--arch arm64 --arch x86_64` and falls back; `make app` output and `lipo -info` confirm `x86_64 arm64`; `README.md:55-58` documents the fallback. |
| 10-5 | P1 | Notarization runbook would ship an unstapled zip | **FIXED** | `RELEASING.md:86-128`: sign (hardened runtime) → zip → submit → staple → validate → `spctl` → **re-zip** → re-checksum; “no entitlements” stated explicitly; `xattr -d` removed. |

### Counts

- **P0 (11 findings across reports, 10 unique — 03-1 ≡ 05-1):** FIXED 4 (06-1, 08-1,
  08-2, 10-1), PARTIAL 3 (05-2, 05-3, 07-1), OPEN 4 (03-1, 03-2, 05-1, 10-2). After
  deduplicating the test-target finding: unique P0 = 10 — FIXED 4, PARTIAL 3, OPEN 3.
- **P1 (41 findings):** FIXED 22, PARTIAL 9, OPEN 10. All OPEN/PARTIAL items are listed
  with their residual scope in the tables above; each is either explicitly deferred by
  the fix reports, structural (test target, AppModel split), performance work, or
  owner-operational.

## 2. Test battery (run from `/Users/david/Projects/sweep`)

| # | Command / check | Result |
|---|-----------------|--------|
| 2.1 | `swift build -c release` | Exit 0. The repo build was cached, so a second clean build was run against a scratch path (`--scratch-path /var/folders/.../sweep-check-build`): **0 warnings, 0 errors**, 8.7 s. |
| 2.2 | `make app`; `lipo -info dist/Sweep.app/Contents/MacOS/Sweep` | Exit 0. `Architectures in the fat file: x86_64 arm64`; `file` confirms a universal Mach-O. Ad-hoc signature reapplied. |
| 2.3 | `--selftest` | Exit 0, `0 failures`. **11 `check()` scenarios executed** (move-to-trash, outside-root, trash-outside, empty-trash, symlink-root, trash-resolved, large-roots, case-fold, trash-app-protected, select-all-preserve, select-all-clear) plus the `selftest:` summary line = 12 printed lines. Docs claiming “twelve checks” are off by one (see §4). No leftovers in the real `~/Library/Caches` or `~/.Trash` after runs. |
| 2.4 | `--scan caches logs developer largeFiles` | Exit 0 in 3.9 s; plausible results: caches 224 items / 9.5 GB, logs 39 / 60 MB, developer 9 / 5.7 GB, largeFiles 21 / 10.2 GB, with correct `safe` / `caution:app-running` / `caution:ai-models` / `caution:archive-or-database` tags. Read-only. |
| 2.5 | `plutil -lint Support/Info.plist`; `codesign --verify --deep --strict dist/Sweep.app` | `OK`; exit 0. `codesign -dvv`: `flags=0x2(adhoc)`, no TeamIdentifier, no entitlements. |
| 2.6 | l10n parity | EN/FR/DE/ES `Localizable.strings`: **162 keys each, identical key sets, zero duplicates, no empty values, identical format-specifier signatures per key, every `.one` paired with `.other`**. `InfoPlist.strings` key sets identical too. All `String(localized:)` keys found in `Sources/**` exist in the English table. |
| 2.7 | `make -n release` | Chain confirmed: universal build → bundle → `VERSION` read from `Support/Info.plist` (`1.0.0`) → `--selftest` → `plutil -lint` → `codesign --verify --deep --strict` → stage app + `LICENSE` + `README.md` → zip → SHA-256 → checksum re-verification. |
| 2.8 | Workflow YAML | `ci.yml`, `release.yml`, all three issue templates parse with Python `yaml.safe_load` and Ruby `YAML.load_file`. |
| 2.9 | `swift test` | `error: no tests found; create a target in the 'Tests' directory` — confirms 03-1/05-1. |
| 2.10 | CLI edge cases | `--scan bogus` → prints category list, exit 1. `--scan caches bogus` → silently drops `bogus`, exit 0 (known P2 from review 05). |

## 3. Adversarial tests

All destructive tests ran against an isolated fixture home in
`/var/folders/.../opencode/adversarial`, using compiled copies of the real sources with
only `NSHomeDirectory()` redirected. The real `~/.Trash` was never touched.

| Scenario | Expected | Result |
|----------|----------|--------|
| `~/.Trash` is a symlink to `~/Documents` | Scan refuses the root; clean refuses the item; target intact | **PASS** — scanner issue `.symlink`; cleaner `removed=0 failures=1 intact=true`. |
| `~/library` / `~/LIBRARY` as root and as clean | Refused (case-insensitive volume) | **PASS** — both spellings refused as root; item under `~/library/application support` refused `.protectedLocation`, file intact. |
| largeFiles roots `/`, `/Users`, `/Volumes` | Refused | **PASS** — plus home, `~/.Trash`, `~/Library`, `/Library`, `/private`, `/tmp`, `/dev`, `/Network` all refused. |
| largeFiles roots `/Volumes/nom`, home subfolder | Accepted | **PASS**. |
| `.app` in the Trash | Classified protected, unselectable, clean refused | **PASS** — `protectedSafety == .protected("app")`, scanner emits `isSelected=false`, cleaner refuses even when forced selected, bundle intact. |
| Manually check a flagged item, then “Select All” | Flagged check preserved | **PASS** — safe items become selected, the manually checked caution item stays checked, protected stays unselected; second press clears all selectable. |
| Destructive sheet | Return must not trigger “Empty the Trash” | **PASS (code)** — `Sheets.swift:56` attaches `.defaultAction` only when not permanent; Cancel owns Escape. No runtime UI click performed (machine constraint). |
| Unreadable scan root | Visible `.failed`, not “Nothing to clean” | **PASS** — `chmod 000` root → `readNothing` → `AppModel` `.failed` with the permission message. |
| Unreadable *subdirectory* | Visible partial state | **FAIL (gap)** — `skippedItems=1`, `hadErrors=false`, state `.done`, `partialFailure=false` → no banner; the success UI hides the skip. See 07-1. |

## 4. OSS repository review (claims vs reality)

- **Links**: every relative link in `README.md` / `README.fr.md` resolves locally; both
  screenshots exist and are valid PNGs. Absolute GitHub URLs are consistent
  (`DavidMolinari/sweep`). `bug_report.yml` uses the absolute security URL; `config.yml`
  points at Discussions (must be enabled for the link to resolve, owner action).
- **Placeholders**: none left (no `example.com`, no “replace before publication”, no
  TODO/FIXME in shipped docs).
- **LICENSE / THIRD_PARTY_LICENSES**: MIT, consistent with `Info.plist` copyright and
  `AboutView`; no dependencies, statement matches `Package.swift`.
- **README honesty**: ad-hoc signing/Gatekeeper caveat is disclosed (`README.md:83-84`);
  “no telemetry, no networking” matches the code (no `URLSession`/network API; only
  `NSWorkspace.open` for Settings links). “Large files are always unchecked by default”
  matches `DiskScanner.swift:572,595`.
- **`make release`** now performs the gates the runbook used to leave manual
  (`Makefile:38-53`), matching `docs/RELEASING.md` and the README table.
- **`release.yml`**: tag↔`Info.plist` guard, draft release, `contents: write`,
  `fail_on_unmatched_files`. Actions are pinned to floating major tags (`@v4`, `@v2`),
  acknowledged as a follow-up.
- **`ci.yml`** is unchanged: it still runs `make release` and uploads an artifact on
  every PR (review 10 P2), and is macOS 15-only with no toolchain pin (05-6).

### Discrepancies between reports/claims and the code

1. **“Twelve checks”** appears in `README.md:133,202`, `README.fr.md:139,210`,
   `CHANGELOG.md:33`, `docs/RELEASING.md:50`, `fixes-final.md:86,95`. The binary has
   **11 `check()` scenarios**; the 12th printed line is the `selftest:` summary. The
   quoted output block is otherwise byte-identical to the real output.
2. **`fixes-final.md` §1** claims the toolbar Scan/Scan All buttons are disabled while
   `isAnyCleaning`; the code only checks `isAnyScanning` (`ContentView.swift:37,46`), and
   the menu commands are not disabled at all (`SweepApp.swift:28-32`). The CHANGELOG
   repeats this claim (“selection, scan, and select-all controls are disabled while a
   clean is in progress”). Selection and select-all are indeed disabled; scan is not.
3. **`fixes-final.md` §1** presents the partial banner's skipped-children summary as
   generally reachable; with the shipped model it only renders when a root failure
   already exists (07-1).
4. `fixes-core.md` says “`partialFailure` is not yet rendered by the UI”; this is true of
   that wave only — `fixes-final.md` wired it. No final-state impact, but the reports
   contradict each other if read in isolation.
5. **Repo state**: `main` is unborn (no HEAD), no remote, no tag, three files untracked.
   Required before publication; outside this pass's constraints.

## 5. Verdict

### **GO** — the artifact (code, binary, documentation) is safe and honest enough to publish.

No blocker was found that can cause data loss, delete outside `~/.Trash`, follow a
symlink, bypass the protected-location rules, or misrepresent deletion mode in the
shipped build. The review 06 and 08 P0s are fixed and independently reproduced; the
review 07 P0 is fixed at root level with one residual subdirectory-visibility gap (07-1);
the review 10 content P0 (10-1) is fixed, and 10-2 is the mechanical repository-init step.
The remaining open P0/P1s are test infrastructure, performance, structural refactoring, or
documented future hardening.

**Blockers (code/artifact): none.**

**Mandatory owner steps for the publication act itself (operational, not defects):**
1. `git add -A` + initial commit (three files are still untracked), push to
   `github.com/DavidMolinari/sweep`, tag `v1.0.0`. `README`, the CI badge, the About link
   and `SECURITY.md` all assume the repository exists.
2. Enable GitHub **private vulnerability reporting** — `SECURITY.md` designates it as the
   only channel. Optionally enable Discussions (linked from `config.yml`, not from the
   README).
3. If the release assets are advertised as the official download, either obtain a
   Developer ID/notarization or keep the currently honest “ad-hoc, right-click → Open”
   wording in the release notes (as `README.md` and `RELEASING.md` already do).

**Non-blocking findings to fix after the initial commit (documentation-only, no
republishing required):**
- “Twelve checks” → eleven `check()` scenarios (+ summary line) in README/README.fr/
  CHANGELOG/RELEASING.
- Remove or implement the CHANGELOG/`fixes-final` claim that scan controls are disabled
  during cleaning.
- `fixes-final.md` skipped-children banner wording.

**Non-blocking technical residuals (recommended, in priority order):**
1. Make `partialFailure = hadErrors || skippedItems > 0` so an unreadable subdirectory is
   visible (`AppModel.swift:207`). This is the only residual issue with user-facing
   truthfulness impact.
2. `move-to-trash` should assert `permanent == false` (`HeadlessMode.swift:38`).
3. Add a real test target and inject home/clock/filesystem (03-1/03-2/05-x); keep
   `--selftest` as the packaged smoke test.
4. Filesystem-identity binding (`st_dev`,`st_ino`) before mutation and fd-relative
   permanent deletion (06-3).
5. Performance P1s: `largeFiles` concurrency/autoreleasepool (01-2) and a process-wide
   scan budget (01-3).
6. Fix the select-all label/action mismatch in the safe-only-selected state (08-3).
7. Pin CI actions by SHA, restrict release artifacts to `main`, matrix macOS 14/15 (05-6,
   review 10 P2s).

**Confidence: high for the safety verdict** — all deletion-critical paths were verified
by reading the shipped code and independently reproduced against an isolated fixture
home (symlinked Trash, case-fold, allowlist roots, protected bundles, select-all,
unreadable root), plus a green release build, universal binary, 11/11 selftest checks,
and 4-way localization parity. **Medium for the operational verdict** — commit/push/tag,
private vulnerability reporting, and notarization/Developer ID depend on the owner and
on Apple credentials, and were not (and could not be) exercised here. GUI interactions
(VoiceOver runtime, Return-key behavior, Reduce Motion rendering) were verified by code
inspection only, per the no-click constraint.
