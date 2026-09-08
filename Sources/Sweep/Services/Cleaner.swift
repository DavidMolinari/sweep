import Foundation

enum Cleaner {
    enum RefusalReason: Equatable {
        case symlink
        case invalidPath
        case protectedLocation
        case outsideScan
        case outsideTrash
        case unauthorizedRoot

        var message: String {
            switch self {
            case .symlink: String(localized: "refusal.symlink")
            case .invalidPath: String(localized: "refusal.invalidPath")
            case .protectedLocation: String(localized: "refusal.protectedLocation")
            case .outsideScan: String(localized: "refusal.outsideScan")
            case .outsideTrash: String(localized: "refusal.outsideTrash")
            case .unauthorizedRoot: String(localized: "refusal.unauthorizedRoot")
            }
        }
    }

    struct Report {
        var removedIDs: [UUID] = []
        var freed: Int64 = 0
        var failures: [String] = []
        var permanent = false
    }

    static func clean(items: [ScanItem], category: SpaceCategory) -> Report {
        var report = Report()
        report.permanent = category.isPermanentDeletion
        report.removedIDs.reserveCapacity(items.count)
        report.failures.reserveCapacity(items.count)
        let fm = FileManager.default

        for item in items {
            if Task.isCancelled { break }

            if item.safety.isProtected {
                report.failures.append(failureLine(item.name, String(localized: "refusal.protectedItem")))
                continue
            }

            if let refusal = refusalReason(for: item, category: category) {
                report.failures.append(failureLine(item.name, refusal.message))
                continue
            }

            do {
                if report.permanent {
                    try fm.removeItem(at: item.url)
                } else {
                    var resulting: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &resulting)
                }
                report.removedIDs.append(item.id)
                report.freed += item.size
            } catch {
                report.failures.append(failureLine(item.name, error.localizedDescription))
            }
        }
        return report
    }

    private static func failureLine(_ name: String, _ reason: String) -> String {
        String(localized: "clean.failure.reason \(name) \(reason)")
    }

    private static let forbiddenPaths: Set<String> = {
        let home = NSHomeDirectory()
        return [
            "/", home, home + "/Library", home + "/Documents", home + "/Desktop",
            home + "/Downloads", home + "/Projects", home + "/Movies", home + "/Music",
            home + "/Pictures", home + "/.Trash", "/Applications", "/System", "/Library",
            "/Users", "/private", "/bin", "/sbin", "/usr", "/etc", "/var", "/opt"
        ]
    }()

    private static let forbiddenPrefixes: [String] = {
        let home = NSHomeDirectory()
        return [
            "/System/", "/Library/", "/Applications/", "/private/", "/usr/", "/bin/",
            "/sbin/", "/etc/", "/var/", "/opt/",
            home + "/Library/Containers/",
            home + "/Library/Group Containers/",
            home + "/Library/Application Support/",
            home + "/Library/Mail/",
            home + "/Library/Messages/",
            home + "/Library/Safari/",
            home + "/Library/Photos/",
            home + "/Library/Keychains/",
            home + "/Library/Accounts/",
            home + "/Library/Calendars/",
            home + "/Library/Contacts/",
            home + "/Library/Mobile Documents/",
            home + "/Library/CloudStorage/"
        ]
    }()

    private static let symlinkKeys: Set<URLResourceKey> = [.isSymbolicLinkKey]

    private static func refusalReason(for item: ScanItem, category: SpaceCategory) -> RefusalReason? {
        let url = item.url

        let isSymlink = (try? url.resourceValues(forKeys: symlinkKeys))?.isSymbolicLink
        if isSymlink == true { return .symlink }

        let path = url.standardizedFileURL.path(percentEncoded: false)
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let resolvedRoot = item.root.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)

        guard url.pathComponents.count >= 4 else { return .invalidPath }
        if forbiddenPaths.contains(path) || forbiddenPaths.contains(resolvedPath) { return .protectedLocation }
        for prefix in forbiddenPrefixes where path.hasPrefix(prefix) || resolvedPath.hasPrefix(prefix) {
            return .protectedLocation
        }

        guard isDescendant(resolvedPath, of: resolvedRoot) else { return .outsideScan }

        if category == .trash {
            let trashRoot = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".Trash", isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            guard isDescendant(resolvedPath, of: trashRoot) else { return .outsideTrash }
        } else {
            let home = URL(fileURLWithPath: NSHomeDirectory())
                .resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            guard isDescendant(resolvedRoot, of: home) else { return .unauthorizedRoot }
        }

        return nil
    }

    private static func isDescendant(_ path: String, of root: String) -> Bool {
        let base = root.hasSuffix("/") ? root : root + "/"
        return path != root && path.hasPrefix(base)
    }
}
