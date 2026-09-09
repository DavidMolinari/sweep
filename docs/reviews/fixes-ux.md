# UI / UX / Accessibility fixes

Scope: `Sources/Sweep/Views/**`, `Support/Resources/*.lproj/Localizable.strings`,
`Sources/Sweep/Models/L10n.swift`. Services and core models are intentionally untouched;
items that require core changes are listed under "Waiting on core" below.

## P0

### 1. Return no longer triggers permanent deletion — `Views/Sheets.swift:56`

`ConfirmCleanView` only applies `.keyboardShortcut(.defaultAction)` when the pending clean
is *not* permanent (`permanent ? nil : .defaultAction`). In the "Empty the Trash?" sheet no
button owns Return; the explicit click is required. Cancel keeps
`.keyboardShortcut(.cancelAction)`, so Escape still dismisses. The recoverable
"Move to Trash" sheet keeps Return as its default action.

### 2. Row state is exposed to VoiceOver — `Views/CategoryDetailView.swift:224-370`

- Each `ItemRow` is now an explicit accessibility element
  (`.accessibilityElement(children: .ignore)`), with:
  - label = file name;
  - value = selection/safety state + size + modified date, e.g.
    "Not selected, Flagged item, 830 MB, 5 Feb 2026" (keys `a11y.selected`,
    `a11y.notSelected`, `a11y.protected`, `safety.caution.label`);
  - hint = caution message, protected explanation (`safety.protected.help`) or
    `a11y.toggle.hint`;
  - `.isSelected` trait when checked;
  - named actions "Reveal in Finder" and "Copy Path".
- Protected rows are no longer `.disabled(!isSelectable)` and no longer dimmed by a
  whole-row `.opacity(0.72)`; they stay focusable and the refusal is conveyed by the
  value/hint. The checkbox and safety badge are decorative (`.accessibilityHidden(true)`)
  because the row value already carries the state.
- The flagged filter picker gets an explicit `.accessibilityLabel("filter.title")`
  (`Views/CategoryDetailView.swift:97`).

## P1

### 3. Caution contrast in light mode — `Views/BrandPalette.swift`, `Views/CategoryDetailView.swift`, `Views/StateViews.swift`

New token `BrandPalette.Semantic.caution = adaptive(0xB45309, 0xFF9F0A)` (dark amber in
light mode, system orange in dark). Applied to: inline caution sentence, warning badge
glyph + circle fill, flagged capsule label/fill in the CleanBar, the FailureView retry
button and the partial-scan banner. Contrast of `#B45309` on white is ~5.0:1 (AA for small
text); dark-mode orange on the dark window stays ~8:1, unchanged. The modified date moved
from `.tertiary` to `.secondary`, the unchecked checkbox border from
`Color.secondary.opacity(0.45)` to solid `Color.secondary`, and the caution line from
`.caption2` to `.caption`.

### 4. Reduce Motion — `Views/DesignSystem.swift:115-140` + all animated views

`SpinningRing` reads `@Environment(\.accessibilityReduceMotion)` and renders the static
30% arc (no `repeatForever`) when the setting is on. Numeric `contentTransition`s and
`.animation` calls in `CategoryHeader`, `ItemRow`, `CleanBar`, `ScanningView` and
`SidebarRow` are gated on the same environment value; checkbox/hover springs are
disabled. Animation durations were also tightened to the documented <0.25 s budget
(`.snappy(duration: 0.2)`, spring `response: 0.22`).

### 5. `filter.title` — all four `Localizable.strings`

Added `"filter.title"` = Show / Afficher / Anzeigen / Mostrar. All four files remain in
strict key parity (150 keys each, no duplicate keys, identical format specifiers).

### 6. Select-all semantics — `Views/CategoryDetailView.swift:412-460`

The button label is now driven by `allSelected` = every *selectable* item is checked:

- flagged items present, not everything checked → `cleanbar.selectSafe`
  ("Select Safe Items");
- every selectable item checked → `action.deselectAll`;
- nothing flagged → `action.selectAll`.

A persistent caption `cleanbar.selectAll.warningNote` ("Flagged items stay unchecked")
is shown next to the button whenever `flaggedCount > 0 && !allSelected`, so the safety
rule is no longer hover-only. The flagged capsule and the warning count use the new
caution token.

Waiting on core: the additive `toggleSelectAll` behaviour. With the current model, pressing
"Select Safe Items" after manually checking a flagged item clears that flagged check, and
there is no one-click way to clear a safe-only selection. See "Waiting on core" #3.

### 7. Partial scan results UI — `Views/StateViews.swift:102-147`, `Views/CategoryDetailView.swift:75-90`

New `PartialScanBanner`: a discreet, non-blocking strip above the list with the localized
title `scan.partial.title` ("Some locations were skipped"), the message supplied by the
model, a "Open Full Disk Access…" action and "Try Again". It is rendered when
`result.state == .failed(message)` **and** items are present; a `.failed` state with an
empty list still shows the full `FailureView`. No new model API is invented; see
"Waiting on core" #2 for the data the banner needs to be reachable.

### 8. Cleaning state

Not implementable in this worktree: `AppModel` (this branch) has no `isCleaning` field and
`performClean` closes the sheet immediately. No view code was written against a
non-existent API. See "Waiting on core" #1 for the expected shape.

## P2 quick wins

- **Settings window** (`Views/SettingsView.swift`): fixed `560×430` replaced by
  `minWidth: 540, idealWidth: 560, minHeight: 420, idealHeight: 430`; the selected tab is
  persisted with `@AppStorage("settings.selectedTab")`; the redundant "About" pane was
  removed — the custom About window (app menu) is the single About surface. Note: full
  per-pane resizing needs `.windowResizability(.contentMinSize)` on the `Settings` scene
  in `SweepApp.swift`, which is outside the allowed scope.
- **Duplicated title** (`Views/CategoryDetailView.swift`): the card no longer repeats
  `category.title`; the window/navigation title remains the single page title and the card
  keeps the icon, root/subtitle and totals.
- **Glass in the content layer** (`09 P1-4`): `CategoryHeader` and `LargeFilesControls` now
  use the flat `contentSurface()` treatment (4.5 % primary fill + hairline) instead of
  material + extra gradient; the sidebar footer no longer stacks `.ultraThinMaterial` over
  the sidebar. Material is kept only for the floating `CleanBar`.
- **Tokens** (`09 P2-1`): hardcoded radii replaced with `BrandPalette.Radius`
  (`Radius.inset/chip/field/card`) in the sidebar, rows, sheets and controls; hardcoded
  `.orange` replaced with the caution token.
- **Empty state** (`Views/StateViews.swift`): the idle message no longer repeats the header
  subtitle; it now states the safety model (`empty.notScanned.message`: "Checked items are
  moved to the Trash — nothing is erased, except when you empty the Trash.").
- **Keyboard**: the Cancel button in `ScanningView` has `.keyboardShortcut(.cancelAction)`
  so Escape cancels the visible scan.
- **Large Files controls**: labelled the reset-folder icon button
  (`accessibilityLabel`), flexible picker width, controls disabled while scanning.
- **Typography**: `@ScaledMetric` for the hero byte counters in `CategoryHeader`; caution
  text raised to `.caption`.

## Waiting on core (other agent)

1. **`isCleaning` (P1-8)** — Expected: a per-category published set/flag, e.g.
   `@Published var cleaning: Set<SpaceCategory>` or `func isCleaning(_ category:) -> Bool`,
   set around `Cleaner.clean`. When present, the CleanBar should disable Scan/Clean/select-all
   while cleaning and show an in-place `ProgressView` + `items removed / total` text; the
   Clean button's disable condition is currently
   `result.selectedItems.isEmpty || result.state == .scanning` and just needs
   `|| model.isCleaning(category)`.
2. **Partial scan status (P1-7)** — `DiskScanner` should surface skipped/permission-denied
   locations (e.g. `skippedCount` + first error in its output). If `AppModel` keeps the
   partial items and sets `ScanState.failed(message)` (or a new `.partial(message)` case),
   the banner becomes reachable with zero extra view work. If a new `.partial` case is
   added, `CategoryDetailView.content(for:)` needs one more `case` mapping to the same
   banner. A `cancelled`-with-results path should also keep items; the banner copy is
   generic enough.
3. **`toggleSelectAll` (P1-6)** — Expected semantics: additive (only sets safe items to
   `true`, never clears a manual check); when every selectable item is selected it clears
   all. The current implementation (`AppModel.swift:212-231`) still resets flagged items and
   can be a no-op after the safe set is checked. The view intentionally does **not** show
   "Deselect All" while only the safe set is checked, per the fix spec — a model-side way
   to clear a safe-only selection in one press is required for that state.
4. **Report sheet escape** (`08 P2`) — `CleanReportView` Close is still Return-only; adding
   `.keyboardShortcut(.cancelAction)` is a one-line change in `Sheets.swift` that was left
   out of this pass to keep the diff scoped.
5. **FDA link always visible** (`09 P2-11`) — hiding the sidebar footer link once Full Disk
   Access works requires a probe in the core.

## Not done (out of scope)

- Dock/About icon: `Support/Branding/**` is off-limits, nothing changed.
- Brand accent resolution (`09 P1-3`): the actionable colour still follows the user's
  system accent. Pinning an `AccentColor` asset or deleting the dead `Brand` tokens is a
  design decision for the owner.
- Increased-contrast variants (`09 P2-6`) for custom colors: only light/dark variants are
  defined.

## Verification

- `swift build -c release`: clean, zero warnings.
- `make app` then `./dist/Sweep.app/Contents/MacOS/Sweep --selftest`: exit 0.
- Localization: 150 keys in each of EN/FR/DE/ES, no missing/extra/duplicate keys, identical
  format specifiers (script-checked).
- Visual: main window, flagged/protected rows, caution text, CleanBar and both confirmation
  sheets captured in light and dark appearance via a temporary harness that reuses these
  view files with seeded data (the real binary was only launched and captured, never
  clicked; no scan was triggered from the UI).
