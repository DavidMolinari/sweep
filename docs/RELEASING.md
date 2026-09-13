# Releasing Sweep

This is the maintainer checklist for publishing a new version. Nothing here
requires a paid Apple Developer account except the notarization step, which is
optional.

The version lives in exactly one place: `CFBundleShortVersionString` in
`Support/Info.plist`. The Makefile reads it from there and names the archive
accordingly, and the release workflow refuses a tag that does not match it.

## 1. Prepare the version

1. Make sure the working tree is clean and on `main`, with CI green.
2. Update the version in `Support/Info.plist`:
   - `CFBundleShortVersionString` — marketing version, e.g. `1.0.0`
   - `CFBundleVersion` — build number, monotonically increasing integer
3. Move the `Unreleased` entries of `CHANGELOG.md` under a new heading dated
   today, following [Keep a Changelog](https://keepachangelog.com/):

   ```markdown
   ## [1.0.1] - 2026-10-02
   ```

4. Commit the version bump, then tag it:

   ```sh
   git add Support/Info.plist CHANGELOG.md
   git commit -m "chore: release 1.0.1"
   git tag -a v1.0.1 -m "Sweep 1.0.1"
   git push origin main --tags
   ```

5. Pushing a `v*` tag runs `.github/workflows/release.yml`: it checks the tag
   against `Support/Info.plist`, runs `make release`, and uploads the zip, its
   checksum, and the CHANGELOG section as a **draft** release. Review and
   publish the draft. The local steps below are for building or re-building an
   archive by hand.

## 2. Build and verify the archive

```sh
make release
```

The target chains every safety gate and aborts on the first failure:

1. `make app` — release build, bundle assembly, ad-hoc signature. The build is
   attempted **universal** (`swift build -c release --arch arm64 --arch x86_64`)
   and falls back to the host architecture if the cross-compile is unavailable.
2. `--selftest` — the guardrail suite must pass on a case-insensitive
   volume; `case-fold` is skipped on a case-sensitive one.
3. `plutil -lint` on the bundled `Info.plist` and
   `codesign --verify --deep --strict` on the bundle.
4. Archive `Sweep.app`, `LICENSE`, and `README.md` at the zip root, then write
   and re-verify `dist/Sweep-<version>.zip.sha256`.

Artifacts in `dist/`:

- `Sweep-<version>.zip`
- `Sweep-<version>.zip.sha256`

Verify manually if needed:

```sh
lipo -info dist/Sweep.app/Contents/MacOS/Sweep     # arm64 x86_64 (or native)
./dist/Sweep.app/Contents/MacOS/Sweep --selftest   # must print 0 failures
cd dist && shasum -a 256 -c Sweep-<version>.zip.sha256
```

## 3. Signing

### Default: ad-hoc

`make app` signs with `codesign --force --sign -`. This is enough for local use
and for users who build from source, but the archive is not notarized, so
Gatekeeper flags downloaded copies. Point users at right-click → **Open**; never
recommend `xattr -d com.apple.quarantine` for a tool that deletes files.

### Optional: Developer ID and notarization

With a paid Apple Developer account you can produce a clean download. Sign the
bundle built by `make release`, then submit, staple, re-zip, and re-checksum —
the stapled ticket lives inside the `.app`, so any zip built before the staple
step is stale.

```sh
# 1. Sign with Developer ID, hardened runtime, and a secure timestamp.
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <NAME> (<TEAMID>)" \
  dist/Sweep.app

codesign --verify --deep --strict --verbose=2 dist/Sweep.app
codesign -dvv dist/Sweep.app 2>&1 | grep -E "Runtime|Authority"

# 2. Submit the zip (not the bare .app).
ditto -c -k --keepParent dist/Sweep.app dist/Sweep-notarize.zip
xcrun notarytool submit dist/Sweep-notarize.zip \
  --keychain-profile "<notary-profile>" --wait

# 3. Staple the ticket and validate it.
xcrun stapler staple dist/Sweep.app
xcrun stapler validate dist/Sweep.app

# 4. Gatekeeper must accept the app.
spctl -a -vv dist/Sweep.app
# expected: accepted, source=Notarized Developer ID

# 5. Rebuild the final archive from the stapled app and regenerate the checksum.
rm -f dist/Sweep-<version>.zip dist/Sweep-<version>.zip.sha256 dist/Sweep-notarize.zip
rm -rf dist/release
mkdir -p dist/release
ditto dist/Sweep.app dist/release/Sweep.app
cp LICENSE README.md dist/release/
ditto -c -k --norsrc dist/release dist/Sweep-<version>.zip
cd dist && shasum -a 256 Sweep-<version>.zip > Sweep-<version>.zip.sha256
```

Notes:

- Create the `notarytool` keychain profile once with
  `xcrun notarytool store-credentials` (Apple ID, app-specific password, team
  ID). Never commit credentials or put them in the Makefile.
- Hardened runtime is enabled by `--options runtime`.
- Sweep needs **no entitlements**. It has no third-party dylibs, no JIT, and no
  unsigned executable memory, so it does **not** need
  `com.apple.security.cs.disable-library-validation` or any other exception.
- `stapler validate` must print “The validate action worked!” before the
  archive is published.

## 4. Publish the release

The tag workflow creates a draft release; finish it in the web UI. To create or
re-create it from the command line:

```sh
gh release create v1.0.1 \
  --title "Sweep 1.0.1" \
  --notes-file <(sed -n '/^## \[1.0.1\]/,/^## \[/p' CHANGELOG.md | sed '$d') \
  dist/Sweep-1.0.1.zip \
  dist/Sweep-1.0.1.zip.sha256
```

The release notes must include:

- the version and date,
- the changes (from `CHANGELOG.md`),
- the SHA-256 checksum of the zip,
- a Gatekeeper note if the build is ad-hoc signed (right-click → **Open**),
  and, when the build is not universal, the architecture it supports.

## 5. After the release

- Confirm the CI badge is green and the release workflow succeeded on the
  tagged commit.
- Download the archive from the release page on a clean machine (or a fresh
  user account), verify `shasum -a 256 -c`, and run `--selftest` once.
- Verify the Full Disk Access story on a machine **without** the permission:
  `~/.Trash` and other TCC-protected folders must report an explicit failure
  with the **Open Full Disk Access…** button, never an empty result.
- Open the next `Unreleased` section in `CHANGELOG.md` if needed.
