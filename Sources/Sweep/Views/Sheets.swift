import SwiftUI

struct ConfirmCleanView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let pending: PendingClean

    var body: some View {
        let permanent = pending.category.isPermanentDeletion

        VStack(spacing: 18) {
            IconMedallion(
                symbol: permanent ? "trash.slash" : "sparkles",
                style: permanent ? .warning : CategoryStyle.of(pending.category),
                size: 58
            )

            VStack(spacing: 6) {
                Text(permanent ? "confirm.title.emptyTrash" : "confirm.title.clean")
                    .font(.title3.weight(.semibold))
                Text(verbatim: L10n.pair(L10n.itemCount(pending.items.count), pending.size.formatted(.byteCount(style: .file))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: permanent ? "exclamationmark.shield.fill" : "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(permanent ? Color.red : Color.secondary)
                Text(permanent
                     ? "confirm.body.emptyTrash"
                     : "confirm.body.clean")
                    .font(.callout)
                    .foregroundStyle(permanent ? Color.red : Color.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(permanent ? Color.red.opacity(0.10) : Color.primary.opacity(0.05))
            }

            HStack {
                Button("action.cancel") { dismiss() }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(permanent ? "cleanbar.emptyTrash" : "confirm.moveToTrash") {
                    model.performClean(pending)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(permanent ? .red : .accentColor)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(26)
        .frame(width: 450)
    }
}

struct CleanReportView: View {
    @Environment(\.dismiss) private var dismiss
    let report: CleanReport

    var body: some View {
        VStack(spacing: 18) {
            IconMedallion(
                symbol: report.failures.isEmpty ? "checkmark" : "exclamationmark.triangle.fill",
                style: report.failures.isEmpty ? .success : .warning,
                size: 58
            )

            VStack(spacing: 6) {
                Text(report.failures.isEmpty ? "report.title.success" : "report.title.partial")
                    .font(.title3.weight(.semibold))
                Text(verbatim: L10n.pair(report.freed.formatted(.byteCount(style: .file)), L10n.removedCount(report.removed)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if !report.failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: L10n.failureCount(report.failures.count))
                        .font(.caption.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.failures, id: \.self) { line in
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 110)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            } else {
                Text(report.permanent ? "report.done.permanent" : "report.done.trashed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("action.close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 2)
        }
        .padding(26)
        .frame(width: 450)
    }
}
