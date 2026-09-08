import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let category: SpaceCategory

    @State private var showOnlyFlagged = false

    var body: some View {
        let result = model.result(for: category)
        let flagged = result.items.filter { $0.safety.warning != nil }
        let runningCount = result.items.filter { $0.safety.cautionReason == .appRunning }.count
        let shownItems = showOnlyFlagged && !flagged.isEmpty ? flagged : result.items

        VStack(spacing: 0) {
            CategoryHeader(
                category: category,
                result: result,
                liveBytes: model.liveBytes[category] ?? 0
            )
            if category == .largeFiles {
                LargeFilesControls()
            }
            if result.state == .done, !flagged.isEmpty {
                FlaggedFilterBar(
                    showOnlyFlagged: $showOnlyFlagged,
                    total: result.items.count,
                    flagged: flagged.count,
                    runningCount: runningCount,
                    rescan: { model.scan(category) }
                )
            }
            content(for: result, items: shownItems)
            CleanBar(
                category: category,
                result: result,
                flaggedCount: flagged.count,
                showOnlyFlagged: $showOnlyFlagged
            )
        }
        .background(detailWash)
        .navigationTitle(category.title)
        .animation(.easeInOut(duration: 0.22), value: result.state)
    }

    private var detailWash: some View {
        let style = CategoryStyle.of(category)
        return LinearGradient(
            colors: [style.colors[0].opacity(0.07), .clear],
            startPoint: .top,
            endPoint: .init(x: 0.5, y: 0.42)
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(for result: CategoryResult, items: [ScanItem]) -> some View {
        switch result.state {
        case .idle:
            EmptyStateView(category: category, alreadyScanned: false) {
                model.scan(category)
            }
        case .scanning:
            ScanningView(category: category, liveBytes: model.liveBytes[category] ?? 0) {
                model.cancelScan(category)
            }
        case .done:
            if result.items.isEmpty {
                EmptyStateView(category: category, alreadyScanned: true) {
                    model.scan(category)
                }
            } else {
                ItemListView(category: category, items: items)
            }
        case .failed(let message):
            FailureView(message: message) {
                model.scan(category)
            }
        }
    }
}

struct FlaggedFilterBar: View {
    @Binding var showOnlyFlagged: Bool
    let total: Int
    let flagged: Int
    let runningCount: Int
    let rescan: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("filter.title", selection: $showOnlyFlagged) {
                Text(verbatim: L10n.allItems(total)).tag(false)
                Text(verbatim: L10n.flaggedCount(flagged)).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            if showOnlyFlagged, runningCount > 0 {
                Text("filter.runningHint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    rescan()
                } label: {
                    Label("action.rescan", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct CategoryHeader: View {
    let category: SpaceCategory
    let result: CategoryResult
    let liveBytes: Int64

    var body: some View {
        let style = CategoryStyle.of(category)

        HStack(alignment: .center, spacing: 16) {
            ZStack {
                GradientIconTile(symbol: category.symbol, style: style, size: 56)
                if result.state == .scanning {
                    SpinningRing(size: 72, lineWidth: 3, gradient: style.angularGradient)
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.system(.title2, weight: .semibold))
                Text(result.rootDescription.isEmpty ? category.subtitle : result.rootDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface(cornerRadius: 18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.colors[0].opacity(0.16), style.colors[1].opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var trailing: some View {
        if result.state == .scanning {
            VStack(alignment: .trailing, spacing: 2) {
                Text(liveBytes.formatted(.byteCount(style: .file)))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(liveBytes)))
                    .animation(.easeOut(duration: 0.25), value: liveBytes)
                Text("status.scanning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !result.items.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.totalSize.formatted(.byteCount(style: .file)))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(result.totalSize)))
                    .animation(.snappy, value: result.totalSize)
                Text(itemCountLabel(result.items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func itemCountLabel(_ count: Int) -> String {
        L10n.itemCount(count)
    }
}

struct ItemListView: View {
    @EnvironmentObject private var model: AppModel
    let category: SpaceCategory
    let items: [ScanItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    ItemRow(item: item) {
                        model.toggleSelection(of: item, in: category)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

struct ItemRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: ScanItem
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                checkbox

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let reason = item.safety.cautionReason {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(reason.message)
                                .lineLimit(2)
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 12)

                badge

                if let modified = item.modified {
                    Text(modified, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(minWidth: 88, alignment: .trailing)
                }

                Text(item.size.formatted(.byteCount(style: .file)))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 76, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.safety.isSelectable)
        .opacity(item.safety.isSelectable ? 1 : 0.72)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .animation(.easeOut(duration: 0.18), value: item.isSelected)
        .contextMenu {
            Button("action.revealInFinder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("action.copyPath") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
        }
    }

    private var checkbox: some View {
        Group {
            if item.safety.isSelectable {
                ZStack {
                    Circle()
                        .fill(item.isSelected ? Color.accentColor : Color.clear)
                    Circle()
                        .strokeBorder(item.isSelected ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.5)
                    if item.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 18, height: 18)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 20, height: 20)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: item.isSelected)
    }

    @ViewBuilder
    private var badge: some View {
        if item.safety.isProtected {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(Color.primary.opacity(0.07))
                }
                .help("safety.protected.help")
                .accessibilityLabel("safety.protected.label")
        } else if let warning = item.safety.warning {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(Color.orange.opacity(0.15))
                }
                .help(warning)
                .accessibilityLabel("safety.caution.label")
        }
    }

    private var backgroundFill: Color {
        if item.isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }
        if isHovering {
            return Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
        }
        return .clear
    }
}

struct CleanBar: View {
    @EnvironmentObject private var model: AppModel
    let category: SpaceCategory
    let result: CategoryResult
    let flaggedCount: Int
    @Binding var showOnlyFlagged: Bool

    var body: some View {
        let selectable = result.items.filter(\.safety.isSelectable)
        let allSelected = !selectable.isEmpty && selectable.allSatisfy(\.isSelected)

        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            HStack(spacing: 12) {
                if !result.items.isEmpty {
                    Button(allSelected ? "action.deselectAll" : "action.selectAll") {
                        model.toggleSelectAll(in: category)
                    }
                    .controlSize(.large)
                    .help(flaggedCount > 0
                          ? "cleanbar.selectAll.warningHelp"
                          : "cleanbar.selectAll.help")
                }

                if flaggedCount > 0 {
                    Button {
                        showOnlyFlagged.toggle()
                    } label: {
                        Label(L10n.flaggedCount(flaggedCount), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule().fill(Color.orange.opacity(showOnlyFlagged ? 0.28 : 0.14))
                            }
                    }
                    .buttonStyle(.plain)
                    .help(showOnlyFlagged ? "cleanbar.flagged.hideHelp" : "cleanbar.flagged.help")
                }

                Spacer(minLength: 8)

                if !result.items.isEmpty {
                    Text(verbatim: L10n.pair(L10n.selectedCount(result.selectedItems.count), result.selectedSize.formatted(.byteCount(style: .file))))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(Color.primary.opacity(0.05))
                        }
                        .contentTransition(.numericText())
                        .animation(.snappy, value: result.selectedSize)
                }

                Button {
                    model.requestClean(category)
                } label: {
                    Label(category.isPermanentDeletion ? "cleanbar.emptyTrash" : "cleanbar.clean",
                          systemImage: category.isPermanentDeletion ? "trash.slash" : "sparkles")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(category.isPermanentDeletion ? .red : .accentColor)
                .disabled(result.selectedItems.isEmpty || result.state == .scanning)
                .help(category.isPermanentDeletion
                      ? "cleanbar.emptyTrash.help"
                      : "cleanbar.clean.help")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}
