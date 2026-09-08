import AppKit
import Foundation

enum DiskScanner {
    typealias ProgressHandler = @Sendable (Int64) -> Void

    final class ProgressReporter: @unchecked Sendable {
        private let lock = NSLock()
        private let handler: ProgressHandler
        private var pending: Int64 = 0
        private var lastFlush = Date.distantPast

        init(handler: @escaping ProgressHandler) {
            self.handler = handler
        }

        func add(_ bytes: Int64) {
            lock.lock()
            pending += bytes
            let now = Date()
            if now.timeIntervalSince(lastFlush) >= 0.1 {
                let value = pending
                pending = 0
                lastFlush = now
                lock.unlock()
                handler(value)
            } else {
                lock.unlock()
            }
        }

        func flush() {
            lock.lock()
            let value = pending
            pending = 0
            lock.unlock()
            if value > 0 { handler(value) }
        }
    }

    private static let maxConcurrentScans = 8

    private static let metadataKeyArray: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    private static let metadataKeys = Set(metadataKeyArray)

    private static let sizeKeyArray: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    private static let sizeKeys = Set(sizeKeyArray)

    private static let childKeyArray: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .contentModificationDateKey
    ]

    private static let childKeys = Set(childKeyArray)

    private static let walkKeyArray: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    private static let walkKeys = Set(walkKeyArray)

    private static let modificationKeys: Set<URLResourceKey> = [.contentModificationDateKey]

    private static let skippedDirectoryNames: Set<String> = [
        "Library", "node_modules", "Pods", "build", "dist", "target",
        "venv", ".venv", "vendor", "Carthage", "DerivedData",
        ".git", ".gradle", ".cargo", ".npm", ".pnpm-store", ".yarn",
        ".cache", ".local", ".docker", ".orbstack", ".build", ".swiftpm"
    ]

    private static let projectMarkerNames: Set<String> = [
        ".git", ".svn", ".hg",
        "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
        "Cargo.toml", "Cargo.lock", "go.mod", "go.sum",
        "pyproject.toml", "setup.py", "requirements.txt", "Pipfile", "poetry.lock",
        "Gemfile", "composer.json", "mix.exs", "pubspec.yaml", "Podfile",
        "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts",
        "settings.gradle", "CMakeLists.txt", "Dockerfile",
        "docker-compose.yml", "docker-compose.yaml"
    ]

    private static let projectMarkerSuffixes = [
        ".xcodeproj", ".xcworkspace", ".sln", ".csproj", ".fsproj", ".podspec",
        ".prproj", ".aep", ".drp", ".fcpxml", ".blend", ".uproject",
        ".als", ".flp", ".ptx", ".cpr", ".rpp", ".c4d"
    ]

    private static let protectedExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "kext", "appex", "xpc",
        "photoslibrary", "photolibrary", "imovielibrary", "tvlibrary",
        "fcpbundle", "logicx", "band", "musiclibrary",
        "sparsebundle", "sparseimage", "vmwarevm", "pvm", "utm", "vbox",
        "vdi", "qcow2", "vhdx", "vmdk"
    ]

    private static let cautionExtensions: Set<String> = [
        "dmg", "iso", "img", "pkg", "mpkg",
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst",
        "sql", "sqlite", "sqlite3", "db", "db3", "dump", "realm", "mdb", "accdb"
    ]

    static func scan(
        category: SpaceCategory,
        threshold: Int64,
        oldOnly: Bool,
        customRoot: URL?,
        runningBundleIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async -> (items: [ScanItem], root: String) {
        let reporter = ProgressReporter(handler: progress)

        switch category {
        case .caches:
            let items = await scanChildren(
                of: userLibrary("Caches"),
                defaultSelected: true,
                runningBundleIDs: runningBundleIDs,
                reporter: reporter
            )
            reporter.flush()
            return (items, "~/Library/Caches")
        case .logs:
            let items = await scanChildren(
                of: userLibrary("Logs"),
                defaultSelected: true,
                runningBundleIDs: runningBundleIDs,
                reporter: reporter
            )
            reporter.flush()
            return (items, "~/Library/Logs")
        case .trash:
            let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
            let items = await scanChildren(
                of: root,
                defaultSelected: true,
                runningBundleIDs: [],
                reporter: reporter
            )
            reporter.flush()
            return (items, "~/.Trash")
        case .developer:
            let items = await scanDeveloperCaches(reporter: reporter)
            reporter.flush()
            return (items, String(localized: "root.developer"))
        case .largeFiles:
            let roots = (customRoot.map { [$0] } ?? defaultLargeFileRoots()).filter(isAllowedLargeFileRoot)
            let items = scanLargeFiles(roots: roots, threshold: threshold, oldOnly: oldOnly, reporter: reporter)
            reporter.flush()
            let label = customRoot == nil ? String(localized: "root.largeFiles.default") : roots.first?.path(percentEncoded: false) ?? ""
            return (items, label)
        }
    }

    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: metadataKeys) else { return 0 }
        if values.isSymbolicLink == true {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else { return 0 }
            return directorySize(of: url)
        }
        if values.isDirectory != true { return allocatedBytes(values) }
        return directorySize(of: url)
    }

    private static func directorySize(of url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: sizeKeyArray,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: sizeKeys) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true || values.isPackage == true { continue }
            total += allocatedBytes(values)
        }
        return total
    }

    private static func scanChildren(
        of root: URL,
        defaultSelected: Bool,
        runningBundleIDs: Set<String>,
        reporter: ProgressReporter
    ) async -> [ScanItem] {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: childKeyArray,
            options: []
        )) ?? []

        let runningTokens = runningTokens(from: runningBundleIDs)
        var slots = [ScanItem?](repeating: nil, count: children.count)

        await withTaskGroup(of: (Int, ScanItem?).self) { group in
            var next = 0
            let width = min(maxConcurrentScans, children.count)
            while next < width {
                let index = next
                let child = children[index]
                group.addTask {
                    (index, scanChild(child, root: root, defaultSelected: defaultSelected, tokens: runningTokens, reporter: reporter))
                }
                next += 1
            }
            while let (index, item) = await group.next() {
                slots[index] = item
                guard !Task.isCancelled, next < children.count else { continue }
                let index = next
                let child = children[index]
                group.addTask {
                    (index, scanChild(child, root: root, defaultSelected: defaultSelected, tokens: runningTokens, reporter: reporter))
                }
                next += 1
            }
        }

        return slots.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    private static func scanChild(
        _ child: URL,
        root: URL,
        defaultSelected: Bool,
        tokens: Set<String>,
        reporter: ProgressReporter
    ) -> ScanItem? {
        if Task.isCancelled { return nil }
        guard let values = try? child.resourceValues(forKeys: childKeys) else { return nil }
        if values.isSymbolicLink == true { return nil }

        let name = child.lastPathComponent
        let safety: ItemSafety
        if isRunning(name, tokens: tokens) {
            safety = .caution(.appRunning)
        } else {
            safety = .safe
        }

        let total = size(of: child)
        reporter.add(total)
        return ScanItem(
            url: child,
            root: root,
            size: total,
            isDirectory: values.isDirectory == true || values.isPackage == true,
            modified: values.contentModificationDate,
            isSelected: safety.isSafe && defaultSelected,
            safety: safety
        )
    }

    private static func scanDeveloperCaches(reporter: ProgressReporter) async -> [ScanItem] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let xcode = library.appendingPathComponent("Developer/Xcode", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)

        let entries: [(URL, ItemSafety)] = [
            (xcode.appendingPathComponent("DerivedData"), .safe),
            (xcode.appendingPathComponent("iOS DeviceSupport"), .caution(.debugSymbols)),
            (xcode.appendingPathComponent("watchOS DeviceSupport"), .caution(.debugSymbols)),
            (xcode.appendingPathComponent("tvOS DeviceSupport"), .caution(.debugSymbols)),
            (library.appendingPathComponent("Developer/CoreSimulator/Caches"), .safe),
            (caches.appendingPathComponent("Homebrew"), .safe),
            (caches.appendingPathComponent("CocoaPods"), .safe),
            (caches.appendingPathComponent("org.swift.swiftpm"), .safe),
            (caches.appendingPathComponent("go-build"), .safe),
            (caches.appendingPathComponent("pip"), .safe),
            (caches.appendingPathComponent("Yarn"), .safe),
            (caches.appendingPathComponent("node-gyp"), .safe),
            (caches.appendingPathComponent("electron"), .safe),
            (caches.appendingPathComponent("ms-playwright"), .safe),
            (home.appendingPathComponent(".npm/_cacache"), .safe),
            (home.appendingPathComponent(".yarn/berry/cache"), .safe),
            (home.appendingPathComponent(".pnpm-store"), .safe),
            (home.appendingPathComponent(".gradle/caches"), .safe),
            (home.appendingPathComponent(".cargo/registry/cache"), .safe),
            (home.appendingPathComponent(".cache/huggingface"), .caution(.aiModels))
        ]

        var slots = [ScanItem?](repeating: nil, count: entries.count)

        await withTaskGroup(of: (Int, ScanItem?).self) { group in
            var next = 0
            let width = min(maxConcurrentScans, entries.count)
            while next < width {
                let index = next
                let entry = entries[index]
                group.addTask {
                    (index, scanDeveloperEntry(entry.0, safety: entry.1, reporter: reporter))
                }
                next += 1
            }
            while let (index, item) = await group.next() {
                slots[index] = item
                guard !Task.isCancelled, next < entries.count else { continue }
                let index = next
                let entry = entries[index]
                group.addTask {
                    (index, scanDeveloperEntry(entry.0, safety: entry.1, reporter: reporter))
                }
                next += 1
            }
        }

        return slots.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    private static func scanDeveloperEntry(_ path: URL, safety: ItemSafety, reporter: ProgressReporter) -> ScanItem? {
        if Task.isCancelled { return nil }
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path.path(percentEncoded: false), isDirectory: &isDirectory) else { return nil }
        let total = size(of: path)
        guard total > 0 else { return nil }
        let modified = (try? path.resourceValues(forKeys: modificationKeys))?.contentModificationDate
        reporter.add(total)
        return ScanItem(
            url: path,
            root: path.deletingLastPathComponent(),
            size: total,
            isDirectory: isDirectory.boolValue,
            modified: modified,
            isSelected: safety.isSafe,
            safety: safety
        )
    }

    private struct LargeScanState {
        var found: [ScanItem] = []
        var visited = 0
        var threshold: Int64 = 0
        var cutoff: Date?
    }

    static func isAllowedLargeFileRoot(_ url: URL) -> Bool {
        let home = NSHomeDirectory()
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let forbidden = [
            home + "/Library", home + "/.Trash",
            "/System", "/Library", "/Applications", "/private", "/bin", "/usr", "/etc", "/var"
        ]
        for base in forbidden where path == base || path.hasPrefix(base + "/") {
            return false
        }
        return true
    }

    private static func defaultLargeFileRoots() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default
        return ["Downloads", "Desktop", "Documents", "Movies", "Pictures", "Music"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    private static func scanLargeFiles(roots: [URL], threshold: Int64, oldOnly: Bool, reporter: ProgressReporter) -> [ScanItem] {
        var state = LargeScanState()
        state.threshold = threshold
        state.cutoff = oldOnly ? Calendar.current.date(byAdding: .month, value: -6, to: Date()) : nil

        for root in roots {
            if Task.isCancelled { break }
            walkLargeFiles(root, root: root, isRoot: true, state: &state, reporter: reporter)
        }
        state.found.sort { $0.size > $1.size }
        return Array(state.found.prefix(500))
    }

    private static func walkLargeFiles(
        _ directory: URL,
        root: URL,
        isRoot: Bool,
        state: inout LargeScanState,
        reporter: ProgressReporter
    ) {
        if Task.isCancelled || state.visited > 4_000_000 { return }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: walkKeyArray,
            options: [.skipsHiddenFiles]
        ) else { return }
        state.visited += 1

        if !isRoot, isProjectFolder(entries) { return }

        for entry in entries {
            if Task.isCancelled { return }
            guard let values = try? entry.resourceValues(forKeys: walkKeys) else { continue }
            if values.isSymbolicLink == true { continue }

            if values.isDirectory == true {
                if values.isPackage == true {
                    let ext = entry.pathExtension.lowercased()
                    if protectedExtensions.contains(ext) { continue }
                    let total = size(of: entry)
                    guard total >= state.threshold else { continue }
                    let modified = (try? entry.resourceValues(forKeys: modificationKeys))?.contentModificationDate
                    guard matchesCutoff(modified, state.cutoff) else { continue }
                    state.found.append(ScanItem(
                        url: entry,
                        root: root,
                        size: total,
                        isDirectory: true,
                        modified: modified,
                        isSelected: false,
                        safety: safety(for: ext)
                    ))
                    reporter.add(total)
                    continue
                }
                if skippedDirectoryNames.contains(entry.lastPathComponent) { continue }
                walkLargeFiles(entry, root: root, isRoot: false, state: &state, reporter: reporter)
                continue
            }

            let ext = entry.pathExtension.lowercased()
            if protectedExtensions.contains(ext) { continue }
            let total = allocatedBytes(values)
            guard total >= state.threshold else { continue }
            let modified = (try? entry.resourceValues(forKeys: modificationKeys))?.contentModificationDate
            guard matchesCutoff(modified, state.cutoff) else { continue }
            state.found.append(ScanItem(
                url: entry,
                root: root,
                size: total,
                isDirectory: false,
                modified: modified,
                isSelected: false,
                safety: safety(for: ext)
            ))
            reporter.add(total)
        }
    }

    private static func isProjectFolder(_ entries: [URL]) -> Bool {
        for entry in entries {
            let name = entry.lastPathComponent
            if projectMarkerNames.contains(name) { return true }
            for suffix in projectMarkerSuffixes where name.hasSuffix(suffix) { return true }
        }
        return false
    }

    private static func safety(for ext: String) -> ItemSafety {
        cautionExtensions.contains(ext)
            ? .caution(.archiveOrDatabase)
            : .safe
    }

    private static func normalizeIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let genericTokens: Set<String> = [
        "client", "browser", "helper", "update", "updater",
        "desktop", "application", "service", "daemon", "agent",
        "apple", "system", "core", "macos",
        "settings", "share", "shared", "cache", "data", "media", "cloud", "files", "sync"
    ]

    private static func runningTokens(from identifiers: Set<String>) -> Set<String> {
        var tokens = Set<String>()
        for identifier in identifiers {
            let normalized = normalizeIdentifier(identifier)
            if normalized.count >= 4 { tokens.insert(normalized) }

            for component in identifier.split(separator: ".").dropFirst() {
                let token = normalizeIdentifier(String(component))
                if token.count >= 6, !genericTokens.contains(token) { tokens.insert(token) }
            }

            if let firstWord = identifier.split(separator: " ").first {
                let token = normalizeIdentifier(String(firstWord))
                if token.count >= 4, !genericTokens.contains(token) { tokens.insert(token) }
            }
        }
        return tokens
    }

    private static func isRunning(_ name: String, tokens: Set<String>) -> Bool {
        let normalized = normalizeIdentifier(name)
        if tokens.contains(normalized) { return true }

        if name.contains(".") {
            for component in name.split(separator: ".") {
                let token = normalizeIdentifier(String(component))
                if token.count >= 4, tokens.contains(token) { return true }
            }
            return false
        }

        return tokens.contains { $0.count >= 4 && normalized.contains($0) }
    }

    private static func matchesCutoff(_ date: Date?, _ cutoff: Date?) -> Bool {
        guard let cutoff else { return true }
        guard let date else { return true }
        return date <= cutoff
    }

    private static func allocatedBytes(_ values: URLResourceValues) -> Int64 {
        if let value = values.totalFileAllocatedSize { return Int64(value) }
        if let value = values.fileAllocatedSize { return Int64(value) }
        if let value = values.fileSize { return Int64(value) }
        return 0
    }

    private static func userLibrary(_ name: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }
}
