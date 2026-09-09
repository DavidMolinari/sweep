# 03 — Architecture & Testability

Context: Sweep is a ~3.1 kloc SwiftUI/SPM macOS 14 app built as a single
executable target (`Package.swift:10-13`), with a `--scan` / `--selftest`
headless path (`HeadlessMode.swift`). The product is safety-critical (it deletes
user files), about to be open-sourced, and currently has no automated test
target; this review maps the structural obstacles to testing and proposes a
concrete target split and injection plan.

Grade: **C** — clean and readable for its size, but the seams needed to test the
safety rules do not exist yet, and `AppModel` already mixes UI, persistence and
domain orchestration.

---

## Findings

### [P0] No test target is possible without restructuring: one monolithic executable
`Package.swift:10-13` declares a single `.executableTarget`. `CONTRIBUTING.md:36-57`
states explicitly "There is no XCTest target"; the only automated check is
`HeadlessMode.runSelfTestIfRequested()` (`HeadlessMode.swift:5-63`) which runs
`exit()` from `SweepApp.init()` (`SweepApp.swift:9-12`).

- Impact: `swift test` has nothing to run; the four safety invariants listed in
  `CONTRIBUTING.md:59-81` are enforced by a printed script, not assertions.
  SwiftPM can technically link a test target against an executable target since
  Swift 5.5, but it drags the `@main` SwiftUI app, AppKit singletons and the
  whole UI into the test process — not a sane seam.
- Recommendation: split into `SweepKit` (library, Foundation only), `SweepUI`
  (library, SwiftUI/AppKit, depends on `SweepKit`) and a thin `Sweep`
  executable depending on both, plus `SweepKitTests`. See target architecture.

### [P0] `DiskScanner` and `Cleaner` are static enums hardwired to the real machine
`DiskScanner` (`DiskScanner.swift:4`) and `Cleaner` (`Cleaner.swift:3`) expose only
`static` members and read the ambient environment directly:
`NSHomeDirectory()` (`DiskScanner.swift:140,268,352,365,527`; `Cleaner.swift:72,82,123-129`),
`FileManager.default` (`DiskScanner.swift:166,174,199,326,366,394`; `Cleaner.swift:36`),
`Calendar.current`/`Date()` (`DiskScanner.swift:375`). There is no protocol, no
initializer, no way to point a scan at a fixture directory.

- Impact: the scan pipeline (child scanning, large-file walk, project-subtree
  skipping, running-app token matching) has zero test coverage and can only be
  exercised against the developer's real home directory. The cleaner's policy
  (`forbiddenPaths`, `forbiddenPrefixes`, `isDescendant`) is the highest-risk
  code in the repo and is only covered by four ad-hoc cases in
  `HeadlessMode.swift:26-51`.
- Recommendation: turn both into injectable value/reference types taking a
  `FileSystem` protocol, a `home: URL`, a `runningIdentifiers: Set<String>`
  provider and a clock/calendar; keep static façades only as deprecated
  convenience. Sketch below.

### [P1] `AppModel` is a god-object: 5 responsibilities, 3 frameworks, concrete dependencies
`AppModel.swift:74-301` centralizes: scan lifecycle and task registry
(`scan/cancelScan/rescanIfDone`, lines 135-202), selection mutation (204-231),
clean flow and report (233-263), preference persistence inside `didSet`
(83-93) and `init` (107-119), AppKit dialogs and deep links
(`NSOpenPanel` 266-286, `NSAlert` 275-281, `NSWorkspace` 156,290), and volume
free-space queries (129-133). It imports AppKit + SwiftUI + Foundation (lines 1-3)
and calls `DiskScanner.scan` (160) and `Cleaner.clean` (245) statically.

- Impact: no part of the app's behavior can be unit-tested; changing the scan
  orchestration requires touching a file that also owns NSOpenPanel copy and
  UserDefaults keys; the class is the merge-conflict hotspot for every feature.
- Recommendation: split into `PreferencesStore` (UserDefaults/authored keys),
  `SystemActions` (folder panel, alerts, reveal/copy, open settings) behind a
  protocol, `ScanSession` (results, live bytes, task registry, selection) and
  `CleanSession` (confirmation, execution, report). `AppModel` becomes a thin
  `@MainActor ObservableObject` composing them for SwiftUI.

### [P1] Domain model is coupled to SwiftUI and to localized presentation
`SpaceCategory` imports SwiftUI (`SpaceCategory.swift:1`) and carries `title`,
`subtitle`, `symbol`, `tint: Color` (12-50). `CautionReason.message`
(`ScanItem.swift:9-16`) and `Cleaner.RefusalReason.message`
(`Cleaner.swift:12-21`) render localized text in the domain layer.
`DiskScanner` returns localized root labels (`String(localized: "root.developer")`
at 152, `"root.largeFiles.default"` at 157) mixed with raw paths. `L10n` lives in
`Models/` although it is presentation formatting (`L10n.swift:3-41`).

- Impact: the core cannot be reused or tested headless; failure output cannot be
  asserted structurally (tests would compare localized strings); a library target
  would need SwiftUI just to expose categories. `SpaceCategory.tint` is also dead
  code — no call site; colors actually come from `CategoryStyle.of`
  (`DesignSystem.swift:32-40`), a duplicate mapping that must be kept in sync.
- Recommendation: keep a pure `SpaceCategory` (rawValue, `isPermanentDeletion`)
  in `SweepKit`; move title/subtitle/symbol to a `SpaceCategory+Presentation`
  extension in `SweepUI`; replace pre-rendered `message` strings with structured
  reasons rendered by the UI; return a `RootLabel` enum from the scanner instead
  of a localized string; drop `tint` or move it to the presentation extension.

### [P1] The safety net is an ad-hoc script that writes into the user's real home
`HeadlessMode.runSelfTestIfRequested()` creates fixtures in the real
`~/Library/Caches` and `~/.Trash` (`HeadlessMode.swift:10-12,23-24`), asserts by
printing and incrementing an int (26-51), then `exit()`s (62). CI runs it
(`.github/workflows/ci.yml`, "Run safety self-test"). It never touches
`DiskScanner`, so scanner regressions ship silently.

- Impact: running the app locally with `--selftest` mutates personal directories;
  failures are not reported per-assertion; the suite cannot grow beyond a CLI
  script.
- Recommendation: port the four cases to XCTest (or Swift Testing once the
  toolchain floor is Xcode 16) in `SweepKitTests` using temporary directories and
  an injected `home`; keep `--selftest` as a lightweight packaged smoke test that
  drives the same kit APIs, and have CI run both.

### [P2] `HeadlessMode` is a second composition root that duplicates AppModel logic
`runIfRequested()` (`HeadlessMode.swift:65-114`) rebuilds running-app identifiers
(79-81), hardcodes threshold `100 MB`, and blocks on a `DispatchSemaphore`
(83,112) around `Task.detached`, then `exit()`s. `--scan` and the GUI take
different paths through the same services.

- Impact: CLI output can drift from GUI behavior; both call sites must be updated
  when scan parameters change.
- Recommendation: introduce a `ScanRequest` value type and a `ScanRunner` in
  `SweepKit`; make both `HeadlessMode` and `ScanSession` call it. Keep the CLI
  adapter in the executable target, free of business logic.

### [P2] Preferences have two owners (AppModel and `@AppStorage`)
`AppModel.init` reads `defaultCategoryKey` (`AppModel.swift:114-117`) and
`resetPreferences` removes it (298); `SettingsView` binds the same key with
`@AppStorage(AppModel.defaultCategoryKey)` (`SettingsView.swift:32`). Threshold,
old-only and custom root are persisted in `didSet` observers
(`AppModel.swift:83-93`).

- Impact: split source of truth; persistence side effects in property observers
  are invisible to tests and order-dependent with view updates.
- Recommendation: a single `PreferencesStore` protocol
  (`PreferencesStoring`) with a `UserDefaults` implementation and an in-memory
  double; load once in `init`, write explicitly, remove `didSet` side effects.

### [P2] Business rules live in views and views call AppKit directly
`CategoryDetailView` computes flagged/running filters (lines 11-13) and
`CleanBar` recomputes "all selected" (`CategoryDetailView.swift:371-372`), while
`ItemRow` calls `NSWorkspace.shared.activateFileViewerSelecting` and
`NSPasteboard.general` inline (291-296) and `SettingsView`/`AboutView` call
`NSWorkspace`, `Bundle.main` (`SettingsView.swift:84-94`, `AboutView.swift:4-24`).

- Impact: selection semantics (only `safe` items are selectable) are expressed in
  more than one place and cannot be tested; view code is untestable by design.
- Recommendation: move derived values to `CategoryResult` (`selectableCount`,
  `allSelectableSelected`, `flaggedItems`, `runningCount`) and route reveal/copy
  through a `SystemActions` protocol implemented in `SweepUI`.

### [P2] Concurrency and hygiene issues that will bite under Swift 6
`DiskScanner` imports AppKit (`DiskScanner.swift:1`) but uses nothing from it;
`ProgressReporter` is `@unchecked Sendable` (7); `ScanItem`, `ItemSafety`,
`ScanOutput` cross task boundaries without `Sendable` conformances. The package
is Swift-5.9 language mode, so this compiles today.

- Impact: enabling strict concurrency later will produce a wall of diagnostics
  across services and models; `@unchecked` hides real review needs.
- Recommendation: mark domain value types `Sendable`, drop the unused AppKit
  import, and enable `StrictConcurrency` after the target split. `ScanItem`'s
  `Equatable` implementation comparing only `id`/`isSelected`
  (`ScanItem.swift:84-86`) is intentional for diffing but should be commented or
  renamed (`hasSameIdentityAndSelection`).
- Hygiene: `CategoryDetailView.swift` (442 lines) contains four view structs and
  `AboutView.swift` contains three; `CONTRIBUTING.md:88-91` asks for one concern
  per file. Split as files are touched, not as a sweeping refactor.

---

## Target architecture

### Target graph

```
Package.swift
├── SweepKit            .library — Foundation only. No SwiftUI, no AppKit.
│   ├── Models/         ScanItem, ItemSafety, CautionReason, ScanState,
│   │                   SpaceCategory (raw + isPermanentDeletion),
│   │                   CategoryResult, PendingClean, CleanReport,
│   │                   ScanRequest, ScanOutput, CleanOutcome
│   ├── Ports/          DiskScanning, Cleaning, FileSystem,
│   │                   RunningApplicationsProviding, PreferencesStoring,
│   │                   ClockProviding
│   ├── Services/       DiskScanner (instance), Cleaner (instance), CleanPolicy,
│   │                   ScanRunner, SystemFileSystem
│   └── Resources/      Localizable.xcstrings (moved from Support/Resources)
│
├── SweepUI             .library — SwiftUI/AppKit, depends on SweepKit
│   ├── AppModel.swift          thin ObservableObject composing the sessions
│   ├── Sessions/               ScanSession, CleanSession, PreferencesStore,
│   │                           LiveSystemActions (NSOpenPanel/NSAlert/NSWorkspace)
│   ├── Presentation/           SpaceCategory+Presentation, CategoryStyle,
│   │                           BrandPalette, DesignSystem, L10n
│   └── Views/                  ContentView, SidebarView, CategoryDetailView, …
│
├── Sweep               .executable — depends on SweepKit + SweepUI
│   ├── SweepApp.swift          @main, AppDelegate, commands
│   ├── HeadlessMode.swift      thin CLI adapter over ScanRunner / SelfTest
│   └── AppInfo.swift           version/GitHub info (moved out of AboutView)
│
├── SweepKitTests       .testTarget — depends on SweepKit
│   ├── FakeFileSystem.swift    in-memory tree + recorded removals
│   ├── CleanerTests.swift      policy matrix: symlink, outside root, trash,
│   │                           protected paths, unauthorized root
│   ├── DiskScannerTests.swift  child scan, large-file walk, project skip,
│   │                           token matching, threshold/cutoff
│   └── ScanRunnerTests.swift   ScanRequest end-to-end on fake FS
│
└── SweepUITests        .testTarget (optional) — depends on SweepUI
    └── ScanSessionTests.swift  orchestration with fake DiskScanning/Cleaning
```

Minimal variant if the three-target split feels heavy for a 3 kloc app:
`SweepCore` (Foundation) + `Sweep` (exe containing UI + `AppModel`), with
`SweepCoreTests`. The UI cannot be tested either way, but the safety-critical
logic gets the same coverage; `SweepUI` is what enables testing `ScanSession`.

### Interfaces (proposed)

```swift
// SweepKit/Ports/FileSystem.swift
public struct EntryMetadata: Sendable, Equatable {
    public var isDirectory: Bool
    public var isPackage: Bool
    public var isSymbolicLink: Bool
    public var allocatedBytes: Int64
    public var modified: Date?
}

public protocol FileSystem: Sendable {
    func metadata(of url: URL) throws -> EntryMetadata
    func children(of directory: URL, skipsHiddenFiles: Bool) throws -> [URL]
    func remove(_ url: URL) throws          // permanent
    func trash(_ url: URL) throws           // recoverable
}

// SweepKit/Ports/DiskScanning.swift
public struct ScanRequest: Sendable {
    public var category: SpaceCategory
    public var threshold: Int64
    public var oldOnly: Bool
    public var customRoot: URL?
    public var runningIdentifiers: Set<String>
}
public struct ScanOutput: Sendable {
    public var items: [ScanItem]
    public var root: URL
    public var rootLabel: RootLabel?        // .developer, .defaultLargeFiles, nil
}

public protocol DiskScanning: Sendable {
    func scan(_ request: ScanRequest,
              progress: @Sendable @escaping (Int64) -> Void) async -> ScanOutput
}

// SweepKit/Ports/Cleaning.swift
public struct CleanOutcome: Sendable {
    public var removedIDs: [UUID]
    public var freed: Int64
    public var failures: [CleanFailure]     // itemName + CleanRefusal / message
    public var permanent: Bool
}
public protocol Cleaning: Sendable {
    func clean(_ items: [ScanItem], category: SpaceCategory) -> CleanOutcome
}

// SweepKit/Services/DiskScanner.swift
public struct DiskScanner: DiskScanning {
    public init(fileSystem: FileSystem = SystemFileSystem(),
                home: URL,
                runningApplications: RunningApplicationsProviding,
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = Date.init)
}

// SweepKit/Services/Cleaner.swift
public struct Cleaner: Cleaning {
    public init(fileSystem: FileSystem, policy: CleanPolicy)
}
public struct CleanPolicy: Sendable {       // replaces the static path sets
    public init(home: URL)
    public func refusal(for item: ScanItem,
                        category: SpaceCategory) -> CleanRefusal?
}
```

`RunningApplicationsProviding` and `SystemActions` keep AppKit out of
`SweepKit`: the live implementations live in `SweepUI` (or the exe target) and
are injected at composition time in `SweepApp` / `HeadlessMode`.

```swift
// SweepUI
protocol SystemActions: AnyObject {
    func chooseFolder(startingAt: URL?, allowsMultiple: Bool) -> URL?
    func showProtectedFolderAlert()
    func reveal(_ url: URL)
    func copyToPasteboard(_ string: String)
    func open(_ url: URL)
}
```

`AppModel` keeps only `@Published` state and forwards to sessions:

```swift
@MainActor final class AppModel: ObservableObject {
    let scan: ScanSession
    let clean: CleanSession
    @Published var selection: SpaceCategory? { didSet { scan.select(selection) } }
    // thin: no UserDefaults, no NSOpenPanel, no FileManager
}
```

### Localization

`Support/Resources/*.lproj` is copied by the Makefile (`Makefile:17`) and is
invisible to SPM: `swift run` and any test target show raw keys, because
`String(localized:)` resolves against `Bundle.main`. To make strings testable:
declare `defaultLocalization: "en"` and
`resources: [.process("Resources")]` on the target owning `L10n`
(`SweepUI`), migrate to `LocalizedStringResource`/`String(localized:bundle:)`
with `Bundle.module`, and update the Makefile to copy the generated
`Sweep_SweepUI.bundle` into `Contents/Resources` (or keep the `.lproj` copy and
pass `bundle: .main` explicitly — less clean but zero Makefile churn).

### Migration plan (incremental, each step shippable)

1. **Scaffold (S).** Add `SweepKit`, `SweepUI`, `SweepKitTests` targets; `git mv`
   files; `Sweep` imports both libraries. No behavior change. CI adds
   `swift test` (initially empty) before packaging. Keep `make app` untouched
   (executable is still named `Sweep`).
2. **Pure models (S).** Move domain types to `SweepKit`; add
   `SpaceCategory+Presentation` and delete `tint`; move `L10n` to `SweepUI`;
   replace `CautionReason.message` / `RefusalReason.message` with structured
   reasons rendered by views.
3. **Seams (M).** Introduce `FileSystem`/`SystemFileSystem`, make
   `DiskScanner`/`Cleaner` instance types taking `home` + deps; keep
   `DiskScanner.size(of:)` as a static wrapper during transition; return
   `RootLabel` instead of `String(localized:)`.
4. **Tests (M).** Port the four `--selftest` cases to `CleanerTests` with temp
   dirs; add policy-matrix tests (symlink, outside scan root, trash outside,
   protected paths, unauthorized root) and scanner tests with `FakeFileSystem`.
   Turn `--selftest` into a packaged smoke test calling the same kit APIs.
5. **AppModel split (M).** Extract `PreferencesStore`, `SystemActions`,
   `ScanSession`, `CleanSession`; inject `DiskScanning`/`Cleaning`. Add
   `ScanSessionTests` with fakes (cancel, live bytes, selection rules,
   rescan-on-done).
6. **Localization/resources (M).** Move resources into SPM, update Makefile,
   add a test that every key resolves in all four locales.
7. **Cleanup (S).** `Sendable` annotations, drop unused `AppKit` import,
   enable `StrictConcurrency`, split oversized view files and `AppInfo.swift`.

Order matters: 1-4 are the safety payoff; 5-7 are maintainability.

---

## Recommendations

| # | Priority | Action | Effort |
|---|----------|--------|--------|
| 1 | P0 | Split `SweepKit` library + `Sweep` exe + `SweepKitTests`; add `swift test` to CI | M |
| 2 | P0 | Make `DiskScanner`/`Cleaner` instance types with injected `FileSystem`, `home`, clock; introduce protocols | M |
| 3 | P0 | Port `--selftest` to XCTest with temp dirs; add cleaner policy matrix and scanner tests | M |
| 4 | P1 | Split `AppModel` into `PreferencesStore` + `SystemActions` + `ScanSession` + `CleanSession` | M |
| 5 | P1 | Purify domain: no SwiftUI in `SpaceCategory`, structured refusal/caution reasons, `RootLabel` | S |
| 6 | P1 | Unify preferences in one store; remove `didSet` persistence and `@AppStorage` dual ownership | S |
| 7 | P2 | Move `L10n` + `.lproj` into SPM resources with `Bundle.module`; update Makefile; key-resolution test | M |
| 8 | P2 | Make `HeadlessMode` a thin adapter over `ScanRunner`; share `ScanRequest` with the GUI | S |
| 9 | P2 | Move derived selection/filter logic out of views; route AppKit calls through `SystemActions` | S |
| 10 | P2 | Swift 6 readiness: `Sendable`, drop unused imports, `StrictConcurrency`; split large view files | S |

---

## References

Files read for this review:

- `Package.swift`
- `Makefile`
- `CONTRIBUTING.md`, `DESIGN.md`, `README.md`, `Support/Info.plist`
- `.github/workflows/ci.yml`
- `Sources/Sweep/SweepApp.swift`
- `Sources/Sweep/HeadlessMode.swift`
- `Sources/Sweep/Models/AppModel.swift`, `ScanItem.swift`, `SpaceCategory.swift`, `L10n.swift`
- `Sources/Sweep/Services/DiskScanner.swift`, `Cleaner.swift`
- `Sources/Sweep/Views/ContentView.swift`, `CategoryDetailView.swift`, `SidebarView.swift`, `StateViews.swift`, `Sheets.swift`, `SettingsView.swift`, `LargeFilesControls.swift`, `AboutView.swift`, `DesignSystem.swift`, `BrandPalette.swift`
- `Support/Resources/{en,fr,de,es}.lproj/Localizable.strings` (inventory via filesystem scan)
