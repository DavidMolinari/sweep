import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 264, max: 320)
        } detail: {
            if let category = model.selection {
                CategoryDetailView(category: category)
            } else {
                VStack(spacing: 14) {
                    IconMedallion(symbol: "sparkles", style: .neutral, size: 60)
                    Text("detail.emptySelection")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $model.confirmation) { pending in
            ConfirmCleanView(pending: pending)
                .environmentObject(model)
        }
        .sheet(item: $model.report) { report in
            CleanReportView(report: report)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.scanAll()
                } label: {
                    Label("toolbar.scanAll", systemImage: "sparkles")
                }
                .disabled(model.isAnyScanning || model.isAnyCleaning)
                .help("toolbar.scanAll.help")
            }
            ToolbarItem {
                Button {
                    model.scanSelected()
                } label: {
                    Label("action.scan", systemImage: "arrow.clockwise")
                }
                .disabled(model.selection == nil || model.isAnyScanning || model.isAnyCleaning)
                .help("toolbar.scan.help")
            }
        }
    }
}
