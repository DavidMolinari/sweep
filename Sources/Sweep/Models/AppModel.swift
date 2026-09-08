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

    private var tasks: [SpaceCategory: Task<Void, Never>] = [:]

    init() {
        let stored = UserDefaults.standard.integer(forKey: Keys.threshold)
        largeThreshold = stored > 0 ? Int64(stored) : 100 * 1024 * 1024
        largeOldOnly = UserDefaults.standard.bool(forKey: Keys.oldOnly)
        if let path = UserDefaults.standard.string(forKey: Keys.root), !path.isEmpty {
            largeCustomRoot = URL(fileURLWithPath: path)
        }
        if let rawCategory = UserDefaults.standard.string(forKey: Self.defaultCategoryKey),
           let category = SpaceCategory(rawValue: rawCategory) {
            selection = category
        }
        refreshFreeSpace()
    }

    var isAnyScanning: Bool {
        results.values.contains { $0.state == .scanning }
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
        guard tasks[category] == nil else { return }

        var placeholder = results[category] ?? CategoryResult()
        placeholder.state = .scanning
        placeholder.replaceItems([])
        placeholder.rootDescription = ""
        results[category] = placeholder
        liveBytes[category] = 0

        let threshold = largeThreshold
        let oldOnly = largeOldOnly
        let customRoot = largeCustomRoot
        let runningApps = NSWorkspace.shared.runningApplications
        let runningIdentifiers = Set(runningApps.compactMap(\.bundleIdentifier) + runningApps.compactMap(\.localizedName))

        let task = Task {
            let output = await DiskScanner.scan(
                category: category,
                threshold: threshold,
                oldOnly: oldOnly,
                customRoot: customRoot,
                runningBundleIDs: runningIdentifiers
            ) { bytes in
                Task { @MainActor in
                    self.liveBytes[category, default: 0] += bytes
                }
            }

            var result = self.results[category] ?? CategoryResult()
            if Task.isCancelled {
                result.state = .idle
                result.replaceItems([])
                result.rootDescription = ""
            } else {
                result.state = .done
                result.replaceItems(output.items)
                result.scannedAt = Date()
                result.rootDescription = output.root
            }
            self.results[category] = result
            self.liveBytes[category] = 0
            self.tasks[category] = nil
        }
        tasks[category] = task
    }

    func cancelScan(_ category: SpaceCategory) {
        tasks[category]?.cancel()
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
        let selectable = result.items.filter(\.safety.isSelectable)
        let allSelected = !selectable.isEmpty && selectable.allSatisfy(\.isSelected)

        result.mutateItems { items in
            for index in items.indices {
                guard items[index].safety.isSelectable else {
                    items[index].isSelected = false
                    continue
                }
                if allSelected {
                    items[index].isSelected = false
                } else {
                    items[index].isSelected = items[index].safety.isSafe
                }
            }
        }
        results[category] = result
    }

    func requestClean(_ category: SpaceCategory) {
        let items = result(for: category).selectedItems
        guard !items.isEmpty else { return }
        confirmation = PendingClean(category: category, items: items)
    }

    func performClean(_ pending: PendingClean) {
        confirmation = nil
        let items = pending.items
        let category = pending.category

        Task {
            let outcome = Cleaner.clean(items: items, category: category)
            if Task.isCancelled { return }

            if var result = self.results[category] {
                result.removeItems(withIDs: Set(outcome.removedIDs))
                self.results[category] = result
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            self.report = CleanReport(
                category: category,
                freed: outcome.freed,
                removed: outcome.removedIDs.count,
                failures: outcome.failures,
                permanent: outcome.permanent
            )
            self.refreshFreeSpace()
        }
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
