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
        }
    }

    private var stateLabel: String {
        switch postureState {
        case .absent:        return "Not detected"
        case .calibrating:   return "Calibrating…"
        case .good:          return "Good"
        case .drifting:      return "Drifting"
        case .bad:           return "Poor posture"
        }
    }

    private var stateColor: Color {
        switch postureState {
        case .absent, .calibrating: return .secondary
        case .good:                 return .green
        case .drifting:             return .yellow
        case .bad:                  return .red
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
