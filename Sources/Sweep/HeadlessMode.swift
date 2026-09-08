import AppKit
import Foundation

enum HeadlessMode {
    static func runSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }

        let fm = FileManager.default
        let token = String(UUID().uuidString.prefix(8))
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let cachesBase = home.appendingPathComponent("Library/Caches/sweep-selftest-\(token)", isDirectory: true)
        let trashBase = home.appendingPathComponent(".Trash/sweep-selftest-\(token)", isDirectory: true)

        var failures = 0

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
        print("move-to-trash:      removed=\(trashReport.removedIDs.count) failures=\(trashReport.failures.count) gone=\(trashedGone)")
        if trashReport.removedIDs.count != 1 || !trashReport.failures.isEmpty || !trashedGone { failures += 1 }

        let outsideFixture = makeFixture(at: cachesBase, name: "outside-\(token)")
        let outsideItem = ScanItem(url: outsideFixture, root: cachesBase.appendingPathComponent("other-root"), size: 0, isDirectory: true, modified: nil, isSelected: true)
        let outsideReport = Cleaner.clean(items: [outsideItem], category: .caches)
        let outsideIntact = fm.fileExists(atPath: outsideFixture.path(percentEncoded: false))
        print("outside-root:       removed=\(outsideReport.removedIDs.count) failures=\(outsideReport.failures.count) intact=\(outsideIntact)")
        if outsideReport.removedIDs.count != 0 || outsideReport.failures.count != 1 || !outsideIntact { failures += 1 }

        let fakeTrashItem = ScanItem(url: outsideFixture, root: cachesBase, size: 0, isDirectory: true, modified: nil, isSelected: true)
        let fakeTrashReport = Cleaner.clean(items: [fakeTrashItem], category: .trash)
        let fakeIntact = fm.fileExists(atPath: outsideFixture.path(percentEncoded: false))
        print("trash-outside:      removed=\(fakeTrashReport.removedIDs.count) failures=\(fakeTrashReport.failures.count) intact=\(fakeIntact)")
        if fakeTrashReport.removedIDs.count != 0 || fakeTrashReport.failures.count != 1 || !fakeIntact { failures += 1 }

        let emptyFixture = makeFixture(at: trashBase, name: "emptied-\(token)")
        let emptyItem = ScanItem(url: emptyFixture, root: trashBase, size: DiskScanner.size(of: emptyFixture), isDirectory: true, modified: nil, isSelected: true)
        let emptyReport = Cleaner.clean(items: [emptyItem], category: .trash)
        let emptiedGone = !fm.fileExists(atPath: emptyFixture.path(percentEncoded: false))
        print("empty-trash:        removed=\(emptyReport.removedIDs.count) failures=\(emptyReport.failures.count) gone=\(emptiedGone) permanent=\(emptyReport.permanent)")
        if emptyReport.removedIDs.count != 1 || !emptyReport.failures.isEmpty || !emptiedGone || !emptyReport.permanent { failures += 1 }

        try? fm.removeItem(at: cachesBase)
        try? fm.removeItem(at: trashBase)

        if let entries = try? fm.contentsOfDirectory(at: home.appendingPathComponent(".Trash"), includingPropertiesForKeys: nil) {
            for entry in entries where entry.lastPathComponent.contains(token) {
                try? fm.removeItem(at: entry)
            }
        }

        exit(failures == 0 ? 0 : 1)
    }

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
        Task.detached {
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
            }
            finished.signal()
        }
        finished.wait()
        exit(0)
    }
}
