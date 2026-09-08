import Foundation

enum L10n {
    static func itemCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "items.count.one \(count)")
            : String(localized: "items.count.other \(count)")
    }

    static func flaggedCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "items.flagged.one \(count)")
            : String(localized: "items.flagged.other \(count)")
    }

    static func selectedCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "items.selected.one \(count)")
            : String(localized: "items.selected.other \(count)")
    }

    static func removedCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "items.removed.one \(count)")
            : String(localized: "items.removed.other \(count)")
    }

    static func failureCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "items.failures.one \(count)")
            : String(localized: "items.failures.other \(count)")
    }

    static func allItems(_ count: Int) -> String {
        String(localized: "filter.all \(count)")
    }

    static func pair(_ first: String, _ second: String) -> String {
        String(localized: "summary.pair \(first) \(second)")
    }
}
