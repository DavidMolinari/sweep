# 10 — Open Source & Release Engineering

Context: Sweep 1.0.0 is a dependency-free SwiftUI/SPM macOS 14+ disk cleaner intended
for public release under MIT at `github.com/DavidMolinari/sweep`. This read-only review
covers license compliance, community files, packaging, signing/notarization,
distribution, CI, versioning, and governance. No build, signing, or release command was
run; findings cite the working tree as reviewed on 2026-09-13.

## Findings

- **[P0] Placeholder contact addresses in published policies** — `SECURITY.md:15-16`,
  `CODE_OF_CONDUCT.md:3-5,66-67` — Both community policies ship dead addresses
  (`security@example.com`, `conduct@example.com`) and even carry visible "replace before
  publication" notes. A published security policy with an unroutable reporting channel is
  the first thing reviewers and security researchers will flag, and it undermines the
  otherwise strong safety documentation. Replace both with monitored addresses (aliases
  are fine), delete the maintainer notes, and verify GitHub private vulnerability
  reporting is enabled as the primary channel.

- **[P0] Repository is not publishable in its current state** — repository state (no
  commits, no remote, no tags) — `git status` reports "No commits yet" on `main`,
  `git remote -v` is empty, and no tag exists, while `README.md:13,51`,
  `AboutView.swift:23`, and `.github/ISSUE_TEMPLATE/config.yml:3-7` all assume
  `github.com/DavidMolinari/sweep` is live. The CI badge, clone instructions, the About
  window link, and the security-advisory URL are all 404 until the repo exists publicly.
  Create the initial commit, push to the public repository, then tag `v1.0.0` before
  announcing anything.

- **[P1] Ad-hoc signing only; the release will be stopped by Gatekeeper** — `Makefile:24`
  (`codesign --force --sign -`), `README.md:80-82`, `docs/RELEASING.md:63-96` — The
  archive is not Developer ID-signed, not notarized, and ships without hardened runtime.
  For a utility that asks users to grant Full Disk Access and then moves/deletes files,
  an unsigned download is the single biggest credibility gap; the documented
  `xattr -d com.apple.quarantine` workaround makes it worse because it trains users to
  strip a security control from a file-deletion tool. Ship v1.0 with Developer ID +
  hardened runtime + notarization + stapled ticket if at all possible; otherwise lead the
  release notes with the Gatekeeper caveat, recommend right-click → Open instead of
  `xattr`, and label the asset "unsigned / Apple Silicon" explicitly.

- **[P1] Distributed binary is arm64-only while the project claims macOS 14+** —
  `Makefile:9,15`, `README.md:44`, `Support/Info.plist:33` — `swift build -c release`
  builds the host architecture; the artifact in `dist/Sweep.app` is a Mach-O thin arm64
  executable, and the CI runner (`ci.yml:21`) is also arm64. Intel Macs capable of running
  Sonoma cannot run the published zip, and the README does not say so. Either build
  universal (`swift build -c release --arch arm64 --arch x86_64`, copying from
  `.build/apple/Products/Release/`) or document "Apple Silicon only" in the README,
  release body, and asset name, and add a `lipo -info` check to the release procedure.

- **[P1] Notarization runbook is incomplete and would ship an unstapled zip** —
  `docs/RELEASING.md:70-96` — The snippet signs, zips, submits, then staples the `.app`
  (`:85`) but never rebuilds the zip after stapling, contradicts its own note at `:93-94`,
  never runs `stapler validate` / `spctl -a -vvv -t install` / `codesign --verify`, and
  says nothing about entitlements. A maintainer following it literally publishes a zip
  without the staple, with no post-hoc verification. Fix the sequence (sign → zip →
  submit → staple → re-zip → regenerate SHA-256 → verify), and state explicitly that Sweep
  needs **no entitlements** and specifically does **not** need
  `com.apple.security.cs.disable-library-validation` (no third-party dylibs, no JIT, no
  unsigned memory; RELEASING already hints at this at `:95-96`).

- **[P2] No tag-triggered release workflow or build provenance** —
  `.github/workflows/ci.yml:3-7,40-53` — CI runs only on `main` pushes and PRs, packages
  an ad-hoc zip on every run, and uploads it as `Sweep-macos`; releases (`v1.0.1`, …) are
  built locally with no verifiable provenance. Add a `release.yml` triggered by `v*` tags
  that rebuilds, runs `--selftest`, packages, checksums, optionally signs/notarizes from
  protected environment secrets, generates a provenance attestation
  (`actions/attest-build-provenance`), and creates the GitHub release from the CHANGELOG
  section. Restrict the current CI artifact to `main` so a CI dump is never mistaken for a
  release.

- **[P2] Distribution is zip-only; no Homebrew cask or DMG** — `Makefile:40-45`,
  `docs/RELEASING.md:35-51` — A zip + SHA-256 is fine as the canonical asset, but macOS
  users expect `brew install --cask sweep`, and there is no install story beyond
  `make install` for non-developers. After notarization, publish a cask (homebrew/cask or
  a project tap) in v1.1; a DMG adds little for this app and can be skipped. Document the
  checksum verification command for manual downloads.

- **[P2] Version is duplicated across four places with no consistency check** —
  `Makefile:2`, `Support/Info.plist:28-31`, `CHANGELOG.md:8`,
  `docs/RELEASING.md:8-31` — `VERSION`, `CFBundleShortVersionString`, `CFBundleVersion`,
  and the changelog heading are edited by hand; drift is likely by v1.0.2 and would make
  the About window (`AboutView.swift:11-21`) misreport the shipped build. Make the
  Makefile `VERSION` the single source and inject it into the bundle at `make app` time
  (PlistBuddy/`plutil`), or add a `make check-version` guard that fails when they diverge.

- **[P2] MIT notice is not in the shipped archive** — `LICENSE:1-3`,
  `Makefile:40-45`, `AboutView.swift:151-161` — The license text is compiled into the
  About sheet, which arguably satisfies MIT's notice requirement for the binary, but the
  zip contains only `Sweep.app` and source files carry no SPDX identifiers. Copy
  `LICENSE` and `THIRD_PARTY_LICENSES.md` into `Contents/Resources/` (or at the zip root)
  and add a one-line SPDX header to each source file; this is exactly the kind of thing
  license scanners check.

- **[P2] Governance is undefined** — `CONTRIBUTING.md:6-11,121-123` — There is no
  `CODEOWNERS`, no maintainer/ownership section, and only a bare "contributions licensed
  under MIT" statement; there is no DCO sign-off convention. For a single-maintainer
  project this is low-risk, but reviewers expect ownership and contribution provenance to
  be explicit. Add `.github/CODEOWNERS`, a short Maintainers section to the README, and
  adopt DCO sign-off (`git commit -s`) in CONTRIBUTING; no CLA is needed for MIT.

- **[P2] Issue/PR intake has broken or unconfigured links** —
  `.github/ISSUE_TEMPLATE/bug_report.yml:13` (relative `../security/policy` resolves
  outside the template directory), `.github/ISSUE_TEMPLATE/config.yml:7` (Discussions URL),
  and the `bug`/`triage`/`enhancement` labels in both templates — The security escalation
  link is broken, the Discussions link 404s until Discussions is enabled, and labels are
  silently dropped if they do not exist in the repo. Use absolute URLs
  (`https://github.com/DavidMolinari/sweep/security/policy`), enable Discussions and
  private vulnerability reporting, and create the labels as part of the repo setup.

- **[P2] `make release` skips the safety gates it documents** — `Makefile:40-45` vs
  `docs/RELEASING.md:53-59` — The release target does not run `--selftest`, `plutil
  -lint`, or `codesign --verify`; the runbook asks the maintainer to run them manually
  after packaging. A release with a failing self-test or an invalid signature is therefore
  one forgotten command away. Wire the checks into `release` (fail the target on any
  failure) and leave only the upload/notarization steps manual.

- **[P2] CI supply-chain and architecture hygiene** — `.github/workflows/ci.yml:26,47` —
  Actions are pinned to floating major tags (`actions/checkout@v4`,
  `actions/upload-artifact@v4`) rather than commit SHAs, and there is no Intel or
  cross-arch build job, so the arm64-only artifact goes unnoticed. Pin actions by SHA
  (Dependabot can keep them current) and add an x86_64 cross-build smoke check to catch
  architecture regressions. `permissions: contents: read` (`:13-14`) and the
  `concurrency` block (`:9-11`) are already correct; no secrets are used, and no cache is
  needed because there are no dependencies.

## Recommendations — release roadmap

**v1.0 gate (before the repo goes public) — S/M**

1. Replace both placeholder emails with monitored addresses and remove the maintainer
   notes; enable private vulnerability reporting and Discussions; create the issue labels
   and fix the relative security link. (S)
2. Make the signing decision explicit: Developer ID + hardened runtime + notarization +
   staple for a clean download, or an "unsigned, Apple Silicon only" release with
   right-click → Open guidance and no `xattr` recommendation. (M–L, external Apple
   account dependency)
3. Fix the notarization runbook end-to-end (re-zip after staple, `stapler validate`,
   `spctl`, `codesign --verify`, checksum regeneration) and document that no entitlements,
   including `disable-library-validation`, are required. (S)
4. Either build universal or label the artifact and README "Apple Silicon"; record the
   `file` / `lipo -info` verification in the release checklist. (S–M)
5. Make `make release` run `--selftest`, `plutil -lint`, and `codesign --verify --deep
   --strict`; copy `LICENSE`/`THIRD_PARTY_LICENSES.md` into the archive. (S)
6. Single-source the version; add CODEOWNERS, a Maintainers section, and DCO sign-off;
   complete repository metadata (description, topics, social preview, branch protection
   requiring CI, tag protection). (S)
7. Initial commit, push to `github.com/DavidMolinari/sweep`, tag `v1.0.0`, verify the CI
   badge and all links from a logged-out browser. (S)

**v1.1 — S/M**

8. Add a tag-triggered `release.yml` with provenance attestation, notarization via
   protected environment secrets, automated release notes from the CHANGELOG, and
   SHA-pinned actions; restrict the CI artifact to `main`. (M)
9. Publish a Homebrew cask once the build is notarized; keep zip + SHA-256 as the
   canonical asset. (M)
10. Add an x86_64/universal build check to CI and consider a second runner label to cover
    both architectures. (S)

## References

- `LICENSE`, `THIRD_PARTY_LICENSES.md`, `README.md`, `README.fr.md`, `DESIGN.md`
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CHANGELOG.md`
- `Makefile`, `Package.swift`, `Support/Info.plist`, `Support/Branding/generate-icon.swift`
- `docs/RELEASING.md`, `docs/assets/` (screenshots)
- `.github/workflows/ci.yml`, `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/ISSUE_TEMPLATE/{config,bug_report,feature_request}.yml`
- `Sources/Sweep/HeadlessMode.swift`, `Sources/Sweep/Views/AboutView.swift`
- Working-tree inspection: `git status`/`git remote -v`/`git tag -l`, `file` and
  `codesign -dvvv` on the generated `dist/Sweep.app` (read-only; no build performed)
