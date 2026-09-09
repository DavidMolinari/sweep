## Summary

<!-- What changes, and why. Link the issue if there is one: "Closes #123". -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Build, packaging, or CI
- [ ] Refactor (no behavior change)

## Testing

<!-- Describe what you ran and what you observed. -->

- [ ] `make app` succeeds
- [ ] `./dist/Sweep.app/Contents/MacOS/Sweep --selftest` reports `0 failures`
- [ ] `./dist/Sweep.app/Contents/MacOS/Sweep --scan <category>` behaves as expected (if the scan code changed)
- [ ] UI changes: screenshot of the app window attached below

## Safety checklist

- [ ] Items are still moved to the Trash with `FileManager.trashItem`; only the Trash category deletes permanently
- [ ] The cleaner still refuses items outside their scan root and refuses symlinks
- [ ] New scan paths or extensions do not weaken the protected-location or sensitive-package rules
- [ ] `caution` items remain unchecked by default and "select all" still selects only `safe` items
- [ ] A guard was added or updated in `--selftest` if the cleaning logic changed

## Docs

- [ ] `README.md` updated (and `README.fr.md`)
- [ ] `CHANGELOG.md` updated under `Unreleased`
- [ ] `THIRD_PARTY_LICENSES.md` updated if a dependency was added (requires prior discussion)
