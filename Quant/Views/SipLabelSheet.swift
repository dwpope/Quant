import Combine
import PostureLogic
import SwiftUI

/// Training-mode confirmation popup shown for each confirmed sip.
///
/// Surfaced from `AppModel.activeSipLabelItem` as a `.medium` detent
/// sheet. The user either confirms the sip or picks a false-positive
/// category; dismissing without a choice counts as skipped (treated as
/// `.unconfirmed` by the queue).
struct SipLabelSheet: View {
    let item: PendingSipLabel
    let onLabel: (SipEvent.Label) -> Void
    let onSkip: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didLabel = false
    @State private var secondsRemaining = 15

    private static let falsePositiveCategories: [(SipEvent.Label, String, String)] = [
        (.chinRest, "Chin rest", "hand.point.up.left"),
        (.faceTouch, "Face touch", "hand.raised"),
        (.adjustingGlasses, "Glasses", "eyeglasses"),
        (.phoneToFace, "Phone", "iphone"),
        (.coughYawn, "Cough/yawn", "wind"),
        (.other, "Other", "questionmark.circle"),
    ]

    private let countdown = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    scoresRow
                    confirmButton
                    falsePositiveSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Was that a sip?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .onReceive(countdown) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
        }
        .onDisappear {
            if !didLabel { onSkip() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedTime)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var scoresRow: some View {
        HStack(spacing: 8) {
            if let s = item.scores {
                scorePill(label: "Prox", value: s.proximity)
                scorePill(label: "Vel", value: s.velocity)
                scorePill(label: "Dur", value: s.duration)
                wristChip(s.activeWrist)
            } else {
                Text("No score data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func scorePill(label: String, value: Float) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private func wristChip(_ activeWrist: String?) -> some View {
        let label: String
        switch activeWrist {
        case "leftWrist": label = "L wrist"
        case "rightWrist": label = "R wrist"
        default: label = "—"
        }
        return Text(label)
            .font(.caption.monospacedDigit())
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }

    private var confirmButton: some View {
        Button {
            apply(.confirmed)
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Confirmed sip")
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var falsePositiveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not a sip — why?")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(Self.falsePositiveCategories, id: \.0) { category, title, icon in
                    Button {
                        apply(category)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon)
                            Text(title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        Text("Auto-dismisses in \(max(secondsRemaining, 0))s")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Actions

    private func apply(_ label: SipEvent.Label) {
        didLabel = true
        onLabel(label)
        dismiss()
    }

    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: item.event.timestamp)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    SipLabelSheet(
        item: PendingSipLabel(
            event: SipEvent(
                timestamp: Date().timeIntervalSince1970,
                duration: 1.8
            ),
            scores: SipDetector.Scores(
                proximity: 0.27,
                velocity: 0.08,
                duration: 1.8,
                activeWrist: "rightWrist"
            )
        ),
        onLabel: { _ in },
        onSkip: {}
    )
}
