import PostureLogic
import SwiftUI

/// Displays the current posture state on the functional monitoring screen.
struct PostureCard: View {
    let postureState: PostureState
    let trackingQuality: TrackingQuality

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(stateColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("POSTURE")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text(stateLabel)
                        .font(.headline)
                        .foregroundStyle(stateColor)

                    if trackingQuality != .good {
                        Text(qualityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            // One element for VoiceOver, "Posture, Sitting well", not "POSTURE" then the state.
            .accessibilityElement(children: .combine)
        }
    }

    private var stateLabel: String { Self.label(for: postureState) }

    /// The posture in the words used everywhere: here, on the Watch and under the timeline
    /// (2026-10-16). This card said "Good / Drifting / Poor posture / Not detected".
    static func label(for postureState: PostureState) -> String {
        switch postureState {
        case .absent:        return "Away"
        case .calibrating:   return "Calibrating…"
        case .good:          return "Sitting well"
        case .drifting:      return "Slouching"
        case .bad:           return "Still slouching"
        }
    }

    private var stateColor: Color {
        switch postureState {
        case .absent, .calibrating: return .secondary
        case .good:                 return Color(PosturePalette.good)
        case .drifting:             return Color(PosturePalette.slouching)
        case .bad:                  return Color(PosturePalette.stillSlouching)
        }
    }

    private var iconName: String {
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
        PostureCard(postureState: .good, trackingQuality: .good)
        PostureCard(postureState: .bad(since: 0), trackingQuality: .good)
        PostureCard(postureState: .drifting(since: 0), trackingQuality: .degraded)
    }
    .padding()
}
