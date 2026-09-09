# 06 — Adversarial Safety & Security Audit

Context: Sweep 1.0.0 is a dependency-free SwiftUI/SPM macOS 14+ disk cleaner whose
whole risk budget is spent in `Cleaner.clean`: it moves files to the Trash, and
permanently deletes them for the `trash` category (`FileManager.removeItem`). This
read-only review audits the scan → selection → clean pipeline as an adversary would
(targeting other users' files, protected app data, TCC-granted privileges, and the
signed-bundle boundary), on the working tree of 2026-09-13 (`main`, no commits yet).
No build, no `--selftest`, and no deletion command was run. Release-engineering
(Build, signing runbook, CI) is covered in `10-oss-release.md`; this report only
covers the security/safety consequences where they intersect.

## Threat model

**Assets to protect:** user documents and media (especially `~/Documents`,
`~/Desktop`, `~/Downloads`, external volumes), application state that lives outside
Caches/Logs (`~/Library/Mail`, `Messages`, `Safari`, `Keychains`, `Preferences`,
`LaunchAgents`, Containers, cloud sync folders), other user accounts' data, and the
user's Full Disk Access (FDA) grant. The app itself claims the Trash is the only
permanent-deletion surface (`SECURITY.md:57-63`).

**Surfaces:** (1) directory scan of five categories (`DiskScanner.scan`),
(2) selection in the UI (`AppModel.toggleSelection`/`toggleSelectAll`), (3) cleaning
(`Cleaner.clean` via `AppModel.performClean`), (4) the user-chosen large-file root
(`AppModel.chooseLargeFilesFolder`, persisted in `UserDefaults`), (5) the Trash
category, whose clean path is irreversible, (6) the CLI entry points `--scan` and
`--selftest` (`HeadlessMode`).

**Adversaries assumed:** a same-user unprivileged process/malware that can create
symlinks, edit `~/Library/Preferences/com.github.davidmolinari.sweep.plist`, and
race file operations, but does *not* hold FDA; a user making a plausible mistake
(renaming/moving a folder, keeping a stale confirmation open); a tampered
distribution (ad-hoc-signed zip).

### What holds today (verified)

- `Cleaner.refusalReason` (`Cleaner.swift:104-134`) runs immediately before every
  mutation, independently of any UI state: leaf symlink refused, `standardized` +
  `resolvingSymlinksInPath` path checks, strict `isDescendant` (exact-prefix with
  trailing slash, `path != root`), category-gated permanent deletion
  (`Cleaner.swift:52-53`, `SpaceCategory.isPermanentDeletion`), and a second
  `isProtected` guard (`Cleaner.swift:41`).
- The scanner skips symlink children (`DiskScanner.swift:244`), so no symlink should
  ever enter a list except through an attacker-controlled root or a race.
- No shell, no `Process`/`NSTask`, no network, no URL-scheme/XPC/AppleScript surface.
  `--scan`/`--selftest` args are parsed by exact flag and mapped through
  `SpaceCategory(rawValue:)`; unknown args are ignored, nothing is executed.
- Read failures fail *closed* in the scanner (`?? []`, `try?`), which prevents
  deleting what could not be inspected; localization interpolation passes file names
  as format *arguments*, not format strings (no format-string injection found, and
  `%`/`%@` in filenames are safe).

## Findings

- **[P0] Symlinked scan roots allow permanent deletion outside `~/.Trash` and lie
  about paths in the UI.** The scanner never `lstat`s its roots
  (`DiskScanner.swift:139-148, 200-204`): `contentsOfDirectory` follows a symlinked
  root, and child URLs are built on the symlink spelling. If `~/.Trash` is a symlink
  to, say, `~/Documents`, the Trash scan lists the *target's* files as
  `~/.Trash/<name>` (the UI renders the unresolved `ScanItem.path`,
  `ScanItem.swift:80-81`, `CategoryDetailView.swift:237`), and `Cleaner` re-resolves
  both sides consistently: `resolvedPath`, `resolvedRoot` and the `trashRoot` check
  (`Cleaner.swift:111-126`) all agree because they resolve through the same symlink.
  `forbiddenPaths` matches only the exact `~/.Trash` path and no prefix protects
  `~/Documents/`, so one click on "Empty Trash" + confirm runs
  `removeItem` on real user files (`Cleaner.swift:53`) — irreversible, user-visible
  path is fake, and no privilege is required beyond writing the symlink. The same
  trick with `~/Library/Caches`/`Logs`/developer roots moves files from unlisted
  folders (recoverable, but displayed under a fake path). *Mitigation:* refuse to
  scan or clean when any root is a symlink or not a directory (`lstat` /
  `.isSymbolicLinkKey` on the root itself, and on `~/.Trash` at clean time); capture
  each root's `(st_dev, st_ino)` at scan time in `ScanItem` and re-verify before each
  operation; display resolved paths in the UI.

- **[P1] Case-sensitive string denylists are bypassable on the default
  case-insensitive APFS volume.** All protections are byte-wise
  (`hasPrefix`/`==` at `Cleaner.swift:115-118`, `DiskScanner.swift:351-358`), while
  macOS volumes resolve `/users/david/librarY` (verified on this host) and
  `resolvingSymlinksInPath()`/`standardizedFileURL()` do not case-fold. Concretely,
  a poisoned `largeCustomRoot` (`AppModel.swift:91-93, 111-113`; the plist is
  writable by any same-user process and is not re-validated on load) set to
  `/Users/<u>/library` passes `isAllowedLargeFileRoot` — its check
  `path == home + "/Library"` misses — and the scanner then walks the real
  `~/Library`; at clean time `resolvedPath.hasPrefix(home + "/Library/Mail/")` also
  misses because the stored spelling is lowercase. A low-privilege process (no FDA)
  therefore steers FDA-holding Sweep into listing and trashing
  `~/Library/Mail`, `Messages`, `Preferences`, `LaunchAgents`, and other TCC- or
  app-protected data. *Mitigation:* never compare user-influenced paths as strings;
  compare filesystem identity of protected directories (`stat` `(st_dev, st_ino)`
  for `~/Library`, `~/.Trash`, `/System`, …) and case-fold string comparisons on
  case-insensitive volumes.

- **[P1] TOCTOU between `refusalReason` and the filesystem call; lstat failures are
  fail-open.** `Cleaner` checks (`Cleaner.swift:104-118`) then acts
  (`Cleaner.swift:51-62`) on path strings; the kernel resolves intermediate
  components at call time, so swapping an ancestor directory for a symlink in the
  window makes `~/.Trash/x/y` resolve to `~/target/y`. For the `trash` category the
  act is `removeItem` (permanent); if Sweep holds FDA and the attacker does not,
  this is a TCC privilege escalation that deletes protected data under Sweep's
  rights. The leaf check itself is fail-open: `(try? url.resourceValues(...))?.isSymbolicLink`
  (`Cleaner.swift:107-108`) yields `nil` on error and is treated as "not a symlink".
  *Mitigation:* fail closed on lstat errors; for permanent deletion use fd-relative
  `openat(O_DIRECTORY|O_NOFOLLOW)` on the parent then
  `unlinkat(..., AT_SYMLINK_NOFOLLOW)`; for trash, `fstat` the item immediately
  before `trashItem` and abort unless `(st_dev, st_ino)` matches the scan-time
  capture (macOS has no fd-based trash API, so keep the residual window tiny and
  documented).

- **[P1] Root authorization is a short, incomplete denylist, applied at scan time
  only.** `isAllowedLargeFileRoot` (`DiskScanner.swift:351-362`) rejects only
  `~/Library`, `~/.Trash`, `/System`, `/Library`, `/Applications`, `/private`,
  `/bin`, `/usr`, `/etc`, `/var` — it accepts `/` (no listed base matches `/`),
  `/Users`, `/Volumes`, `/dev`, `/home`, `/Network`, `/cores`, and it accepts `~/`
  itself. A user typing `/` in the open panel (or a poisoned default) gets a scan of
  the entire machine (with FDA) whose items are then all refused at clean time by
  `unauthorizedRoot` (`Cleaner.swift:127-131`) — safe today, but a misleading read
  surface and one refactor away from being a deletion primitive. Conversely, the
  `forbiddenPrefixes` list (`Cleaner.swift:81-100`) omits many `~/Library` subtrees
  (`Preferences`, `LaunchAgents`, `Services`, `Spelling`, …) and the cleaner never
  re-applies `isAllowedLargeFileRoot`; a root swapped to one of those paths passes
  every check (`Cleaner.swift:120-131`). `item.root` is trusted as the sole
  boundary (`ScanItem.swift:61-62`) with no identity binding. *Mitigation:* invert
  to an allowlist — a root must be a *strict* descendant of `NSHomeDirectory()`
  (plus explicitly mounted volumes opened by the user), canonicalized, excluding
  protected locations by filesystem identity; store the authorized root as
  `(URL, dev, ino)` and re-verify it at clean time.

- **[P1] Ad-hoc signature, no hardened runtime, notarization only optional, and
  docs teach users to strip quarantine.** `Makefile:24` runs
  `codesign --force --sign -`; there is no entitlements file and no
  `--options runtime`, and `docs/RELEASING.md:63-96` makes Developer ID/notarization
  optional while advising `xattr -d com.apple.quarantine` (`:67-68`) for a tool that
  is granted FDA and deletes files. Without hardened runtime, `DYLD_INSERT_LIBRARIES`
  injection by a same-user process (or a compromised shell profile) runs inside
  Sweep's FDA context and inherits its file access; with an ad-hoc signature there
  is no stable designated requirement for TCC to key on and no Developer ID
  revocation path, so users cannot distinguish official builds from lookalikes using
  the generic bundle id `com.github.davidmolinari.sweep` (`Support/Info.plist:17`).
  Localization assets are equally unprotected: no format-string injection was found
  (filenames are passed as arguments, all four locales declare matching `%@`/`%lld`
  specifiers), but a writable bundle lets an attacker relabel the destructive button.
  *Mitigation:* Developer ID + `--options runtime` (no entitlements, in particular
  never `com.apple.security.cs.allow-dyld-environment-variables` or
  `disable-library-validation`) + notarization/stapling as the *default* release
  path; drop the `xattr` advice; coordinate with `10-oss-release.md`.

- **[P2] `ItemSafety.protected` is dead code; bundles the docs say are never
  proposed are listed and default-selected.** No code path ever constructs
  `.protected` (`ScanItem.swift:31` and readers only; `scanChild` emits `.safe` or
  `.caution(.appRunning)`, `DiskScanner.swift:246-252`), so the cleaner's
  `isProtected` guard (`Cleaner.swift:41`) can never fire. `protectedExtensions`
  (`.app`, `.framework`, `.sparsebundle`, `.photoslibrary`, VM disks, …) is applied
  only in the large-file walk (`DiskScanner.swift:96-102, 410-435`), while
  `scanChildren` lists any child and `defaultSelected: true` pre-selects it for
  Caches/Logs/Trash (`DiskScanner.swift:122-148`). In Trash, `.app`/`.sparsebundle`
  items are permanently deletable, and a Caches child named `*.app`/`*.plugin` is
  one click from the Trash; `SECURITY.md:61-63` overclaims. *Mitigation:* either
  assign `.protected` in `scanChildren` for `protectedExtensions` (and keep them
  unselectable) or scope the SECURITY.md claim to large-file scans; keep the
  extension list.

- **[P2] "Select All" ignores the active filter and selects invisible items.**
  When the "flagged only" filter is active the list shows only caution items
  (`CategoryDetailView.swift:11-13, 73`), but `toggleSelectAll`
  (`AppModel.swift:212-231`) iterates all items and selects only `.safe` ones —
  i.e. it selects the hidden safe items and touches none of the visible ones. The
  status bar shows a selected count, but the confirmation sheet shows no paths, so
  a user reviewing warnings can clean dozens of items they never saw. *Mitigation:*
  scope select-all to `shownItems` (or disable it while filtered) and keep
  protected/caution behavior unchanged.

- **[P2] Permanent deletion has no path review, no undo, no audit trail, and can act
  on a stale snapshot.** `ConfirmCleanView` displays only a count and total size
  (`Sheets.swift:18-24, 49-56`); `removeItem` is irreversible and nothing is logged
  (`Cleaner.swift:52-58`). `PendingClean` snapshots the items at confirmation time
  (`AppModel.swift:233-237`), and a rescan triggered while the sheet is open (the
  `Cmd+R` command is not disabled) replaces every `ScanItem.id`, so
  `removeItems(withIDs:)` (`AppModel.swift:248-251`) silently reconciles nothing and
  the UI can keep showing already-deleted rows; caution classifications (e.g.
  app-running) can also be stale. *Mitigation:* list the first N paths in the
  confirmation; require typed confirmation or local authentication above a threshold
  of items/bytes; append a user-visible audit log; cancel any `PendingClean` when a
  rescan completes and disable scan commands while a confirmation is presented.

- **[P2] Space accounting counts hard links, APFS clones, snapshots and sparse
  bundles as if deletion would free them.** Sizes come from
  `totalFileAllocatedSize`/`fileSize` per path with no `(st_dev, st_ino)` dedup and
  no `st_nlink` check (`DiskScanner.swift:162-191, 254-259`), and
  `Cleaner.Report.freed` sums the scan-time size (`Cleaner.swift:59`). The same
  inode can be listed in two categories (e.g. `~/Library/Caches/Homebrew` via
  Caches and via Developer), removing one hard link frees nothing until the last
  link is gone, APFS clones share blocks, local Time Machine snapshots pin deleted
  blocks, and a mounted `.sparsebundle` cannot be meaningfully reclaimed by deleting
  its backing directory. `SECURITY.md:36` declares incorrect freed-space reporting
  in scope. *Mitigation:* dedup by inode within a scan, surface multi-link files,
  and label the report as an estimate (or compute a conservative delta from
  `volumeAvailableCapacity`) with a snapshots/clones caveat in README/SECURITY.

- **[P2] Fail-open error paths hide TCC/permission problems.** `contentsOfDirectory
  ?? []` and `try?` on children (`DiskScanner.swift:200-204, 243`) mean a
  TCC-denied Desktop/Documents/Downloads scan yields a successful, empty
  "nothing to clean" state (`AppModel.swift:172-183`) with no indication that
  access was refused; the only affordance is a permanent "Open Full Disk Access"
  button (`AppModel.swift:288-291`). Users are pushed toward granting the broadest
  permission (FDA) to fix an unexplained empty list. *Mitigation:* surface
  enumeration errors through `ScanState.failed` with the affected root, and
  distinguish "denied" from "empty".

- **[P2] The release binary ships a destructive self-test and runs a blocking,
  non-cancellable clean on the main actor.** Any local process can invoke
  `Sweep --selftest` (`HeadlessMode.swift:5-63`, wired in `SweepApp.init`,
  `SweepApp.swift:9-12`), which creates and deletes fixtures under
  `~/Library/Caches` and `~/.Trash`; the token namespacing makes collisions
  unlikely, but it is an avoidable destructive surface in shipped builds. Separately,
  `performClean` starts `Task { Cleaner.clean(...) }` from a `@MainActor` method and
  discards the handle (`AppModel.swift:239-263`), so the whole deletion loop runs on
  the main thread and `Task.isCancelled` inside `Cleaner` (`Cleaner.swift:39`) can
  never become true — a large clean freezes the UI with no cancel or progress.
  *Mitigation:* gate `--selftest` behind a compile-time flag or explicit
  environment variable (CI keeps using it); run cleaning off the main actor with a
  retained task handle and cooperative cancellation.

## Recommendations

Ordered by leverage. All are additive; none relaxes an existing check.

1. **Bind authorization to filesystem identity (M).** Extend `ScanItem` with the
   scanned root's `(st_dev, st_ino)` (and the item's own, captured at scan); re-verify
   both immediately before `trashItem`/`removeItem`, aborting on mismatch. This is
   the single change that neutralizes symlink swaps, root replacement, and most
   TOCTOU variants.
2. **Validate roots, not just items (S).** Apply the same `lstat`/`O_NOFOLLOW`
   discipline to every root (`~/Library/Caches`, `~/Library/Logs`, `~/.Trash`,
   developer paths, custom large-file root) at scan *and* clean time; refuse
   symlinked or non-directory roots. Include a check that `~/.Trash` itself is a
   real directory before any permanent deletion.
3. **Replace string denylists with canonical identity checks (S).** Compare
   protected locations via `stat` `(dev, ino)` and case-fold comparisons on
   case-insensitive volumes (or fail closed when the volume's case sensitivity
   cannot be determined). This closes the `~/library`-style bypass.
4. **Allowlist the custom large-file root (S).** Require a strict descendant of the
   user's home (or a volume explicitly selected through the open panel), reject `/`,
   `NSHomeDirectory()` itself, `/Users`, `/Volumes`, `/dev`, `/home`, `/Network`,
   `/cores`, and protected locations; re-validate the persisted `UserDefaults` value
   on load, not only the scan filter.
5. **Make permanent deletion fd-relative (M).** `openat(O_DIRECTORY|O_NOFOLLOW)` the
   parent chain under `~/.Trash`, then `unlinkat(AT_SYMLINK_NOFOLLOW)`; additionally
   re-`fstat` before each deletion. Document the residual `trashItem` window.
6. **Fix distribution identity (S/M).** Developer ID + hardened runtime
   (`--options runtime`) + notarization + stapling as default; no entitlements
   (especially no DYLD/library-validation relaxation); remove the `xattr -d`
   workaround from `RELEASING.md`; verify with `codesign --verify --strict` and
   `spctl -a -vvv -t install`. Coordinate with `10-oss-release.md`.
7. **Selection and confirmation UX (S/M).** Filter-scoped select-all; show paths in
   the empty-trash confirmation; local authentication or typed confirmation for
   large permanent deletions; append-only audit log; invalidate pending cleans on
   rescan.
8. **Honest reporting (M).** Inode dedup within a scan, `st_nlink` awareness,
   snapshot/clone/sparsebundle caveats, and "reported size" wording instead of
   "freed".
9. **Surface access errors (S).** Report TCC/permission failures per root in
   `ScanState.failed` instead of returning an empty success.
10. **Test the boundaries in CI (M).** Add unit/integration tests for: symlinked
    scan root, `~/.Trash` symlink, case-variant root, root swap between scan and
    clean, hard link dedup, item outside root, and permanent-deletion gate. None of
    these requires weakening the current checks — they lock them in. Keep the
    existing `--selftest`.
11. **Operational hardening (S).** Gate `--selftest` out of release builds (env/flag),
    move cleaning off the main actor with a retained `Task` handle, and keep the
    no-shell/no-network CLI property covered by a test.

## References

Files read for this audit (working tree, 2026-09-13, `main`, no commits):

- `Sources/Sweep/Services/Cleaner.swift` (all 140 lines; `refusalReason` 104-134,
  `isDescendant` 136-139, lists 71-100, `removeItem`/`trashItem` 51-62)
- `Sources/Sweep/Services/DiskScanner.swift` (all 531 lines; roots 110-160,
  `scanChildren` 193-233, `scanChild` 235-265, `isAllowedLargeFileRoot` 351-362,
  `walkLargeFiles` 385-451, size 162-191)
- `Sources/Sweep/Models/ScanItem.swift`, `Models/AppModel.swift`,
  `Models/SpaceCategory.swift`, `Models/L10n.swift`
- `Sources/Sweep/HeadlessMode.swift` (`--selftest` 5-63, `--scan` 65-114)
- `Sources/Sweep/SweepApp.swift`, `Views/CategoryDetailView.swift`, `Views/Sheets.swift`,
  `Views/ContentView.swift`, `Views/LargeFilesControls.swift`, `Views/SettingsView.swift`,
  `Views/SidebarView.swift`, `Views/StateViews.swift`, `Views/AboutView.swift`
- `Support/Info.plist`, `Package.swift`, `Makefile`, `.github/workflows/ci.yml`,
  `.gitignore`
- `SECURITY.md`, `docs/RELEASING.md`, `docs/reviews/10-oss-release.md`,
  `Support/Resources/*.lproj/Localizable.strings` (format-specifier review)
- Host checks (read-only): default volume resolves `/users/<u>/librarY`
  case-insensitively, `realpath` preserves the typed case, `~/.Trash` and `/sbin`
  are not symlinks on this machine.
