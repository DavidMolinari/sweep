import SwiftUI

struct LargeFilesControls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Picker("largeFiles.minSize", selection: $model.largeThreshold) {
                Text("size.10mb").tag(Int64(10 * 1024 * 1024))
                Text("size.50mb").tag(Int64(50 * 1024 * 1024))
                Text("size.100mb").tag(Int64(100 * 1024 * 1024))
                Text("size.250mb").tag(Int64(250 * 1024 * 1024))
                Text("size.500mb").tag(Int64(500 * 1024 * 1024))
            }
            .frame(width: 190)

            Toggle("largeFiles.olderThan6Months", isOn: $model.largeOldOnly)
                .toggleStyle(.checkbox)

            Spacer()

            Button {
                model.chooseLargeFilesFolder()
            } label: {
                Label(model.largeCustomRoot?.lastPathComponent ?? String(localized: "largeFiles.userFolders"), systemImage: "folder")
            }
            .help(model.largeCustomRoot?.path(percentEncoded: false)
                  ?? String(localized: "largeFiles.userFolders.help"))

            if model.largeCustomRoot != nil {
                Button {
                    model.largeCustomRoot = nil
                    model.rescanIfDone(.largeFiles)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("largeFiles.resetRoot.help")
            }

            Button("action.scan") {
                model.scan(.largeFiles)
            }
            .buttonStyle(.bordered)
            .disabled(model.isAnyScanning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .onChange(of: model.largeThreshold) { _, _ in
            model.rescanIfDone(.largeFiles)
        }
        .onChange(of: model.largeOldOnly) { _, _ in
            model.rescanIfDone(.largeFiles)
        }
    }
}
