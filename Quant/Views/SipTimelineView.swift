import PostureLogic
import SwiftUI

/// Shows today's confirmed sip events with swipe-to-delete and a manual-add button.
///
/// This is the minimal v1 scope: no batch operations, no editing — just
/// add and delete. The "Desk use only" note is shown prominently so the
/// user understands this measures desk-session frequency, not total volume.
///
/// When `appModel.isTrainingModeEnabled` is on, each row shows its label
/// pill, offers a "Label…" swipe/context action to open `SipLabelSheet`,
/// and the toolbar exposes a ShareLink that exports the labeled JSONL.
struct SipTimelineView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var sipStore: SipStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSip = false
    @State private var addSipDate = Date()
    @State private var sipBeingLabeled: SipEvent?
    @State private var exportError: String?
    @State private var showExportPicker = false
    @State private var exportedURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if sipStore.sips.isEmpty {
                    emptyState
                } else {
                    sipList
                }
            }
            .navigationTitle("Today's Sips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if appModel.isTrainingModeEnabled {
                            exportButton
                        }
                        Button {
                            addSipDate = Date()
                            showAddSip = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Export Training Data",
                isPresented: $showExportPicker,
                titleVisibility: .visible
            ) {
                Button("Export JSON") {
                    exportedURL = try? appModel.sipTrainingStore.exportJSON(for: sipStore.sips)
                }
                Button("Export JSONL") {
                    exportedURL = try? appModel.sipTrainingStore.exportJSONL(for: sipStore.sips)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("JSON keeps the full nested structure. JSONL has one event per line.")
            }
            .sheet(isPresented: Binding(
                get: { exportedURL != nil },
                set: { if !$0 { exportedURL = nil } }
            )) {
                if let url = exportedURL {
                    ShareSheet(url: url)
                }
            }
            .sheet(isPresented: $showAddSip) {
                addSipSheet
            }
            .sheet(item: $sipBeingLabeled) { sip in
                SipLabelSheet(
                    item: PendingSipLabel(event: sip, scores: scores(for: sip)),
                    onLabel: { label in
                        appModel.sipStore.setLabel(id: sip.id, label: label)
                    },
                    onSkip: {}
                )
            }
        }
    }

    private func scores(for sip: SipEvent) -> SipDetector.Scores? {
        guard let record = appModel.sipTrainingStore.record(for: sip.id) else { return nil }
        return SipDetector.Scores(
            proximity: record.proximityScore,
            velocity: record.velocityScore,
            duration: record.durationScore,
            activeWrist: record.activeWrist
        )
    }

    // MARK: - Sip List

    private var sipList: some View {
        List {
            Section {
                ForEach(sipStore.sips) { sip in
                    SipRow(sip: sip, showLabel: appModel.isTrainingModeEnabled)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                sipBeingLabeled = sip
                            } label: {
                                Label("Label\u{2026}", systemImage: "tag")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                sipBeingLabeled = sip
                            } label: {
                                Label("Label\u{2026}", systemImage: "tag")
                            }
                        }
                }
                .onDelete { offsets in
                    sipStore.remove(at: offsets)
                }
            } footer: {
                footerNote
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            showExportPicker = true
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No sips recorded yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Aware detects sips automatically while you work at your desk.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            footerNote
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Desk use only \u{2014} tracks how regularly you drink while working, not total daily intake.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Add Sip Sheet

    private var addSipSheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Time",
                    selection: $addSipDate,
                    in: Calendar.current.startOfDay(for: Date())...Date(),
                    displayedComponents: [.hourAndMinute]
                )
            }
            .navigationTitle("Add Missed Sip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSip = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let event = SipEvent(
                            timestamp: addSipDate.timeIntervalSince1970,
                            duration: 0,
                            confidence: nil,
                            label: .missed
                        )
                        sipStore.add(event)
                        showAddSip = false
                    }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

// MARK: - Row

private struct SipRow: View {
    let sip: SipEvent
    let showLabel: Bool

    var body: some View {
        HStack {
            Text(formattedTime)
                .font(.body)

            if showLabel, let label = sip.label {
                labelPill(for: label)
            }

            Spacer()

            if sip.duration > 0 {
                Text("\(Int(sip.duration))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labelPill(for label: SipEvent.Label) -> some View {
        Text(labelText(label))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(labelColor(label).opacity(0.2), in: Capsule())
            .foregroundStyle(labelColor(label))
    }

    private func labelText(_ label: SipEvent.Label) -> String {
        switch label {
        case .confirmed: return "confirmed"
        case .unconfirmed: return "unreviewed"
        case .missed: return "missed"
        case .chinRest: return "chin rest"
        case .faceTouch: return "face touch"
        case .adjustingGlasses: return "glasses"
        case .phoneToFace: return "phone"
        case .coughYawn: return "cough/yawn"
        case .other: return "other"
        }
    }

    private func labelColor(_ label: SipEvent.Label) -> Color {
        switch label {
        case .confirmed: return .green
        case .missed: return .blue
        case .unconfirmed: return .gray
        case .chinRest, .faceTouch, .adjustingGlasses,
             .phoneToFace, .coughYawn, .other:
            return .orange
        }
    }

    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: sip.timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Share Sheet

/// Thin UIActivityViewController wrapper so we can present any URL
/// (JSONL or JSON) from a SwiftUI `.sheet`.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SipTimelineView(appModel: AppModel(), sipStore: SipStore())
}
