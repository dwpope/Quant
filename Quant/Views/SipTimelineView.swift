import PostureLogic
import SwiftUI

/// Shows today's confirmed sip events with swipe-to-delete and a manual-add button.
///
/// This is the minimal v1 scope: no batch operations, no editing — just
/// add and delete. The "Desk use only" note is shown prominently so the
/// user understands this measures desk-session frequency, not total volume.
struct SipTimelineView: View {
    @ObservedObject var sipStore: SipStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSip = false
    @State private var addSipDate = Date()

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
                    Button {
                        addSipDate = Date()
                        showAddSip = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSip) {
                addSipSheet
            }
        }
    }

    // MARK: - Sip List

    private var sipList: some View {
        List {
            Section {
                ForEach(sipStore.sips) { sip in
                    SipRow(sip: sip)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No sips recorded yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Quant detects sips automatically while you work at your desk.")
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
                            confidence: nil
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

    var body: some View {
        HStack {
            Text(formattedTime)
                .font(.body)

            Spacer()

            if sip.duration > 0 {
                Text("\(Int(sip.duration))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: sip.timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    let store = SipStore()
    return SipTimelineView(sipStore: store)
}
