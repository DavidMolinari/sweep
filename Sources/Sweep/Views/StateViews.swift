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
                Text(alreadyScanned ? String(localized: "empty.nothingToClean.message") : category.subtitle)
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
                    .contentTransition(.numericText(value: Double(liveBytes)))
                    .animation(.easeOut(duration: 0.25), value: liveBytes)
            }

            Button("action.cancel", action: cancel)
                .controlSize(.large)
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
                .tint(.orange)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
