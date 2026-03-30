import SwiftUI

/// Displays today's hydration summary on the functional monitoring screen.
/// Tap to open the full sip timeline.
struct HydrationCard: View {
    let sipCount: Int
    let lastSipTimestamp: TimeInterval?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CardContainer {
                HStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HYDRATION")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .tracking(1.2)

                        Text(sipCountLabel)
                            .font(.headline)

                        HStack(spacing: 4) {
                            Text(lastSipLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Text("Desk use only")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var sipCountLabel: String {
        switch sipCount {
        case 0:  return "No sips yet"
        case 1:  return "1 sip today"
        default: return "\(sipCount) sips today"
        }
    }

    private var lastSipLabel: String {
        guard let ts = lastSipTimestamp else {
            return "No recent sip"
        }
        let elapsed = Date().timeIntervalSince1970 - ts
        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "Last sip \(minutes) min ago"
        } else {
            let hours = Int(elapsed / 3600)
            return "Last sip \(hours)h ago"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        HydrationCard(sipCount: 0, lastSipTimestamp: nil, onTap: {})
        HydrationCard(sipCount: 7, lastSipTimestamp: Date().timeIntervalSince1970 - 240, onTap: {})
    }
    .padding()
}
