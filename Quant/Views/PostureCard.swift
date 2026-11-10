import PostureLogic
import SwiftUI

/// Displays the current posture state on the functional monitoring screen.
struct PostureCard: View {
    let postureState: PostureState
    let trackingQuality: TrackingQuality
    let coaching: NudgeReason?
    /// The head held turned to one side (`Pipeline.headTurnedSince`), from the moment it turns.
    var headTurned = false

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(stateColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("POSTURE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(1.2)
                        Spacer(minLength: 0)
                        signalBadge
                    }
                    .lineLimit(1)

                    Text(stateLabel)
                        .font(.headline)
                        .foregroundStyle(stateColor)
                        .lineLimit(1)

                    // As tall as the longest it can say, so the card keeps its height whatever it
                    // says: each line, hidden, takes its room.
                    ZStack(alignment: .topLeading) {
                        ForEach(Self.allDetails, id: \.self) { Text($0).hidden() }
                        Text(Self.detail(for: postureState, coaching: coaching, headTurned: headTurned))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            // One element for VoiceOver, "Posture, Sitting well", not "POSTURE" then the state.
            .accessibilityElement(children: .combine)
        }
    }

    private var stateLabel: String { Self.label(for: postureState, headTurned: headTurned) }

    /// A head turned is shown while sitting well (2026-11-10), as on the Watch and the calm view.
    /// Slouching as well, the slouch is the posture to fix, and is what's shown.
    private static func showsHeadTurn(_ postureState: PostureState, headTurned: Bool) -> Bool {
        if case .good = postureState { return headTurned }
        return false
    }

    private var showsHeadTurn: Bool { Self.showsHeadTurn(postureState, headTurned: headTurned) }

    /// The posture in the words used everywhere: here, on the Watch and under the timeline
    /// (2026-10-16). This card said "Good / Drifting / Poor posture / Not detected". A head held
    /// turned, where the posture is (2026-11-10): Dave, "When i turn my head i would like to see
    /// that registered on the device as a status in the same location it usually shows slouching".
    static func label(for postureState: PostureState, headTurned: Bool = false) -> String {
        if showsHeadTurn(postureState, headTurned: headTurned) { return "Head turned" }
        switch postureState {
        case .absent:        return "Away"
        case .calibrating:   return "Calibrating…"
        case .good:          return "Sitting well"
        case .drifting:      return "Slouching"
        case .bad:           return "Still slouching"
        }
    }

    /// What to do (2026-11-09): slouching, how to sit up again, in the words the Watch's nudge
    /// uses (`SlouchCoaching` picks which); the head turned, its nudge's line; otherwise what to
    /// keep, or why there's nothing to judge.
    static func detail(for postureState: PostureState, coaching: NudgeReason?, headTurned: Bool = false) -> String {
        if showsHeadTurn(postureState, headTurned: headTurned) { return NudgeReason.headTurned.coachingMessage }
        switch postureState {
        case .drifting, .bad: return (coaching ?? .sustainedSlouch).coachingMessage
        case .good:           return "Head up, sitting back"
        case .absent:         return "Out of the camera's view"
        case .calibrating:    return "Sit as you usually do, and hold still"
        }
    }

    /// Every line `detail` can give.
    static let allDetails: [String] = {
        let states: [PostureState] = [.good, .absent, .calibrating, .drifting(since: 0)]
        let reasons: [NudgeReason?] = [nil, .sustainedSlouch, .forwardCreep, .headDrop, .sink]
        var lines = [detail(for: .good, coaching: nil, headTurned: true)]
        for state in states {
            for reason in reasons where !lines.contains(detail(for: state, coaching: reason)) {
                lines.append(detail(for: state, coaching: reason))
            }
        }
        return lines
    }()

    /// The camera's signal, beside the heading on the same line (2026-11-09). It was a line of its
    /// own under the posture, and as tracking came and went the card grew and shrank, and every
    /// card under it jumped. Just the symbol when the words don't fit.
    @ViewBuilder private var signalBadge: some View {
        if trackingQuality != .good {
            let symbol = trackingQuality == .lost ? "video.slash" : "exclamationmark.triangle"
            ViewThatFits(in: .horizontal) {
                Label(qualityLabel, systemImage: symbol)
                Image(systemName: symbol)
                    .accessibilityLabel(qualityLabel)
            }
            .font(.caption2)
            .imageScale(.small)
            .foregroundStyle(.secondary)
        }
    }

    /// A head turned in the slouch's yellow, with the Watch's symbol: something coming, not yet
    /// bad.
    private var stateColor: Color {
        if showsHeadTurn { return Color(PosturePalette.slouching) }
        switch postureState {
        case .absent, .calibrating: return .secondary
        case .good:                 return Color(PosturePalette.good)
        case .drifting:             return Color(PosturePalette.slouching)
        case .bad:                  return Color(PosturePalette.stillSlouching)
        }
    }

    private var iconName: String {
        if showsHeadTurn { return "arrow.left.arrow.right.circle.fill" }
        switch postureState {
        case .absent, .calibrating: return "person.slash"
        case .good:                 return "checkmark.circle.fill"
        case .drifting:             return "exclamationmark.circle"
        case .bad:                  return "xmark.circle.fill"
        }
    }

    private var qualityLabel: String {
        switch trackingQuality {
        case .degraded: return "Camera signal degraded"
        case .lost:     return "Camera signal lost"
        case .good:     return ""
        }
    }
}

// MARK: - Shared card container

struct CardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    VStack(spacing: 12) {
        PostureCard(postureState: .good, trackingQuality: .good, coaching: nil)
        PostureCard(postureState: .good, trackingQuality: .good, coaching: nil, headTurned: true)
        PostureCard(postureState: .bad(since: 0), trackingQuality: .good, coaching: .headDrop)
        PostureCard(postureState: .drifting(since: 0), trackingQuality: .degraded, coaching: .forwardCreep)
    }
    .padding()
}
