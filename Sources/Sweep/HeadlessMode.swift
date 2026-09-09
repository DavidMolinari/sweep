import AppKit
import Foundation

enum HeadlessMode {
    @MainActor
    static func runSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }

        let fm = FileManager.default
        let token = String(UUID().uuidString.prefix(8))
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let cachesBase = home.appendingPathComponent("Library/Caches/sweep-selftest-\(token)", isDirectory: true)
        let trashBase = home.appendingPathComponent(".Trash/sweep-selftest-\(token)", isDirectory: true)
        let supportBase = home.appendingPathComponent("library/application support/sweep-selftest-\(token)", isDirectory: true)

        var failures = 0

        func check(_ label: String, _ ok: Bool, _ detail: String) {
            let padded = label.padding(toLength: 22, withPad: " ", startingAt: 0)
            print("\(padded)\(detail)")
            if !ok { failures += 1 }
        }

        func makeFixture(at root: URL, name: String) -> URL {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: dir.appendingPathComponent("sample-\(token).bin").path(percentEncoded: false), contents: Data(count: 1_048_576))
            return dir
        }

        try? fm.createDirectory(at: cachesBase, withIntermediateDirectories: true)
        try? fm.createDirectory(at: trashBase, withIntermediateDirectories: true)

        let trashFixture = makeFixture(at: cachesBase, name: "trashed-\(token)")
        let trashItem = ScanItem(url: trashFixture, root: cachesBase, size: DiskScanner.size(of: trashFixture), isDirectory: true, modified: nil, isSelected: true)
        let trashReport = Cleaner.clean(items: [trashItem], category: .caches)
        let trashedGone = !fm.fileExists(atPath: trashFixture.path(percentEncoded: false))
        check("move-to-trash:", trashReport.removedIDs.count == 1 && trashReport.failures.isEmpty && trashedGone && !trashReport.permanent,
              "removed=\(trashReport.removedIDs.count) failures=\(trashReport.failures.count) gone=\(trashedGone) permanent=\(trashReport.permanent)")

        let outsideFixture = makeFixture(at: cachesBase, name: "outside-\(token)")
        let outsideItem = ScanItem(url: outsideFixture, root: cachesBase.appendingPathComponent("other-root"), size: 0, isDirectory: true, modified: nil, isSelected: true)
        let outsideReport = Cleaner.clean(items: [outsideItem], category: .caches)
        let outsideIntact = fm.fileExists(atPath: outsideFixture.path(percentEncoded: false))
        check("outside-root:", outsideReport.removedIDs.isEmpty && outsideReport.failures.count == 1 && outsideIntact,
              "removed=\(outsideReport.removedIDs.count) failures=\(outsideReport.failures.count) intact=\(outsideIntact)")

        let fakeTrashItem = ScanItem(url: outsideFixture, root: cachesBase, size: 0, isDirectory: true, modified: nil, isSelected: true)
        let fakeTrashReport = Cleaner.clean(items: [fakeTrashItem], category: .trash)
        let fakeIntact = fm.fileExists(atPath: outsideFixture.path(percentEncoded: false))
        check("trash-outside:", fakeTrashReport.removedIDs.isEmpty && fakeTrashReport.failures.count == 1 && fakeIntact,
              "removed=\(fakeTrashReport.removedIDs.count) failures=\(fakeTrashReport.failures.count) intact=\(fakeIntact)")

        let emptyFixture = makeFixture(at: trashBase, name: "emptied-\(token)")
        let emptyItem = ScanItem(url: emptyFixture, root: trashBase, size: DiskScanner.size(of: emptyFixture), isDirectory: true, modified: nil, isSelected: true)
        let emptyReport = Cleaner.clean(items: [emptyItem], category: .trash)
        let emptiedGone = !fm.fileExists(atPath: emptyFixture.path(percentEncoded: false))
        check("empty-trash:", emptyReport.removedIDs.count == 1 && emptyReport.failures.isEmpty && emptiedGone && emptyReport.permanent,
              "removed=\(emptyReport.removedIDs.count) failures=\(emptyReport.failures.count) gone=\(emptiedGone) permanent=\(emptyReport.permanent)")

        let symlinkTarget = makeFixture(at: cachesBase, name: "symlink-target-\(token)")
        let symlinkRoot = cachesBase.appendingPathComponent("symlink-root-\(token)")
        try? fm.removeItem(at: symlinkRoot)
        _ = try? fm.createSymbolicLink(at: symlinkRoot, withDestinationURL: symlinkTarget)
        let symlinkIssue = DiskScanner.rootValidationFailure(for: symlinkRoot, missingIsError: false)?.issue
        check("symlink-root:", symlinkIssue == .symlink, "issue=\(symlinkIssue?.message ?? "none")")

        let escapeFile = cachesBase.appendingPathComponent("escape-\(token).bin")
        fm.createFile(atPath: escapeFile.path(percentEncoded: false), contents: Data(count: 4096))
        let escapeLink = trashBase.appendingPathComponent("linkdir-\(token)")
        try? fm.removeItem(at: escapeLink)
        _ = try? fm.createSymbolicLink(at: escapeLink, withDestinationURL: cachesBase)
        let escapedURL = escapeLink.appendingPathComponent("escape-\(token).bin")
        let escapedItem = ScanItem(url: escapedURL, root: cachesBase, size: 4096, isDirectory: false, modified: nil, isSelected: true)
        let escapedReport = Cleaner.clean(items: [escapedItem], category: .trash)
        let escapeIntact = fm.fileExists(atPath: escapeFile.path(percentEncoded: false))
        check("trash-resolved:", escapedReport.removedIDs.isEmpty && escapedReport.failures.count == 1 && escapeIntact,
              "removed=\(escapedReport.removedIDs.count) failures=\(escapedReport.failures.count) intact=\(escapeIntact)")

        let fileLinkURL = cachesBase.appendingPathComponent("file-link-\(token)")
        try? fm.removeItem(at: fileLinkURL)
        _ = try? fm.createSymbolicLink(at: fileLinkURL, withDestinationURL: symlinkTarget)
        let fileLinkItem = ScanItem(url: fileLinkURL, root: cachesBase, size: 0, isDirectory: false, modified: nil, isSelected: true)
        let fileLinkReason = Cleaner.refusalReason(for: fileLinkItem, category: .caches)
        check("refusal-symlink:", fileLinkReason == .symlink, "issue=\(fileLinkReason?.message ?? "none")")

        let missingItem = ScanItem(url: cachesBase.appendingPathComponent("missing-\(token)"), root: cachesBase, size: 0, isDirectory: false, modified: nil, isSelected: true)
        let missingReason = Cleaner.refusalReason(for: missingItem, category: .caches)
        check("refusal-missing-path:", missingReason == .invalidPath, "issue=\(missingReason?.message ?? "none")")

        let sharedBase = URL(fileURLWithPath: "/Users/Shared/sweep-selftest-\(token)", isDirectory: true)
        try? fm.createDirectory(at: sharedBase, withIntermediateDirectories: true)
        let sharedFile = sharedBase.appendingPathComponent("item-\(token).bin")
        fm.createFile(atPath: sharedFile.path(percentEncoded: false), contents: Data(count: 4096))
        let sharedItem = ScanItem(url: sharedFile, root: sharedBase, size: 4096, isDirectory: false, modified: nil, isSelected: true)
        let sharedReason = Cleaner.refusalReason(for: sharedItem, category: .caches)
        check("refusal-foreign-root:", sharedReason == .unauthorizedRoot, "issue=\(sharedReason?.message ?? "none")")
        try? fm.removeItem(at: sharedBase)

        let slashRefused = !DiskScanner.isAllowedLargeFileRoot(URL(fileURLWithPath: "/"))
        let usersRefused = !DiskScanner.isAllowedLargeFileRoot(URL(fileURLWithPath: "/Users"))
        let volumesRefused = !DiskScanner.isAllowedLargeFileRoot(URL(fileURLWithPath: "/Volumes"))
        let homeRefused = !DiskScanner.isAllowedLargeFileRoot(home)
        let libraryRefused = !DiskScanner.isAllowedLargeFileRoot(URL(fileURLWithPath: home.path(percentEncoded: false) + "/library"))
        let homeChildAllowed = DiskScanner.isAllowedLargeFileRoot(home.appendingPathComponent("selftest-\(token)", isDirectory: true))
        check("large-roots:", slashRefused && usersRefused && volumesRefused && homeRefused && libraryRefused && homeChildAllowed,
              "slash=\(slashRefused) users=\(usersRefused) volumes=\(volumesRefused) home=\(homeRefused) library=\(libraryRefused) child=\(homeChildAllowed)")

        let caseSensitive = (try? home.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
        if caseSensitive {
            print("case-fold:          skipped (case-sensitive volume)")
        } else {
            try? fm.createDirectory(at: supportBase, withIntermediateDirectories: true)
            let caseFile = supportBase.appendingPathComponent("case-\(token).bin")
            fm.createFile(atPath: caseFile.path(percentEncoded: false), contents: Data(count: 4096))
            let caseItem = ScanItem(url: caseFile, root: supportBase, size: 4096, isDirectory: false, modified: nil, isSelected: true)
            let caseReport = Cleaner.clean(items: [caseItem], category: .largeFiles)
            let caseIntact = fm.fileExists(atPath: caseFile.path(percentEncoded: false))
            check("case-fold:", caseReport.removedIDs.isEmpty && caseReport.failures.count == 1 && caseIntact,
                  "removed=\(caseReport.removedIDs.count) failures=\(caseReport.failures.count) intact=\(caseIntact)")
            try? fm.removeItem(at: supportBase)
        }

        let appBundle = trashBase.appendingPathComponent("sweep-selftest-\(token).app", isDirectory: true)
        try? fm.createDirectory(at: appBundle, withIntermediateDirectories: true)
        fm.createFile(atPath: appBundle.appendingPathComponent("payload-\(token).bin").path(percentEncoded: false), contents: Data(count: 1024))
        let appSafety = DiskScanner.protectedSafety(for: appBundle, category: .trash)
        let appItem = ScanItem(url: appBundle, root: trashBase, size: 1024, isDirectory: true, modified: nil, isSelected: true, safety: appSafety ?? .safe)
        let appReport = Cleaner.clean(items: [appItem], category: .trash)
        let appIntact = fm.fileExists(atPath: appBundle.path(percentEncoded: false))
        check("trash-app-protected:", appSafety == .protected("app") && appReport.removedIDs.isEmpty && appReport.failures.count == 1 && appIntact,
              "safety=\(appSafety == .protected("app")) removed=\(appReport.removedIDs.count) failures=\(appReport.failures.count) intact=\(appIntact)")

        let model = AppModel()
        var selectionResult = CategoryResult()
        let safeItem = ScanItem(url: cachesBase.appendingPathComponent("safe-\(token).bin"), root: cachesBase, size: 16, isDirectory: false, modified: nil, isSelected: false, safety: .safe)
        let flaggedItem = ScanItem(url: cachesBase.appendingPathComponent("flagged-\(token).bin"), root: cachesBase, size: 16, isDirectory: false, modified: nil, isSelected: true, safety: .caution(.archiveOrDatabase))
        selectionResult.replaceItems([safeItem, flaggedItem])
        model.results[.caches] = selectionResult
        model.toggleSelectAll(in: .caches)
        let firstItems = model.result(for: .caches).items
        let safeSelected = firstItems.first { $0.id == safeItem.id }?.isSelected == true
        let flaggedPreserved = firstItems.first { $0.id == flaggedItem.id }?.isSelected == true
        model.toggleSelectAll(in: .caches)
        let allCleared = model.result(for: .caches).items.allSatisfy { !$0.isSelected }
        check("select-all-preserve:", safeSelected && flaggedPreserved, "safe=\(safeSelected) flagged=\(flaggedPreserved)")
        check("select-all-clear:", allCleared, "allCleared=\(allCleared)")

        try? fm.removeItem(at: cachesBase)
        try? fm.removeItem(at: trashBase)
        try? fm.removeItem(at: supportBase)

        if let entries = try? fm.contentsOfDirectory(at: home.appendingPathComponent(".Trash"), includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.contains(token) {
                try? fm.removeItem(at: entry)
            }
        }

        print("selftest:           \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--scan") else { return }

        let names = Array(arguments.suffix(from: arguments.index(after: flagIndex)))
        let categories: [SpaceCategory] = names.isEmpty
            ? SpaceCategory.allCases
            : names.compactMap { SpaceCategory(rawValue: $0) }

        guard !categories.isEmpty else {
            print("Categories: \(SpaceCategory.allCases.map(\.rawValue).joined(separator: ", "))")
            exit(1)
        }

        _ = NSApplication.shared
        let runningApps = NSWorkspace.shared.runningApplications
        let runningIdentifiers = Set(runningApps.compactMap(\.bundleIdentifier) + runningApps.compactMap(\.localizedName))

        let finished = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            defer { finished.signal() }
            for category in categories {
                let started = Date()
                let output = await DiskScanner.scan(
                    category: category,
                    threshold: 100 * 1024 * 1024,
                    oldOnly: false,
                    customRoot: nil,
                    runningBundleIDs: runningIdentifiers,
                    progress: { _ in }
                )
                let elapsed = Date().timeIntervalSince(started)
                let total = output.items.reduce(Int64(0)) { $0 + $1.size }
                print("\(category.rawValue)\t\(output.root)\t\(output.items.count) items\t\(total) bytes\t\(String(format: "%.1fs", elapsed))")
                for item in output.items.prefix(12) {
                    let tag: String
                    if item.safety.isProtected {
                        tag = "protected"
                    } else if let reason = item.safety.cautionReason {
                        tag = "caution:\(reason.headlessName)"
                    } else {
                        tag = "safe"
                    }
                    print("   [\(tag)] selected=\(item.isSelected) \(item.size)\t\(item.path)")
                }
                for failure in output.diagnostics.rootFailures {
                    print("   [unreadable] \(failure.path): \(failure.issue.message)")
                }
            }
        }
        finished.wait()
        exit(0)
    }
}
