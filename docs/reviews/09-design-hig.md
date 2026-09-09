# 09 — Design System & HIG Consistency

Read-only expert review of Sweep's visual layer: `DesignSystem.swift`, `BrandPalette.swift`,
`DESIGN.md`, the icon generator and every SwiftUI view, checked against `DESIGN.md` (the
declared single source of truth) and the Apple Human Interface Guidelines, including the
2025/2026 Liquid Glass materials guidance. macOS 14 deployment target, four locales
(EN/FR/DE/ES). Severity: P0 = user-blocking or safety, P1 = documented HIG/own-rule
violation with visible impact, P2 = polish and consistency debt.

## Findings

### P0 — None
No release-blocking design defect found. The safety-critical visual language (no pre-selected
destructive subset, explicit confirmation, protected rows locked) holds up.

### P1-1 · Reduce Motion is not honored by the only continuous animation
**Where:** `Sources/Sweep/Views/DesignSystem.swift:115-135` (`SpinningRing`), used at
`Sources/Sweep/Views/StateViews.swift:49`, `Sources/Sweep/Views/CategoryDetailView.swift:132`,
`Sources/Sweep/Views/SidebarView.swift:87`. No `accessibilityReduceMotion` is read anywhere
in the target.
**Rule:** HIG Accessibility > Motion — *"When this setting is active, ensure your app responds
by reducing automatic and repetitive animations, including zooming, scaling, and peripheral
motion."* `DESIGN.md:222-224` explicitly promises: *"Respect Reduce Motion: `SpinningRing` is
the only continuous animation and should be replaced by a static track when
`accessibilityReduceMotion` is on."*
**Gap:** The ring spins forever (line 130) regardless of the system setting; the promise is
unimplemented.
**Recommendation:** read `@Environment(\.accessibilityReduceMotion)` in `SpinningRing` and
render the static track only (drop the trimmed arc + `repeatForever`), and use
`.animation(reduceMotion ? nil : ...)` for state transitions.

### P1-2 · Permission failures are rendered as "Nothing to clean"
**Where:** `Sources/Sweep/Models/AppModel.swift:172-183` always sets `.done` (only cancellation
is special-cased); `Sources/Sweep/Services/DiskScanner.swift:110-160` never returns an error or
sets `ScanState.failed`; `Sources/Sweep/Views/StateViews.swift:71-97` (`FailureView`) is
unreachable dead UI. A denied read (e.g. missing Full Disk Access) yields an empty list, which
`CategoryDetailView.swift:68-71` routes to the success-flavored `EmptyStateView`
("Nothing to clean — No items found in this category.").
**Rule:** HIG Feedback — communicate status accurately and give people a way to recover; HIG
Empty states — an empty result must be truthful, not a substitute for an error. The app itself
admits partial coverage in `Support/Resources/en.lproj/Localizable.strings:154`: *"Without it,
some locations are skipped."*
**Gap:** A user who never granted Full Disk Access sees a reassuring "Nothing to clean" for
protected folders — the worst possible outcome for a disk cleaner.
**Recommendation:** have `DiskScanner` report skipped/permission-denied roots, propagate a real
`.failed` (or a "partial" state), show `FailureView` with a "Grant Full Disk Access" action,
and mark partial results distinctly in `CategoryHeader`.

### P1-3 · The brand accent is dead code; the actionable color is the user's system accent
**Where:** `Sources/Sweep/Views/BrandPalette.swift:33-48` — `Brand.deep/midnight/indigo/violet/
ice/halo/primary/primaryDeep/signature` have zero call sites in the target. Everything
interactive uses `.accentColor` (`CategoryDetailView.swift:305,354,431`, `Sheets.swift:55`),
which macOS resolves to the user-chosen system accent (graphite, pink, …).
**Rule:** HIG Color — use color to communicate and be judicious with color in controls; Liquid
Glass guidance (*Adopting Liquid Glass*) — *"Review your use of color in controls … leverage
system colors, or define a custom color with light and dark variants, and an increased contrast
option for each variant."* `DESIGN.md:41,91` claims `primary #1F6BFA` *"matches the system accent
used by buttons"*.
**Gap:** Selecting rows, the selection circle, the primary Clean button and the danger button
tint all change with the OS accent; the documented "one clear accent" and the icon's
indigo/violet identity (Support/Branding/icon-1024.png) do not match the shipped UI. The brand
tokens are unmaintained drift waiting to happen.
**Recommendation:** either delete the dead `Brand` tokens and rewrite `DESIGN.md` §3.1 to state
that the system accent is authoritative, or add an asset-catalog `AccentColor` (#1F6BFA light +
dark + increased-contrast variants) and use it, so the accent is brand-pinned and still
adapts. Decide once; do not keep both stories.

### P1-4 · Glass/material used in the content layer, layered on more translucency
**Where:** `Sources/Sweep/Views/CategoryDetailView.swift:153` (static header card gets
`glassSurface`), `:155-163` (a second gradient layer behind it), `:440` (`CleanBar` uses
`.ultraThinMaterial`), `Sources/Sweep/Views/SidebarView.swift:58` (footer material inside an
already-glassy sidebar), `Sources/Sweep/Views/LargeFilesControls.swift:50-57` (another material
panel with a different stroke).
**Rule:** HIG Materials — *"Don't use Liquid Glass in the content layer … use standard materials
for elements in the content layer"*; WWDC25 "Meet Liquid Glass" — *"always avoid glass on
glass"*; *Adopting Liquid Glass* — *"Reduce your use of custom backgrounds in controls and
navigation elements … prefer to remove custom effects and let the system determine the
background appearance."* `DESIGN.md:168-169` states the project's own rule: glass is
*"reserved for panels that float over content (sheets, consoles). Content areas stay plain."*
**Gap:** The header card is in the layout flow, not floating, and stacks material + gradient +
colored shadow + gradient tile + glow. The sidebar footer stacks material on the sidebar
material. The result is the "busy chrome" the brand says it avoids.
**Recommendation:** keep one elevation language. Flatten `CategoryHeader` to a subtle
`Color.primary.opacity(0.04)` fill (or a single `glassSurface` without the extra gradient
background), drop the footer's custom material in favor of the sidebar's system surface, and
unify `LargeFilesControls` with the same container style as the header. Restrict glass to
sheets, the CleanBar and (optionally) nothing else.

### P1-5 · Destructive button combines "destructive style" and "default button"
**Where:** `Sources/Sweep/Views/Sheets.swift:49-57` — the permanent-deletion confirm button has
`.buttonStyle(.borderedProminent)` + `.tint(.red)` + `.keyboardShortcut(.defaultAction)`, so
Return empties the Trash. `CategoryDetailView.swift:429-435` uses the same red prominent
treatment.
**Rule:** HIG Buttons — *"Don't assign the primary role to a button that performs a destructive
action, even if that action is the most likely choice."* HIG Alerts carves out exactly this
case: when people deliberately choose a destructive action such as Empty Trash, *"the alert
doesn't apply the destructive style to the Empty Trash button … the convenience of pressing
Return to confirm … outweighs the benefit of reaffirming."*
**Gap:** The implementation does both halves of the contradictory pair — red destructive styling
*and* Return-as-default. For an irreversible, non-recoverable action this is the one place where
the app's "danger is explicit" promise (`DESIGN.md:174-175`) must translate into HIG mechanics.
**Recommendation:** pick one consistent model. Safest: keep the red tint but move the
`.defaultAction` shortcut to Cancel (and consider `.keyboardShortcut(.cancelAction)` on
Escape). If you prefer Apple's Empty Trash precedent, keep Return but drop the red tint from
the default button and rely on the sheet's copy. Apply the same choice in `ConfirmCleanView`
and `CleanBar`.

### P1-6 · Preferences window is force-sized and skips three explicit Settings behaviors
**Where:** `Sources/Sweep/Views/SettingsView.swift:6-16` — `TabView` in a fixed
`.frame(width: 560, height: 430)`, no persisted selection, no per-pane sizing, plus an About
pane (`:13-14`, `:193-236`) that duplicates `AboutView`.
**Rule:** HIG Settings — *"Dim a settings window's minimize and maximize buttons … because a
settings window accommodates the size of the current pane"*; *"Update the window's title to
reflect the currently visible pane"*; *"Restore the most recently viewed pane."* HIG The menu
bar — the About menu item *"Displays the About window … which includes copyright and version
information"* (i.e. About is not a settings pane; no system app ships one).
**Gap:** Fixed frame contradicts per-pane accommodation and will feel cramped or empty
depending on the pane; larger accessibility text sizes and long DE/FR strings are constrained.
The window always reopens on General and the title never follows the pane.
**Recommendation:** let each pane size intrinsically (`.fixedSize()` / pane-specific max widths,
`.formStyle(.grouped)` already handles the rest), persist tab selection with `@AppStorage`
(restore last pane), remove the About pane and keep the About window as the single About
surface, and consider macOS 15+ `Tab` initializers when the target allows it so the tab bar
picks up the Tahoe look automatically.

### P2-1 · Radius and semantic-color tokens exist but are bypassed
**Where:** `BrandPalette.swift:110-116` defines `Radius.inset/chip/field` (7/10/12) — no call
sites; the code hardcodes the same values at `SidebarView.swift:36` (7), `Sheets.swift:40`
(12), `Sheets.swift:102` (10), `CategoryDetailView.swift:275` (10),
`CategoryDetailView.swift:153,155` (18 instead of `Radius.card`),
`LargeFilesControls.swift:51,55` (12). `Semantic.warning`/`danger` are used only inside
medallions; warning affordances hardcode `.orange` (`CategoryDetailView.swift:250,342,345,
394,398`, `StateViews.swift:93`) and destructive ones hardcode `Color.red`
(`Sheets.swift:29,34,41`, `CategoryDetailView.swift:431`). `SpaceCategory.tint`
(`SpaceCategory.swift:42-50`) is dead. `DesignSystem.swift:125` uses `Color.primary` where
`DESIGN.md:142` documents the `primary` token at 8 %.
**Impact:** the design system is descriptive, not enforcing; every future tweak forks.
**Recommendation:** replace the literals with the tokens (`Radius.*`, `Semantic.warning/
danger`); either use or delete `SpaceCategory.tint`; fix the `SpinningRing` track token
reference in either code or doc.

### P2-2 · Typography drifts from `DESIGN.md` §4
**Where:** `CategoryDetailView.swift:249` sets caution text to `.caption2` (below the
`DESIGN.md:159` rule *"Never set text below `.caption`"*); fixed point sizes at
`CategoryDetailView.swift:174,185` (24/30 pt `design: .rounded`) and `AboutView.swift:53`
(23 pt) do not follow text styles and won't scale; `DESIGN.md:155` says byte counts are
`.callout`/`.title3` monospaced, but the header uses custom rounded sizes and the sidebar
counter uses `.caption` (`SidebarView.swift:90`).
**Impact:** inconsistent numeral voice across sidebar, header, rows; Dynamic Type / text-size
users get a frozen hierarchy.
**Recommendation:** use `.title`/`.largeTitle` with `.monospacedDigit()` for the hero counters,
lift caution text to `.caption`, and document the rounded-numeral decision in `DESIGN.md` if it
is intentional.

### P2-3 · The category title is shown twice
**Where:** `CategoryDetailView.swift:42` (`.navigationTitle(category.title)`) and
`:138-139` (same title inside the header card), 90 px apart in the unified toolbar; visible in
`docs/assets/sweep-light.png` and `docs/assets/sweep-dark.png`.
**Impact:** redundant hierarchy at the top of every screen; the card's title competes with the
window title instead of supporting it.
**Recommendation:** keep the window/navigation title and strip the title from the card (keep
subtitle + totals), or set the window title to "Sweep" and keep the card title. Refresh the
screenshots when done.

### P2-4 · Row selection is a custom checkbox without an accessibility value; contrast is stacked down
**Where:** `CategoryDetailView.swift:300-325` draws the checkbox by hand; the row
(`:229-298`) is a `.plain` Button exposing only its concatenated text. Locked rows get
`:282` `.opacity(0.72)` on top of secondary text, and the unchecked circle uses
`:307` `Color.secondary.opacity(0.45)`.
**Rule:** HIG Accessibility — convey state programmatically, don't rely on color alone, ensure
sufficient contrast (WCAG 1.4.11 wants ~3:1 for control boundaries; 45 % secondary easily
falls short).
**Impact:** VoiceOver never announces "selected / not selected"; low-vision users may not
perceive the only selection affordance; locked rows become hard to read.
**Recommendation:** add `.accessibilityValue(...)` (or use a real `Toggle` styled with
`.toggleStyle(.checkbox)` / custom `ToggleStyle`), raise the circle border to a solid
secondary, and avoid cumulative opacity on disabled rows.

### P2-5 · Dates use `.tertiary` for decision-relevant data
**Where:** `CategoryDetailView.swift:259-263` renders the modification date in `.caption`
tertiary; the Large Files "older than 6 months" workflow depends on reading it.
**Rule:** `DESIGN.md:213-216` validates only `Color.secondary` (5.07:1 light / 6.48:1 dark);
tertiary is below AA for 11 pt text.
**Recommendation:** use `.secondary`; reserve tertiary for truly decorative metadata.

### P2-6 · Increased Contrast / Reduce Transparency are not handled for custom colors
**Where:** `BrandPalette.swift:20-25` `adaptive(_:_:)` resolves light/dark only; tile strokes,
glows and text over them never change under `.accessibilityContrast`.
**Rule:** *Adopting Liquid Glass* — define an increased-contrast option for each custom color
variant and test custom colors/animations against Reduced Transparency, Increased Contrast and
Reduce Motion configurations.
**Recommendation:** add contrast-aware variants for `Surface.tileStroke*` and glyph shadows, or
prefer system colors where the category identity allows it.

### P2-7 · Animation durations exceed the project's own 0.25 s budget
**Where:** `.snappy` defaults at `SidebarView.swift:94` and `CategoryDetailView.swift:188`
(~0.5 s springs), `CategoryDetailView.swift:324` spring response 0.28 s, `AboutView.swift:107-
110` `.snappy`; `DESIGN.md:172-173` promises *"everything else responds to user action and
stays under 0.25 s."*
**Recommendation:** use explicit short durations (`.snappy(duration: 0.2)`,
`.easeOut(duration: 0.18)`), keep the checkbox spring within budget, and pair P1-1's Reduce
Motion handling with these.

### P2-8 · Toolbar/menu semantics and missing standard shortcuts
**Where:** `ContentView.swift:35,44` — "Scan all" uses `sparkles` (the brand decorative glyph,
see `DESIGN.md:75`) while "Scan" uses `arrow.clockwise`; `SweepApp.swift:27-32` puts both scan
commands in the View menu via `CommandGroup(after: .sidebar)`. There is no Select All (`⌘A`)
command for the item list and no Escape/`⌘.` mapping to `cancelScan`
(`StateViews.swift:64` has the only Cancel button).
**Rule:** HIG The menu bar — put commands in menus that match their purpose; provide standard
shortcuts for standard actions.
**Recommendation:** pick scanner-specific symbols and reserve `sparkles` for brand moments, add
`Select All ⌘A` (and `Deselect All`) commands bound to `toggleSelectAll`, add
`.keyboardShortcut(.cancelAction)` to Cancel scan, and consider a dedicated Scan menu if the
command set grows.

### P2-9 · Sheets are fixed-width with long localized bodies
**Where:** `Sheets.swift:61,120` — both sheets are `.frame(width: 450)`; `confirm.body.emptyTrash`
and `report.done.trashed` are full sentences, and German/French translations run longer
(`Support/Resources/de.lproj/Localizable.strings`).
**Rule:** HIG Sheets / Layout — size to content and let text wrap rather than constraining it.
**Recommendation:** keep a `minWidth` (≈420) but let the content drive height and wrap
(`.fixedSize(horizontal: false, vertical: true)`), then re-check DE/ES.

### P2-10 · Empty-state copy repeats the header subtitle
**Where:** `CategoryDetailView.swift:140` shows `category.subtitle` in the header;
`StateViews.swift:19` repeats it in the empty state directly below ("No scan yet —
Temporary files created by applications."). Reproduced in both screenshots.
**Recommendation:** when `state == .idle`/`.empty`, let the empty state carry the explanation
(what will be scanned, approximate scope) and shorten the header subtitle to the root path or
drop it.

### P2-11 · Full Disk Access is advertised even when already granted
**Where:** `SidebarView.swift:45-52` unconditionally shows a "Full Disk Access…" link in the
sidebar footer; there is no probe of the protected paths before showing it.
**Rule:** HIG — don't instruct people to complete setup that is already complete; keep
persistent chrome for status.
**Recommendation:** probe a protected path (as the scanner does) or remember successful
scans, then hide or de-emphasize the link once access works.

### P2-12 · Icon generator duplicates the palette and has drifted values
**Where:** `Support/Branding/generate-icon.swift:25-27` hardcodes `brandMidnight = 0x0A0E2E`
(actually `BrandPalette.Brand.deep`, `BrandPalette.swift:34`) and `brandViolet = 0x7B4DFF`
(dead constant; `BrandPalette.violet` is `0x7F52FF`, `DESIGN.md:44`); the live gradient stops
at `:211-214` repeat the hexes `0C1134/1E2280/4634CE/7F52FF` a third time.
**Impact:** three copies of the brand ramp; one already wrong. `DESIGN.md:2-5` claims
`BrandPalette.swift` is the token home but the icon cannot import it (`Support/` is outside the
target).
**Recommendation:** generate the icon palette from a shared source (small script or checked
duplicated JSON), or at minimum delete the dead constants and add the icon hexes to the drift
checklist. The icon itself matches the documented construction and is legible at 32 px (verified
`icon-32.png`, `icon-1024.png`).

### P2-13 · Large Files has no sort affordance
**Where:** `ItemListView` (`CategoryDetailView.swift:201-219`) renders a fixed order; there is
no sort control for a category whose entire purpose is "find the biggest/oldest files".
**Rule:** HIG Lists and tables — use a table when presenting columns of data people compare and
sort; it also provides keyboard navigation and per-column VoiceOver semantics for free.
**Recommendation:** add a sort picker (size / date / name) at minimum; consider `Table` with
sortable columns as the medium-term refactor for `largeFiles` and `developer`.

## Recommendations

Priority order; effort S ≈ <½ day, M ≈ 1–2 days, L ≈ multi-day.

| # | Action | Effort |
| --- | --- | --- |
| 1 | Honor Reduce Motion in `SpinningRing` and state transitions (P1-1). | S |
| 2 | Surface scan failures/partial results; wire `.failed`, add FDA recovery (P1-2). | M |
| 3 | Resolve the accent story: pin `AccentColor` (#1F6BFA + dark + high contrast) or delete dead `Brand` tokens and update `DESIGN.md` (P1-3). | S–M |
| 4 | Flatten the content layer: one container treatment, no material-on-material (P1-4). | M |
| 5 | One destructive-button model per HIG (red + Cancel default, or Return + neutral) applied in both surfaces (P1-5). | S |
| 6 | Make Settings size per-pane, restore last pane, remove the About pane (P1-6). | M |
| 7 | Replace hardcoded radii/semantic colors with existing tokens or delete the tokens (P2-1). | S |
| 8 | Typography cleanup: no `.caption2`, text styles instead of fixed sizes, label the hero counters (P2-2, P2-5). | S |
| 9 | Remove the duplicated category title and refresh `docs/assets` screenshots (P2-3). | S |
| 10 | Row accessibility: expose selection state, fix stacked-opacity contrast (P2-4). | S |
| 11 | Add increased-contrast variants for tile strokes/glows (P2-6). | M |
| 12 | Tighten animation durations to the documented <0.25 s budget (P2-7). | S |
| 13 | Menu/toolbar semantics: Select All ⌘A, Escape cancels scan, icon roles (P2-8). | S–M |
| 14 | Content-wrap the confirm/report sheets and re-test DE/ES (P2-9). | S |
| 15 | Deduplicate empty-state copy; gate the FDA link on real access (P2-10, P2-11). | S–M |
| 16 | De-duplicate icon palette hexes; fix `generate-icon.swift` drift (P2-12). | S |
| 17 | Add sorting (and eventually `Table`) for Large Files (P2-13). | M–L |

Suggested sequencing: 1, 2, 5, 7, 9 are a same-day batch; 3 and 4 are the design-language
decisions to make before any UI polish pass; 17 is the only structural refactor.

## References

Files read for this review (read-only; nothing else modified):

- `DESIGN.md`
- `Sources/Sweep/SweepApp.swift`
- `Sources/Sweep/Views/DesignSystem.swift`
- `Sources/Sweep/Views/BrandPalette.swift`
- `Sources/Sweep/Views/ContentView.swift`
- `Sources/Sweep/Views/SidebarView.swift`
- `Sources/Sweep/Views/CategoryDetailView.swift`
- `Sources/Sweep/Views/StateViews.swift`
- `Sources/Sweep/Views/Sheets.swift`
- `Sources/Sweep/Views/SettingsView.swift`
- `Sources/Sweep/Views/AboutView.swift`
- `Sources/Sweep/Views/LargeFilesControls.swift`
- `Sources/Sweep/Models/AppModel.swift`
- `Sources/Sweep/Models/SpaceCategory.swift`
- `Sources/Sweep/Models/ScanItem.swift`
- `Sources/Sweep/Models/L10n.swift`
- `Sources/Sweep/Services/DiskScanner.swift` (scan entry points)
- `Support/Info.plist`
- `Support/Branding/generate-icon.swift`, `icon-16/32/1024.png`, `AppIcon.icns`
- `Support/Resources/{en,fr,de,es}.lproj/Localizable.strings`
- `docs/assets/sweep-light.png`, `docs/assets/sweep-dark.png`
- `Package.swift`, `Makefile`

HIG and Apple references cited above:

- HIG Accessibility (Motion; Reduce Motion response).
- HIG Buttons (primary role vs destructive actions).
- HIG Alerts (deliberately chosen destructive actions; Cancel; destructive styling).
- HIG Settings (per-pane sizing, last pane, window title, toolbar).
- HIG The menu bar (About menu item).
- HIG Materials + *Adopting Liquid Glass* (content layer vs Liquid Glass layer, custom colors
  with light/dark/increased-contrast variants, reduce custom backgrounds).
- WWDC25 "Meet Liquid Glass" (avoid glass on glass; tinting sparingly).
