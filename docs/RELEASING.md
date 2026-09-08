# Releasing Sweep

This is the maintainer checklist for publishing a new version. Nothing here
requires a paid Apple Developer account except the notarization step, which is
optional.

## 1. Prepare the version

1. Make sure the working tree is clean and on `main`, with CI green.
2. Update the version in `Support/Info.plist`:
   - `CFBundleShortVersionString` — marketing version, e.g. `1.0.0`
   - `CFBundleVersion` — build number, monotonically increasing integer
3. Update the version in the `Makefile`:

   ```make
   VERSION = 1.0.0
   ```

4. Move the `Unreleased` entries of `CHANGELOG.md` under a new heading dated
   today, following [Keep a Changelog](https://keepachangelog.com/):

   ```markdown
   ## [1.0.1] - 2026-10-02
   ```

5. Commit the version bump, then tag it:

   ```sh
   git add Support/Info.plist Makefile CHANGELOG.md
   git commit -m "chore: release 1.0.1"
   git tag -a v1.0.1 -m "Sweep 1.0.1"
   git push origin main --tags
   ```

## 2. Build the archive

```sh
make release
```

This runs `make app` (release build, bundle assembly, ad-hoc signature) and
writes two files:

- `dist/Sweep-<version>.zip`
- `dist/Sweep-<version>.zip.sha256`

Verify the checksum:

```sh
cd dist && shasum -a 256 -c Sweep-<version>.zip.sha256
```

Verify the bundle before shipping:

```sh
plutil -lint dist/Sweep.app/Contents/Info.plist
./dist/Sweep.app/Contents/MacOS/Sweep --selftest   # must print 4/4
codesign --verify --deep --strict --verbose=2 dist/Sweep.app
```

## 3. Signing

### Default: ad-hoc

`make app` signs with `codesign --force --sign -`. This is enough for local
use and for users who build from source, but the archive is not notarized, so
Gatekeeper flags downloaded copies. Document the workaround in the release
notes (right-click → Open, or `xattr -d com.apple.quarantine`).

### Optional: Developer ID and notarization

With a paid Apple Developer account you can produce a clean download. Replace
the ad-hoc signing step for the release build only:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <NAME> (<TEAMID>)" \
  dist/Sweep.app

ditto -c -k --keepParent dist/Sweep.app dist/Sweep-<version>.zip

xcrun notarytool submit dist/Sweep-<version>.zip \
  --keychain-profile "<notary-profile>" --wait

xcrun stapler staple dist/Sweep.app
```

Notes:

- Create the `notarytool` keychain profile once with
  `xcrun notarytool store-credentials` (Apple ID, app-specific password, team
  ID). Never commit credentials or put them in the Makefile.
- Notarize the zip, then staple the `.app` and rebuild the zip so the stapled
  ticket is included.
- Hardened runtime requires entitlements if the app ever uses JIT or unsigned
  memory; Sweep does not.

## 4. Create the GitHub release

Using the GitHub CLI:

```sh
gh release create v1.0.1 \
  --title "Sweep 1.0.1" \
  --notes-file <(sed -n '/^## \[1.0.1\]/,/^## \[/p' CHANGELOG.md | sed '$d') \
  dist/Sweep-1.0.1.zip \
  dist/Sweep-1.0.1.zip.sha256
```

Or create the release in the web UI, paste the changelog section as release
notes, and attach both files from `dist/`.

The release notes must include:

- the version and date,
- the changes (from `CHANGELOG.md`),
- the SHA-256 checksum of the zip,
- a note about Gatekeeper if the build is ad-hoc signed.

## 5. After the release

- Confirm the CI badge is green on the tagged commit.
- Download the archive from the release page on a clean machine (or a fresh
  user account) and run `--selftest` once.
- Open the next `Unreleased` section in `CHANGELOG.md` if needed.
