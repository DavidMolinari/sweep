import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Tab: String {
        case general
        case largeFiles
        case storage
    }

    @AppStorage("settings.selectedTab") private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPane()
                .tabItem { Label("settings.tab.general", systemImage: "gearshape") }
                .tag(Tab.general)
            LargeFilesSettingsPane()
                .tabItem { Label("settings.tab.largeFiles", systemImage: "scalemass") }
                .tag(Tab.largeFiles)
            StorageSettingsPane()
                .tabItem { Label("settings.tab.storage", systemImage: "internaldrive") }
                .tag(Tab.storage)
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 420, idealHeight: 430)
    }
}

private struct LeadingText: View {
    let key: LocalizedStringKey

    var body: some View {
        Text(key)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppModel.defaultCategoryKey) private var defaultCategory = SpaceCategory.caches.rawValue
    @State private var showingResetAlert = false

    var body: some View {
        Form {
            Section {
                Picker("settings.general.launchCategory", selection: $defaultCategory) {
                    ForEach(SpaceCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol)
                            .tag(category.rawValue)
                    }
                }
            } header: {
                Text("settings.general.behavior")
            } footer: {
                LeadingText(key: "settings.general.launchCategory.footer")
            }

            Section {
                LabeledContent("settings.general.language.current") {
                    Text(verbatim: currentLanguageName)
                }
                Button("settings.general.openLanguageSettings") {
                    openLanguageSettings()
                }
            } header: {
                Text("settings.general.language")
            } footer: {
                LeadingText(key: "settings.general.language.footer")
            }

            Section {
                Button("settings.general.reset") {
                    showingResetAlert = true
                }
            } footer: {
                LeadingText(key: "settings.general.reset.footer")
            }
        }
        .formStyle(.grouped)
        .alert("settings.reset.title", isPresented: $showingResetAlert) {
            Button("action.cancel", role: .cancel) {}
            Button("settings.reset.confirm", role: .destructive) {
                defaultCategory = SpaceCategory.caches.rawValue
                model.resetPreferences()
            }
        } message: {
            Text("settings.reset.message")
        }
    }

    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        return Locale.current.localizedString(forLanguageCode: code)?
            .capitalized(with: Locale.current) ?? code.uppercased()
    }

    private func openLanguageSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct LargeFilesSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("settings.largeFiles.threshold", selection: $model.largeThreshold) {
                    Text("size.10mb").tag(Int64(10 * 1024 * 1024))
                    Text("size.50mb").tag(Int64(50 * 1024 * 1024))
                    Text("size.100mb").tag(Int64(100 * 1024 * 1024))
                    Text("size.250mb").tag(Int64(250 * 1024 * 1024))
                    Text("size.500mb").tag(Int64(500 * 1024 * 1024))
                }
                Toggle("settings.largeFiles.oldOnly", isOn: $model.largeOldOnly)
                    .toggleStyle(.checkbox)
            } header: {
                Text("settings.largeFiles.defaults")
            } footer: {
                LeadingText(key: "settings.largeFiles.footer")
            }

            Section {
                LabeledContent("settings.largeFiles.folder") {
                    Text(verbatim: model.largeCustomRoot?.path(percentEncoded: false)
                         ?? String(localized: "largeFiles.userFolders"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 10) {
                    Button("settings.largeFiles.choose") {
                        model.chooseLargeFilesFolder()
                    }
                    if model.largeCustomRoot != nil {
                        Button("settings.largeFiles.useDefaultFolder") {
                            model.largeCustomRoot = nil
                            model.rescanIfDone(.largeFiles)
                        }
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.largeThreshold) { _, _ in
            model.rescanIfDone(.largeFiles)
        }
        .onChange(of: model.largeOldOnly) { _, _ in
            model.rescanIfDone(.largeFiles)
        }
    }
}

private struct StorageSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("settings.storage.freeSpace") {
                    Text(verbatim: freeSpaceDescription)
                        .monospacedDigit()
                }
                Button {
                    model.refreshFreeSpace()
                } label: {
                    Label("settings.storage.refresh", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("settings.storage.volume")
            }

            Section {
                LeadingText(key: "settings.storage.fullDiskAccess.description")
                    .foregroundStyle(.secondary)
                Button("settings.storage.fullDiskAccess.open") {
                    model.openFullDiskAccessSettings()
                }
            } header: {
                Text("settings.storage.fullDiskAccess")
            } footer: {
                LeadingText(key: "settings.storage.footer")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFreeSpace()
        }
    }

    private var freeSpaceDescription: String {
        model.freeSpace.map { $0.formatted(.byteCount(style: .file)) }
            ?? String(localized: "settings.storage.freeSpace.unavailable")
    }
}
