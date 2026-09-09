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
    let message: String
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

            Button("action.retry", action: retry)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(BrandPalette.Semantic.caution)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PartialScanBanner: View {
    @EnvironmentObject private var model: AppModel
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandPalette.Semantic.caution)

            VStack(alignment: .leading, spacing: 1) {
                Text("scan.partial.title")
                    .font(.caption.weight(.semibold))
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button("settings.storage.fullDiskAccess.open") {
                model.openFullDiskAccessSettings()
            }
            .controlSize(.small)

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
        .accessibilityElement(children: .combine)
    }
}
