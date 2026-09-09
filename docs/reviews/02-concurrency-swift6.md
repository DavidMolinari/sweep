# 02 — Concurrency & Swift 6 Readiness

Context: Sweep is a macOS 14 SwiftUI app built with Swift tools 5.9 in Swift 5 language mode, with no test target. The concurrency surface is small: `AppModel` is `@MainActor`, `DiskScanner` is a stateless `enum` using one bounded `withTaskGroup` per category, `Cleaner` is a synchronous utility, and a `DispatchSemaphore` bridges the `--scan`/`--selftest` CLI modes. This review audits every isolation boundary and estimates the cost of flipping the target to Swift 6 language mode with `-strict-concurrency=complete`.

Verification method: read-only inspection plus `swiftc -typecheck` (Xcode 16.4 / Swift 6.1.2) on a scratch copy of `Sources/`, in both `-swift-version 6` and `-strict-concurrency=complete`. No build was run in the repository. Result up front: **the whole target typechecks with zero diagnostics in Swift 6 mode after exactly two `@MainActor` annotations** (see Recommendations). No P0 data race was found; the real work is runtime behavior, not compiler appeasement.

## Findings

### [P1] `Cleaner.clean` executes on the main actor — AppModel.swift:244-245, Cleaner.swift:31-65

`Task {}` created in `performClean` inherits `@MainActor` from `AppModel`, and `Cleaner.clean` is a synchronous nonisolated function: the call therefore runs in the MainActor's execution context and blocks the main thread for the whole deletion loop. Each iteration performs blocking filesystem I/O (`trashItem` / `removeItem` at Cleaner.swift:53-56) plus several symlink resolutions per item (Cleaner.swift:107-112). The `Task.isCancelled` guard at Cleaner.swift:39 reads the enclosing task, but no handle to that task is stored, so it can never become true — it is dead code.

- Risk: main-thread I/O / UI freeze proportional to the number of selected items and volume latency (network, FileProvider and virtual volumes can take seconds or more). Not a data race.
- Recommendation: make the API asynchronous and await it from the (still MainActor) decision logic; a nonisolated `async` callee runs on the global executor (SE-0338) and inherits the caller's cancellation:

```swift
// Cleaner.swift
static func clean(items: [ScanItem], category: SpaceCategory) async -> Report {
    // same body; keep `Task.isCancelled` / use `try Task.checkCancellation()`
    for item in items {
        if Task.isCancelled { break }
        // ...
    }
    return report
}

// AppModel.swift
private var cleanTask: Task<Void, Never>?

func performClean(_ pending: PendingClean) {
    confirmation = nil
    cleanTask?.cancel()
    cleanTask = Task { [weak self] in
        let outcome = await Cleaner.clean(items: pending.items, category: pending.category)
        guard let self, !Task.isCancelled else { return }
        // existing commit + report code
    }
}
```

The four synchronous self-test call sites in `HeadlessMode.swift:28-51` then need to `await` too (make `runSelfTestIfRequested` async and bridge it like `runIfRequested`, or keep a private sync core and expose an async wrapper). Do not "fix" this with `Task.detached { Cleaner.clean(...) }` alone: the detached task does not inherit cancellation, so cancellation stays dead unless you forward it explicitly (`withTaskCancellationHandler` + an atomic flag).

### [P2] Scan cancellation is deferred and does not release the category slot — AppModel.swift:190-192, 143-187; DiskScanner.swift:209-230

`cancelScan` only calls `task.cancel()`. Until the task drains, the UI stays in `.scanning`, and `tasks[category]` stays occupied, so a restart is silently refused by the guard at AppModel.swift:144. `withTaskGroup` waits for every in-flight child, and children can only observe cancellation at their own checkpoints (DiskScanner.swift:184, 242, 325, 392, 405); a child blocked in a single `resourceValues` call on a stalled volume cannot be interrupted.

- Risk: perceived hang after pressing Cancel (bounded by one checkpoint, usually milliseconds, unbounded on unhealthy volumes); no deadlock, no data race.
- Recommendation: reset state immediately and protect the late commit with a generation token. Once the slot is freed at cancel time, the token is mandatory otherwise a cancelled task can overwrite the results of a newer scan:

```swift
private var scans: [SpaceCategory: (id: UUID, task: Task<Void, Never>)] = [:]

// in scan(_:), after building the placeholder:
let scanID = UUID()
let task = Task { [weak self] in
    let output = await DiskScanner.scan(/* ... */)
    guard let self, self.scans[category]?.id == scanID, !Task.isCancelled else { return }
    // commit results, liveBytes, then self.scans[category] = nil
}
scans[category] = (scanID, task)

func cancelScan(_ category: SpaceCategory) {
    guard let entry = scans[category] else { return }
    entry.task.cancel()
    scans[category] = nil
    var result = results[category] ?? CategoryResult()
    result.state = .idle
    result.replaceItems([])
    results[category] = result
    liveBytes[category] = 0
}
```

### [P2] Progress pipeline: one unstructured task per flush, and a stale `liveBytes` ordering hazard — AppModel.swift:159-170, 184

The `progress` closure captures `self` (an implicitly `Sendable` `@MainActor` class, so this is legal under Swift 6 — verified) and spawns an unstructured `Task { @MainActor in ... }` for every flush (at most ~10/s per category). The task that resets `liveBytes[category] = 0` at AppModel.swift:184 can be scheduled before an already-enqueued progress task, leaving a non-zero counter displayed after the scan is `.done`.

- Risk: minor UI inconsistency; no data race (all mutations are MainActor-serialized). Not a Swift 6 blocker.
- Recommendation: replace the per-flush tasks with one `AsyncStream` consumer and await it before resetting. The handler then captures only the (Sendable) continuation, which also keeps the closure safe if the project later enables `NonisolatedNonsendingByDefault`:

```swift
let (progress, continuation) = AsyncStream<Int64>.makeStream()
let progressTask = Task { @MainActor [weak self] in
    for await bytes in progress { self?.liveBytes[category, default: 0] += bytes }
}
let output = await DiskScanner.scan(
    category: category, threshold: threshold, oldOnly: oldOnly,
    customRoot: customRoot, runningBundleIDs: runningIdentifiers,
    progress: { continuation.yield($0) }
)
continuation.finish()
await progressTask.value          // all increments applied
self.liveBytes[category] = 0      // then reset
```

`AsyncStream.makeStream` is back-deployed before macOS 14 (confirmed in the macOS 15.5 SDK `_Concurrency` interface), so no availability issue at the current deployment target.

### [P2] Up to 40 blocking directory walks on the cooperative pool — AppModel.swift:139-141; DiskScanner.swift:41, 209-230, 298-318

`maxConcurrentScans` is 8 per category and `scanAll` starts all 5 categories at once, so up to 40 children can run. Each child runs synchronous, non-suspending work for its whole lifetime (`size(of:)`/`directorySize` at DiskScanner.swift:162-191, `walkLargeFiles` at 385-451), i.e. it occupies a cooperative-pool thread while enumerating. The cooperative pool is sized to the core count, not to 40.

- Risk: cooperative-thread starvation — continuations of the scan itself and any other async work in the process are delayed; heavy disk contention. No deadlock: the blocking calls eventually return.
- Recommendation: add a process-wide limiter (an actor-based async semaphore) shared by `scanChildren` and `scanDeveloperCaches`, or serialize `scanAll`; e.g. limit to `max(2, ProcessInfo.processInfo.activeProcessorCount)`. If you instead route the blocking walks through a dedicated `DispatchQueue` bridged with `withCheckedContinuation`, be aware that `Task.isCancelled` is always `false` inside a GCD closure — forward cancellation with `withTaskCancellationHandler` and an atomic flag (e.g. `OSAllocatedUnfairLock<Bool>`).

### [P2] `ProgressReporter` is `@unchecked Sendable` and can invoke the handler concurrently — DiskScanner.swift:5-39

The implementation is sound as written: `pending`/`lastFlush` are lock-guarded, and `handler(value)` is deliberately called after `unlock()` (avoids re-entrancy deadlock). Two things are not expressed in the type system: the unchecked conformance itself, and the fact that a handler slower than the 100 ms flush interval can be invoked concurrently from `add` on another thread. Today's handler (spawning a MainActor task) tolerates this, but a future handler might not.

- Risk: future data race if a handler author assumes serial invocation; no bug today.
- Recommendation: store state in `OSAllocatedUnfairLock(initialState:)` (macOS 13+, compatible with the macOS 14 target) or `synchronization.Mutex` (macOS 15, availability-gated) so the class can be plain `Sendable`; otherwise keep `@unchecked` but add an explicit comment documenting the contract. If you adopt the `AsyncStream` suggestion above, document that `Continuation.yield` is thread-safe — which it is — and drop the custom lock entirely.

### [P2] `HeadlessMode` blocks the MainActor on a semaphore with no timeout or `defer` — HeadlessMode.swift:65-113; SweepApp.swift:9-12

`runIfRequested` reads main-thread-only AppKit (`NSApplication.shared`, `NSWorkspace.shared.runningApplications` at HeadlessMode.swift:79-81), then blocks the main thread on `finished.wait()` (line 112) while a `Task.detached` scans. `signal()` is the last statement of the detached task (line 110), not deferred, and the wait has no timeout.

- Risk: latent deadlock — the moment any code on the scan path requires the MainActor/main thread, the process hangs at launch; a skipped `signal()` hangs forever. No issue today because `DiskScanner` is Foundation-only.
- Recommendation: annotate `runIfRequested` with `@MainActor` (this is also the required Swift 6 fix, see below), replace `finished.signal()` with `defer { finished.signal() }`, use `Task.detached(priority: .userInitiated)`, and `wait(timeout: .now() + 600)` with a diagnostic + non-zero `exit` on timeout. Document that the scan path must stay MainActor-free, or convert the CLI path to `async` and exit from the task.

### [P2] `Task.isCancelled` in synchronous helpers is context-dependent — Cleaner.swift:39; DiskScanner.swift:184, 242, 325, 392, 405

Inside `withTaskGroup` children these checks work (structured cancellation propagates), but when the same helpers are called from a plain synchronous context — the self-test, or a future unit test — `Task.isCancelled` is silently `false`, and in `Cleaner.clean` it can never fire because the enclosing task is unreachable.

- Risk: false confidence in cancellation behavior; cancellation cannot be unit-tested through the current API.
- Recommendation: thread an explicit `isCancelled: @Sendable () -> Bool` through the synchronous APIs (or make them `async` and use `Task.checkCancellation()`); tests should wrap the work in a `Task` and cancel it.

### [P2] No test target, and scan roots are hard-wired to `NSHomeDirectory()` — Package.swift:9-14; DiskScanner.swift:123, 140, 268-294, 364-370; Cleaner.swift:104

The target is a single `executableTarget` with no tests, and `DiskScanner` derives every root from `NSHomeDirectory()` while `Cleaner.refusalReason` is `private`. The behaviors most at risk here (cancellation latency, progress coalescing, concurrency window, refusal rules) are exactly the ones that need tests, and a test that uses the current API would touch the developer's real home directory.

- Risk: regressions undetected; untestable design.
- Recommendation: add a `Tests/SweepTests` target (swift-testing, bundled with the toolchain); ideally split pure logic into a `SweepCore` library target with the executable as a thin `@main` shell. Inject a small `ScanRoots`/`ScanEnvironment` value into `DiskScanner.scan` (defaulting to today's behavior), make `refusalReason` internal for pure unit tests, and add: an `@MainActor` test for `AppModel` cancel semantics (asserting immediate `.idle` and that a late cancelled scan cannot clobber a new one), a `ProgressReporter` test that adds from many group children concurrently and asserts no bytes are lost, and a cancellation test that runs `DiskScanner.size` inside a cancelled `Task`.

### Verified sound (no action)

- `AppModel` MainActor discipline is correct: all UI state mutations happen on the MainActor, and only Sendable values (`SpaceCategory`, `Set<String>`, `[ScanItem]`, `Int64`) cross isolation boundaries. `@MainActor` classes are implicitly `Sendable`, so the progress closure capture at AppModel.swift:166-170 is valid under Swift 6 (verified by typecheck).
- `NSWorkspace.shared.runningApplications` is read on the main thread at both call sites (AppModel.swift:156 on the MainActor; HeadlessMode.swift:80 in `App.init`, now to be annotated `@MainActor`), and only `bundleIdentifier`/`localizedName` strings are passed to the scanner (AppModel.swift:157) — `NSRunningApplication` is not Sendable, so never move the array or the read off-main.
- The `withTaskGroup` windowing pattern (DiskScanner.swift:209-230, 298-318) is correct: bounded width, index-keyed slots, draining on cancellation, final sort. Child closures capture only Sendable values (`URL`, `Set<String>`, the `@unchecked Sendable` reporter).
- No P0: there is no reachable data race or deadlock in the current code.

## Recommendations

Ordered migration path. The headline: strict concurrency is already essentially satisfied; the fixes below are about runtime behavior (main-thread I/O, cancellation, starvation) that the type checker cannot see.

| # | Step | Effort | Priority |
|---|------|--------|----------|
| 1 | Flip to Swift 6 language mode; add the 2 required `@MainActor` annotations | S | Do first |
| 2 | Move `Cleaner.clean` off the MainActor (async) and make its cancellation real | S | P1 |
| 3 | Immediate cancel state reset + generation token for late commits | S | P2 |
| 4 | Replace per-flush progress tasks with an `AsyncStream` consumer | S | P2 |
| 5 | Harden `ProgressReporter` (`OSAllocatedUnfairLock` or documented `@unchecked`) | S | P2 |
| 6 | Global scan concurrency limiter (or GCD bridge with forwarded cancellation) | M | P2 |
| 7 | Harden the `HeadlessMode` semaphore bridge (`defer`, timeout, priority) | S | P2 |
| 8 | Test target + injected scan roots (optionally split `SweepCore` library) | M | P2 |
| 9 | CI: `-strict-concurrency=complete`, warnings-as-errors, `swift test` | S | P2 |

**Step 1 — Swift 6 language mode (verified).** Bump the manifest to tools 6.0 and opt into v6 per target:

```swift
// swift-tools-version: 6.0
// ...
.executableTarget(
    name: "Sweep",
    path: "Sources/Sweep",
    swiftSettings: [.swiftLanguageMode(.v6)]
)
```

Then add exactly two annotations, both required because `NSApplication.shared` is `NS_SWIFT_UI_ACTOR` in the SDK:

- `@MainActor` on `HeadlessMode.runIfRequested` (HeadlessMode.swift:65) — and for symmetry on `runSelfTestIfRequested` (line 5); both are only called from `App.init` (SweepApp.swift:10-11), which is MainActor-inferred.
- `@MainActor` on `AppInfo.icon` (AboutView.swift:5) — used only from SwiftUI views.

With those in place, a scratch `swiftc -typecheck -swift-version 6` and a scratch `-strict-concurrency=complete` run over the whole target report **zero errors and zero warnings** (Swift 6.1.2, Xcode 16.4). There are no other strict-concurrency diagnostics: the `@unchecked Sendable` reporter, the task groups, the semaphore capture, and the progress closure all pass. If you prefer a warning-only audit first, keep tools 5.9 and add `.unsafeFlags(["-strict-concurrency=complete"])` temporarily (fine for a root executable target).

**Effort estimate.** Step 1 is under half a day (two annotations, verified). Steps 2-4 are another half day. A clean implementation of the full list, including the test target and CI, is 2-3 days for one experienced developer — M overall. The migration risk is low: no third-party dependencies, one module, and the compiler already accepts the isolation model.

**Forward-looking note.** On Swift 6.2+, if the `NonisolatedNonsendingByDefault` upcoming feature is enabled, `nonisolated async` functions run on the caller's actor by default. At that point `await DiskScanner.scan(...)` from the MainActor would start on the main actor unless the function is marked `@concurrent` (or the work is dispatched explicitly). Keep the heavy scanners either synchronous-on-a-dedicated-executor or annotated `@concurrent` when the feature becomes available, so off-main execution is explicit rather than implied by SE-0338.

## References

Files read (paths relative to the repository root):

- `Package.swift` (15 lines)
- `Sources/Sweep/SweepApp.swift` (58)
- `Sources/Sweep/HeadlessMode.swift` (115)
- `Sources/Sweep/Models/AppModel.swift` (301)
- `Sources/Sweep/Models/ScanItem.swift` (87)
- `Sources/Sweep/Models/SpaceCategory.swift` (53)
- `Sources/Sweep/Services/Cleaner.swift` (140)
- `Sources/Sweep/Services/DiskScanner.swift` (531)
- `Sources/Sweep/Views/CategoryDetailView.swift` (lines 1-130: scan/cancel wiring at 59-79)
- `Sources/Sweep/Views/AboutView.swift` (lines 1-113: `AppInfo.icon` at 4-9)
- `Makefile` (49)
- SDK checked: macOS 15.5 `AppKit.framework/Headers/NSApplication.h`, `NSWorkspace.h`, `NSRunningApplication.h` (actor annotations), `_Concurrency.swiftmodule` interface (`AsyncStream.makeStream` back-deployment)
- Scratch verification: `swiftc -typecheck -swift-version 6` and `-strict-concurrency=complete` over a copy of `Sources/` (Xcode 16.4, Swift 6.1.2); no build was run in the repository.
