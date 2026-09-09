import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .disabled(model.isCleaning(category))
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: result.state)
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

    private func showsFullDiskAccessAction(for result: CategoryResult) -> Bool {
        result.diagnostics.rootFailures.contains { failure in
            if case .unreadable = failure.issue { return true }
            return false
        }
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
                VStack(spacing: 0) {
                    if result.partialFailure {
                        PartialScanBanner(diagnostics: result.diagnostics) {
                            model.scan(category)
                        }
                    }
                    ItemListView(category: category, items: items)
                        .disabled(model.isCleaning(category))
                }
            }
        case .failed(let message):
            if result.items.isEmpty {
                FailureView(
                    message: message,
                    showsFullDiskAccessAction: showsFullDiskAccessAction(for: result)
                ) {
                    model.scan(category)
                }
            } else {
                VStack(spacing: 0) {
                    PartialScanBanner(message: message, diagnostics: result.diagnostics) {
                        model.scan(category)
                    }
                    ItemListView(category: category, items: items)
                        .disabled(model.isCleaning(category))
                }
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
            .accessibilityLabel(Text("filter.title"))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var liveCounterSize: CGFloat = 24
    @ScaledMetric(relativeTo: .largeTitle) private var totalCounterSize: CGFloat = 30

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

            Text(result.rootDescription.isEmpty ? category.subtitle : result.rootDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentSurface()
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var trailing: some View {
        if result.state == .scanning {
            VStack(alignment: .trailing, spacing: 2) {
                Text(liveBytes.formatted(.byteCount(style: .file)))
                    .font(.system(size: liveCounterSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(liveBytes)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: liveBytes)
                Text("status.scanning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !result.items.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                Text(result.totalSize.formatted(.byteCount(style: .file)))
                    .font(.system(size: totalCounterSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(result.totalSize)))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: result.totalSize)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .font(.caption)
                        .foregroundStyle(BrandPalette.Semantic.caution)
                    }
                }

                Spacer(minLength: 12)

                badge

                if let modified = item.modified {
                    Text(modified, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                RoundedRectangle(cornerRadius: BrandPalette.Radius.chip, style: .continuous)
                    .fill(backgroundFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: item.isSelected)
        .contextMenu {
            Button("action.revealInFinder") {
                revealInFinder()
            }
            Button("action.copyPath") {
                copyPath()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityHint(Text(accessibilityHintText))
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
        .accessibilityAction(named: Text("action.revealInFinder")) {
            revealInFinder()
        }
        .accessibilityAction(named: Text("action.copyPath")) {
            copyPath()
        }
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if item.safety.isProtected {
            parts.append(String(localized: "a11y.protected"))
        } else {
            parts.append(item.isSelected ? String(localized: "a11y.selected") : String(localized: "a11y.notSelected"))
            if item.safety.warning != nil {
                parts.append(String(localized: "safety.caution.label"))
            }
        }
        parts.append(item.size.formatted(.byteCount(style: .file)))
        if let modified = item.modified {
            parts.append(modified.formatted(.dateTime.day().month().year()))
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHintText: String {
        if item.safety.isProtected {
            return String(localized: "safety.protected.help")
        }
        if let warning = item.safety.warning {
            return warning
        }
        return String(localized: "a11y.toggle.hint")
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }

    private var checkbox: some View {
        Group {
            if item.safety.isSelectable {
                ZStack {
                    Circle()
                        .fill(item.isSelected ? Color.accentColor : Color.clear)
                    Circle()
                        .strokeBorder(item.isSelected ? Color.clear : Color.secondary, lineWidth: 1.5)
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
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: item.isSelected)
        .accessibilityHidden(true)
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
                .accessibilityHidden(true)
        } else if let warning = item.safety.warning {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrandPalette.Semantic.caution)
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(BrandPalette.Semantic.caution.opacity(0.16))
                }
                .help(warning)
                .accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let category: SpaceCategory
    let result: CategoryResult
    let flaggedCount: Int
    @Binding var showOnlyFlagged: Bool

    private var isCleaning: Bool {
        model.isCleaning(category)
    }

    private var allSelected: Bool {
        let selectable = result.items.filter(\.safety.isSelectable)
        return !selectable.isEmpty && selectable.allSatisfy(\.isSelected)
    }

    private var selectAllTitle: LocalizedStringKey {
        if allSelected { return "action.deselectAll" }
        return flaggedCount > 0 ? "cleanbar.selectSafe" : "action.selectAll"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            HStack(spacing: 12) {
                if !result.items.isEmpty {
                    Button(selectAllTitle) {
                        model.toggleSelectAll(in: category)
                    }
                    .controlSize(.large)
                    .disabled(isCleaning)
                    .help(flaggedCount > 0
                          ? "cleanbar.selectAll.warningHelp"
                          : "cleanbar.selectAll.help")
                }

                if flaggedCount > 0 && !allSelected {
                    Text("cleanbar.selectAll.warningNote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if flaggedCount > 0 {
                    Button {
                        showOnlyFlagged.toggle()
                    } label: {
                        Label(L10n.flaggedCount(flaggedCount), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(BrandPalette.Semantic.caution)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule().fill(BrandPalette.Semantic.caution.opacity(showOnlyFlagged ? 0.28 : 0.15))
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCleaning)
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
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: result.selectedSize)
                }

                if isCleaning {
                    cleaningStatus
                } else {
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private var cleaningStatus: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text("cleanbar.cleaning")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("action.cancel") {
                model.cancelClean(category)
            }
            .controlSize(.large)
            .help("cleanbar.cleaning.help")
        }
        .accessibilityElement(children: .contain)
    }
}
