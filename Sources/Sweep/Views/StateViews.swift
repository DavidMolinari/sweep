import SwiftUI

struct EmptyStateView: View {
    let category: SpaceCategory
    let alreadyScanned: Bool
    let rescan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            IconMedallion(
                symbol: alreadyScanned ? "checkmark" : category.symbol,
                style: alreadyScanned ? .success : CategoryStyle.of(category),
                size: 64
            )

            VStack(spacing: 6) {
                Text(alreadyScanned ? "empty.nothingToClean.title" : "empty.notScanned.title")
                    .font(.title3.weight(.semibold))
                Text(alreadyScanned ? String(localized: "empty.nothingToClean.message") : String(localized: "empty.notScanned.message"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(alreadyScanned ? "action.rescan" : "action.scan") {
                rescan()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let category: SpaceCategory
    let liveBytes: Int64
    let cancel: () -> Void

    var body: some View {
        let style = CategoryStyle.of(category)

        VStack(spacing: 18) {
            ZStack {
                IconMedallion(symbol: category.symbol, style: style, size: 68)
                SpinningRing(size: 118, lineWidth: 3.5, gradient: style.angularGradient)
            }
            .frame(height: 136)

            VStack(spacing: 6) {
                Text("status.scanning")
                    .font(.title3.weight(.semibold))
                Text(liveBytes > 0 ? String(localized: "status.scanned \(liveBytes.formatted(.byteCount(style: .file)))") : category.subtitle)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(liveBytes)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: liveBytes)
            }

            Button("action.cancel", action: cancel)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailureView: View {
    @EnvironmentObject private var model: AppModel
    let message: String
    var showsFullDiskAccessAction: Bool = false
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            IconMedallion(symbol: "exclamationmark.triangle.fill", style: .warning, size: 64)

            VStack(spacing: 6) {
                Text("failure.title")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button("action.retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(BrandPalette.Semantic.caution)

                if showsFullDiskAccessAction {
                    Button("settings.storage.fullDiskAccess.open") {
                        model.openFullDiskAccessSettings()
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PartialScanBanner: View {
    @EnvironmentObject private var model: AppModel
    var message: String = ""
    var diagnostics: DiskScanner.ScanDiagnostics = .none
    let retry: () -> Void

    private var showsFullDiskAccessAction: Bool {
        diagnostics.rootFailures.contains { failure in
            if case .unreadable = failure.issue { return true }
            return false
        }
    }

    private var detailLines: [String] {
        var lines = diagnostics.rootFailures.prefix(2).map { failure in
            "\(failure.path) — \(Self.label(for: failure.issue))"
        }
        var summary: [String] = []
        let hiddenRoots = diagnostics.rootFailures.count - lines.count
        if hiddenRoots > 0 {
            summary.append(L10n.skippedRoots(hiddenRoots))
        }
        if diagnostics.skippedItems > 0 {
            summary.append(L10n.skippedItems(diagnostics.skippedItems))
        }
        if !summary.isEmpty {
            lines.append(summary.joined(separator: " · "))
        }
        if lines.isEmpty, !message.isEmpty {
            lines.append(message)
        }
        return lines
    }

    private static func label(for issue: DiskScanner.ScanDiagnostics.RootIssue) -> String {
        switch issue {
        case .symlink: String(localized: "scan.issue.symlink")
        case .notDirectory: String(localized: "scan.issue.notDirectory")
        case .missing: String(localized: "scan.issue.missing")
        case .notAllowed: String(localized: "scan.issue.notAllowed")
        case .unreadable(let detail): detail
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.Semantic.caution)

            VStack(alignment: .leading, spacing: 2) {
                Text("scan.partial.title")
                    .font(.caption.weight(.semibold))
                ForEach(detailLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(line)
                }
            }

            Spacer(minLength: 8)

            if showsFullDiskAccessAction {
                Button("settings.storage.fullDiskAccess.open") {
                    model.openFullDiskAccessSettings()
                }
                .controlSize(.small)
            }

            Button("action.retry", action: retry)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: BrandPalette.Radius.chip, style: .continuous)
                .fill(BrandPalette.Semantic.caution.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BrandPalette.Radius.chip, style: .continuous)
                .strokeBorder(BrandPalette.Semantic.caution.opacity(0.25), lineWidth: 0.8)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}
