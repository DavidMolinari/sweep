import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            Section("sidebar.section.cleaning") {
                ForEach(SpaceCategory.allCases) { category in
                    SidebarRow(category: category)
                        .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }
}

struct SidebarFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        }
                    Text(model.freeSpace.map { String(localized: "sidebar.freeSpace \($0.formatted(.byteCount(style: .file)))") } ?? String(localized: "sidebar.freeSpace.unavailable"))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    model.openFullDiskAccessSettings()
                } label: {
                    Label("sidebar.fullDiskAccess", systemImage: "lock.shield")
                        .font(.callout)
                }
                .buttonStyle(.link)
                .help("sidebar.fullDiskAccess.help")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.ultraThinMaterial)
    }
}

struct SidebarRow: View {
    @EnvironmentObject private var model: AppModel
    let category: SpaceCategory

    var body: some View {
        let result = model.result(for: category)
        let style = CategoryStyle.of(category)

        HStack(spacing: 10) {
            GradientIconTile(symbol: category.symbol, style: style, size: 26)
                .opacity(result.state == .scanning ? 0.85 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.system(.body, weight: .medium))
                if result.state == .scanning {
                    Text("status.scanning")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if result.state == .scanning {
                SpinningRing(size: 15, lineWidth: 2, gradient: style.angularGradient)
            } else if !result.items.isEmpty {
                Text(result.totalSize.formatted(.byteCount(style: .file)))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: result.totalSize)
            }
        }
        .padding(.vertical, 3)
    }
}
