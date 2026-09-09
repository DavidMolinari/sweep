import AppKit
import Foundation
import SwiftUI

enum ScanState: Equatable {
    case idle
    case scanning
    case done
    case failed(String)
}

struct CategoryResult {
    private(set) var items: [ScanItem] = []
    var state: ScanState = .idle
    var scannedAt: Date?
    var rootDescription: String = ""
    var partialFailure: Bool = false
    var diagnostics: DiskScanner.ScanDiagnostics = .none

    private(set) var totalSize: Int64 = 0
    private(set) var selectedItems: [ScanItem] = []
    private(set) var selectedSize: Int64 = 0

    init() {}

    mutating func replaceItems(_ newItems: [ScanItem]) {
        items = newItems
        refreshTotals()
    }

    mutating func removeItems(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty, !items.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        refreshTotals()
    }

    mutating func mutateItems(_ body: (inout [ScanItem]) -> Void) {
        body(&items)
        refreshTotals()
    }

    private mutating func refreshTotals() {
        var total: Int64 = 0
        var selected: [ScanItem] = []
        selected.reserveCapacity(items.count)
        var selectedTotal: Int64 = 0
        for item in items {
            total += item.size
            if item.isSelected {
                selected.append(item)
                selectedTotal += item.size
            }
        }
        totalSize = total
        selectedItems = selected
        selectedSize = selectedTotal
    }
}

struct PendingClean: Identifiable {
    let id = UUID()
    let category: SpaceCategory
    let items: [ScanItem]
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct CleanReport: Identifiable {
    let id = UUID()
    let category: SpaceCategory
    let freed: Int64
    let movedToTrash: Int64
    let removed: Int
    let failures: [String]
    let permanent: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published var results: [SpaceCategory: CategoryResult] = [:]
    @Published var selection: SpaceCategory? = .caches
    @Published var liveBytes: [SpaceCategory: Int64] = [:]
    @Published var confirmation: PendingClean?
    @Published var report: CleanReport?
    @Published var freeSpace: Int64?

    @Published var largeThreshold: Int64 {
        didSet { UserDefaults.standard.set(Int(largeThreshold), forKey: Keys.threshold) }
    }

    @Published var largeOldOnly: Bool {
        didSet { UserDefaults.standard.set(largeOldOnly, forKey: Keys.oldOnly) }
    }

    @Published var largeCustomRoot: URL? {
        didSet { UserDefaults.standard.set(largeCustomRoot?.path(percentEncoded: false), forKey: Keys.root) }
    }

    static let defaultCategoryKey = "defaultCategory"

    private enum Keys {
        static let threshold = "largeThreshold"
        static let oldOnly = "largeOldOnly"
        static let root = "largeCustomRoot"
    }

    private static let freeSpaceKeys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]

    private var scans: [SpaceCategory: (id: UUID, task: Task<Void, Never>)] = [:]
    private var cleanTasks: [SpaceCategory: Task<Void, Never>] = [:]

    @Published private(set) var cleaningCategories: Set<SpaceCategory> = []

    init() {
        let stored = UserDefaults.standard.integer(forKey: Keys.threshold)
        largeThreshold = stored > 0 ? Int64(stored) : 100 * 1024 * 1024
        largeOldOnly = UserDefaults.standard.bool(forKey: Keys.oldOnly)
        if let path = UserDefaults.standard.string(forKey: Keys.root), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if DiskScanner.isAllowedLargeFileRoot(url) {
                largeCustomRoot = url
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.root)
            }
        }
        if let rawCategory = UserDefaults.standard.string(forKey: Self.defaultCategoryKey),
           let category = SpaceCategory(rawValue: rawCategory) {
            selection = category
        }
        refreshFreeSpace()
    }

    var isAnyScanning: Bool {
        !scans.isEmpty
    }

    var isAnyCleaning: Bool {
        !cleaningCategories.isEmpty
    }

    func isCleaning(_ category: SpaceCategory) -> Bool {
        cleaningCategories.contains(category)
    }

    func result(for category: SpaceCategory) -> CategoryResult {
        results[category] ?? CategoryResult()
    }

    func refreshFreeSpace() {
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: Self.freeSpaceKeys) {
            freeSpace = values.volumeAvailableCapacityForImportantUsage
        }
    }

    func scanSelected() {
        if let selection { scan(selection) }
    }

    func scanAll() {
        for category in SpaceCategory.allCases { scan(category) }
    }

    func scan(_ category: SpaceCategory) {
        guard scans[category] == nil else { return }

        var placeholder = results[category] ?? CategoryResult()
        placeholder.state = .scanning
        placeholder.replaceItems([])
        placeholder.rootDescription = ""
        placeholder.partialFailure = false
        placeholder.diagnostics = .none
        results[category] = placeholder
        liveBytes[category] = 0

        let threshold = largeThreshold
        let oldOnly = largeOldOnly
        let customRoot = largeCustomRoot
        let runningApps = NSWorkspace.shared.runningApplications
        let runningIdentifiers = Set(runningApps.compactMap(\.bundleIdentifier) + runningApps.compactMap(\.localizedName))
        let scanID = UUID()

        let task = Task { [weak self] in
            guard let self else { return }
            let output = await DiskScanner.scan(
                category: category,
                threshold: threshold,
                oldOnly: oldOnly,
                customRoot: customRoot,
                runningBundleIDs: runningIdentifiers
            ) { bytes in
                Task { @MainActor [weak self] in
                    guard let self, self.scans[category]?.id == scanID else { return }
                    self.liveBytes[category, default: 0] += bytes
                }
            }

            guard !Task.isCancelled, self.scans[category]?.id == scanID else { return }

            var result = self.results[category] ?? CategoryResult()
            result.diagnostics = output.diagnostics
            result.rootDescription = output.root
            if output.diagnostics.readNothing {
                result.state = .failed(Self.failureMessage(for: output.diagnostics))
                result.partialFailure = false
                result.replaceItems([])
            } else {
                result.state = .done
                result.partialFailure = output.diagnostics.hadErrors
                result.replaceItems(output.items)
                result.scannedAt = Date()
            }
            self.results[category] = result
            self.liveBytes[category] = 0
            self.scans[category] = nil
        }
        scans[category] = (scanID, task)
    }

    func cancelScan(_ category: SpaceCategory) {
        guard let entry = scans[category] else { return }
        entry.task.cancel()
        scans[category] = nil

        var result = results[category] ?? CategoryResult()
        result.state = .idle
        result.replaceItems([])
        result.rootDescription = ""
        result.partialFailure = false
        result.diagnostics = .none
        results[category] = result
        liveBytes[category] = 0
    }

    private static func failureMessage(for diagnostics: DiskScanner.ScanDiagnostics) -> String {
        let lines = diagnostics.rootFailures.prefix(3).map { failure in
            "\(failure.path): \(failure.issue.message)"
        }
        let suffix = diagnostics.rootFailures.count > 3 ? "\n…" : ""
        return lines.joined(separator: "\n") + suffix
    }

    func rescanIfDone(_ category: SpaceCategory) {
        guard let state = results[category]?.state else { return }
        switch state {
        case .done, .failed:
            scan(category)
        default:
            break
        }
    }

    func toggleSelection(of item: ScanItem, in category: SpaceCategory) {
        guard var result = results[category],
              let index = result.items.firstIndex(where: { $0.id == item.id }),
              result.items[index].safety.isSelectable else { return }
        result.mutateItems { $0[index].isSelected.toggle() }
        results[category] = result
    }

    func toggleSelectAll(in category: SpaceCategory) {
        guard var result = results[category], !result.items.isEmpty else { return }
        let safe = result.items.filter(\.safety.isSafe)
        let allSafeSelected = !safe.isEmpty && safe.allSatisfy(\.isSelected)

        result.mutateItems { items in
            for index in items.indices {
                if allSafeSelected {
                    if items[index].safety.isSelectable {
                        items[index].isSelected = false
                    }
                } else if items[index].safety.isSafe {
                    items[index].isSelected = true
                }
            }
        }
        results[category] = result
    }

    func requestClean(_ category: SpaceCategory) {
        guard !isCleaning(category) else { return }
        let items = result(for: category).selectedItems
        guard !items.isEmpty else { return }
        confirmation = PendingClean(category: category, items: items)
    }

    func performClean(_ pending: PendingClean) {
        confirmation = nil
        let category = pending.category
        let items = pending.items
        guard !items.isEmpty, cleanTasks[category] == nil else { return }

        cleaningCategories.insert(category)
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = Cleaner.clean(items: items, category: category)
            await self?.completeClean(category: category, outcome: outcome)
        }
        cleanTasks[category] = task
    }

    func cancelClean(_ category: SpaceCategory) {
        cleanTasks[category]?.cancel()
    }

    private func completeClean(category: SpaceCategory, outcome: Cleaner.Report) async {
        cleanTasks[category] = nil
        cleaningCategories.remove(category)

        if var result = results[category] {
            result.removeItems(withIDs: Set(outcome.removedIDs))
            results[category] = result
        }

        try? await Task.sleep(for: .milliseconds(350))
        report = CleanReport(
            category: category,
            freed: outcome.freed,
            movedToTrash: outcome.movedToTrash,
            removed: outcome.removedIDs.count,
            failures: outcome.failures,
            permanent: outcome.permanent
        )
        refreshFreeSpace()
    }

    func chooseLargeFilesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "panel.choose")
        panel.message = String(localized: "panel.chooseFolder.message")
        panel.directoryURL = largeCustomRoot ?? URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            guard DiskScanner.isAllowedLargeFileRoot(url) else {
                let alert = NSAlert()
                alert.messageText = String(localized: "alert.protectedFolder.title")
                alert.informativeText = String(localized: "alert.protectedFolder.message")
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "action.ok"))
                alert.runModal()
                return
            }
            largeCustomRoot = url
            rescanIfDone(.largeFiles)
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func resetPreferences() {
        largeThreshold = 100 * 1024 * 1024
        largeOldOnly = false
        largeCustomRoot = nil
        selection = .caches
        UserDefaults.standard.removeObject(forKey: Self.defaultCategoryKey)
        rescanIfDone(.largeFiles)
    }
}
