import AppKit
import SwiftUI

enum AppInfo {
    static var icon: NSImage {
        NSApplication.shared.applicationIconImage
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage()
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var version: String {
        "\(shortVersion) (\(buildVersion))"
    }

    static let githubURL = URL(string: "https://github.com/DavidMolinari/sweep")!
}

struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menu.aboutSweep") {
            openWindow(id: AboutView.windowID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct AboutView: View {
    static let windowID = "about"

    @State private var copied = false
    @State private var showingLicense = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text(verbatim: "Sweep")
                        .font(.system(size: 23, weight: .semibold))
                    Text("about.version \(AppInfo.version)")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 38)
            .padding(.bottom, 18)

            VStack(spacing: 6) {
                Text("about.copyright")
                    .font(.callout)
                Text("about.builtWith")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            HStack(spacing: 10) {
                Button {
                    copyVersion()
                } label: {
                    Label(
                        copied ? "about.copied" : "about.copyVersion",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .accessibilityLabel(Text(copied ? LocalizedStringKey("about.copied") : LocalizedStringKey("about.copyVersion")))
                Button("about.viewLicense") {
                    showingLicense = true
                }
                .accessibilityLabel(Text("about.viewLicense"))
            }

            Link(destination: AppInfo.githubURL) {
                Label("about.github", systemImage: "arrow.up.right")
                    .font(.callout)
            }
            .accessibilityLabel(Text("about.github"))
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .frame(width: 380)
        .sheet(isPresented: $showingLicense) {
            MITLicenseSheet()
        }
    }

    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Sweep \(AppInfo.version)", forType: .string)
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.snappy) { copied = false }
        }
    }
}

struct MITLicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("about.license.title", systemImage: "doc.text")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                Text(verbatim: Self.licenseText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }

            Divider()

            HStack {
                Spacer()
                Button("action.close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 400)
    }

    private static let licenseText = """
    MIT License

    Copyright © 2026 David Molinari

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
