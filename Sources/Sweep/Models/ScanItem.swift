import Foundation

enum CautionReason: Equatable {
    case appRunning
    case debugSymbols
    case aiModels
    case archiveOrDatabase

    var message: String {
        switch self {
        case .appRunning: String(localized: "safety.caution.running")
        case .debugSymbols: String(localized: "safety.caution.debugSymbols")
        case .aiModels: String(localized: "safety.caution.aiModels")
        case .archiveOrDatabase: String(localized: "safety.caution.archive")
        }
    }

    var headlessName: String {
        switch self {
        case .appRunning: "app-running"
        case .debugSymbols: "debug-symbols"
        case .aiModels: "ai-models"
        case .archiveOrDatabase: "archive-or-database"
        }
    }
}

enum ItemSafety: Equatable {
    case safe
    case caution(CautionReason)
    case protected(String)

    var isSafe: Bool {
        if case .safe = self { return true }
        return false
    }

    var isSelectable: Bool {
        if case .protected = self { return false }
        return true
    }

    var isProtected: Bool {
        if case .protected = self { return true }
        return false
    }

    var warning: String? {
        if case .caution(let reason) = self { return reason.message }
        return nil
    }

    var cautionReason: CautionReason? {
        if case .caution(let reason) = self { return reason }
        return nil
    }
}

struct ScanItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let root: URL
    let size: Int64
    let isDirectory: Bool
    let modified: Date?
    var isSelected: Bool
    let safety: ItemSafety
    let name: String
    let path: String

    init(url: URL, root: URL, size: Int64, isDirectory: Bool, modified: Date?, isSelected: Bool, safety: ItemSafety = .safe) {
        self.id = UUID()
        self.url = url
        self.root = root
        self.size = size
        self.isDirectory = isDirectory
        self.modified = modified
        self.isSelected = isSelected
        self.safety = safety
        self.name = url.lastPathComponent
        self.path = url.path(percentEncoded: false)
    }

    static func == (lhs: ScanItem, rhs: ScanItem) -> Bool {
        lhs.id == rhs.id && lhs.isSelected == rhs.isSelected
    }
}
