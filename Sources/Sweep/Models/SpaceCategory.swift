import SwiftUI

enum SpaceCategory: String, CaseIterable, Identifiable, Hashable {
    case caches
    case logs
    case trash
    case developer
    case largeFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches: String(localized: "category.caches.title")
        case .logs: String(localized: "category.logs.title")
        case .trash: String(localized: "category.trash.title")
        case .developer: String(localized: "category.developer.title")
        case .largeFiles: String(localized: "category.largeFiles.title")
        }
    }

    var subtitle: String {
        switch self {
        case .caches: String(localized: "category.caches.subtitle")
        case .logs: String(localized: "category.logs.subtitle")
        case .trash: String(localized: "category.trash.subtitle")
        case .developer: String(localized: "category.developer.subtitle")
        case .largeFiles: String(localized: "category.largeFiles.subtitle")
        }
    }

    var symbol: String {
        switch self {
        case .caches: "shippingbox"
        case .logs: "doc.plaintext"
        case .trash: "trash"
        case .developer: "hammer"
        case .largeFiles: "scalemass"
        }
    }

    var tint: Color {
        switch self {
        case .caches: .blue
        case .logs: .gray
        case .trash: .red
        case .developer: .purple
        case .largeFiles: .orange
        }
    }

    var isPermanentDeletion: Bool { self == .trash }
}
