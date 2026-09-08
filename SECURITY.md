# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |

## Reporting a vulnerability

Please do not open a public issue for security problems.

- Preferred: use GitHub private vulnerability reporting —
  [Security → Report a vulnerability](https://github.com/DavidMolinari/sweep/security/advisories/new).
- Alternative: email `security@example.com` (placeholder — maintainers must
  replace this address with a monitored one before publication).

Include as much as you can: affected version (`Sweep` menu → About, or
`--selftest` output), macOS version, steps to reproduce, and any proof of
concept. If the issue involves file deletion, describe the exact path and
category involved.

You can expect an acknowledgement within 72 hours and a status update at least
every 7 days until the issue is resolved. Please give us reasonable time to
ship a fix before public disclosure; we will credit you in the release notes
unless you prefer otherwise.

## Scope

In scope:

- Bypasses of the cleaner's safety checks: moving to Trash an item outside its
  scan root, permanently deleting anything other than items inside `~/.Trash`,
  following symlinks, or touching protected locations.
- Crashes, data loss, or unexpected file moves caused by Sweep.
- Incorrect reporting of what was deleted or how much space was freed.
- Build, packaging, or bundle integrity issues (Makefile, `Support/Info.plist`).

Out of scope:

- The fact that a disk cleaner moves files or empties the Trash. That is the
  documented purpose of the app.
- Files that remain after cleaning because macOS or another process holds them
  open. The app reports these as failures and leaves them alone.
- Sandboxing: the app runs outside the App Sandbox by design and may request
  Full Disk Access.
- Issues in unreleased, local modifications of the source tree.

## What the app does on disk

Sweep is a local-only utility. It has no networking code, no telemetry, and no
update mechanism. It reads file metadata and sizes to build its reports.

- **Reads:** `~/Library/Caches`, `~/Library/Logs`, `~/.Trash`, a fixed list of
  developer cache paths, and the selected large-file roots (Downloads, Desktop,
  Documents, Movies, Pictures, Music, or a user-chosen folder).
- **Moves:** selected items are moved to the Trash with
  `FileManager.trashItem`. They remain recoverable until the Trash is emptied.
- **Deletes permanently:** only when the Trash category is cleaned, and only
  paths inside `~/.Trash`.
- **Never:** follows symlinks, scans inside project subtrees during large-file
  scans, or proposes sensitive bundles (`.app`, `.framework`, photo libraries,
  VM disks, …).
- **Full Disk Access:** optional. It only widens the readable scope of the
  scan; it does not change deletion behavior.
