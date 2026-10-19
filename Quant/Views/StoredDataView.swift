import SwiftUI

/// What the app keeps on the phone, and deleting the older part of it (2026-10-11).
struct StoredDataView: View {
    @EnvironmentObject var appModel: AppModel

    @State private var pendingDays: Int?
    @State private var lastFreed: Int64?

    private static let choices = [7, 30, 90]

    var body: some View {
        List {
            Section {
                if summary.byKind.isEmpty {
                    Text("Nothing stored yet")
                        .readableSecondary()
                }
                ForEach(summary.byKind, id: \.kind) { line in
                    LabeledContent(line.kind.label) {
                        Text("\(line.count) \(line.count == 1 ? "file" : "files") · \(Self.size(line.bytes))")
                            .readableSecondary()
                    }
                }
            } header: {
                Text("On this iPhone")
                    .readableSecondary()
            } footer: {
                Text("Total \(Self.size(summary.totalBytes)).")
                    .readableSecondary()
            }

            Section {
                ForEach(Self.choices, id: \.self) { days in
                    let old = StoredData.olderThan(days: days, in: appModel.storedData)
                    Button(role: .destructive) {
                        pendingDays = days
                    } label: {
                        LabeledContent("Older than \(days) days") {
                            Text(old.isEmpty ? "None" : Self.size(old.reduce(0) { $0 + $1.bytes }))
                        }
                    }
                    .disabled(old.isEmpty)
                }
                if let lastFreed {
                    Text("Deleted \(Self.size(lastFreed)).")
                        .readableSecondary()
                }
            } header: {
                Text("Delete older data")
                    .readableSecondary()
            } footer: {
                Text("Today's data is never deleted. To keep a copy, export the posture log or the Jev data first.")
                    .readableSecondary()
            }
        }
        .navigationTitle("Stored Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appModel.scanStoredData() }
        .confirmationDialog(confirmTitle, isPresented: confirmShown, titleVisibility: .visible) {
            if let days = pendingDays {
                Button("Delete", role: .destructive) {
                    Task { lastFreed = await appModel.deleteStoredData(olderThan: days) }
                }
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var summary: StoredData.Summary { StoredData.Summary(items: appModel.storedData) }

    private var confirmShown: Binding<Bool> {
        Binding(get: { pendingDays != nil }, set: { if !$0 { pendingDays = nil } })
    }

    private var confirmTitle: String {
        guard let days = pendingDays else { return "" }
        let old = StoredData.olderThan(days: days, in: appModel.storedData)
        return "Delete \(old.count) \(old.count == 1 ? "file" : "files") (\(Self.size(old.reduce(0) { $0 + $1.bytes }))) older than \(days) days?"
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// On the main screen when there's data older than a month, from the scan at launch.
struct StoredDataCard: View {
    let olderBytes: Int64
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("STORED DATA")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    Text("\(StoredDataView.size(olderBytes)) older than \(AppModel.storedDataNoticeDays) days")
                        .font(.subheadline)
                    Text("Review or delete it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
