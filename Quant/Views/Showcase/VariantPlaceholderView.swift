import SwiftUI
import PostureLogic

struct VariantPlaceholderView: View {
    let descriptor: VariantDescriptor
    @EnvironmentObject var observer: PostureDisplayObserver

    var body: some View {
        VStack(spacing: 16) {
            Text("Variant \(descriptor.id)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(descriptor.name)
                .font(.title2.weight(.semibold))

            Text(descriptor.category.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            Label(stateLabel, systemImage: stateIcon)
                .font(.headline)
                .foregroundStyle(stateColor)
                .padding(.top, 8)

            Text(String(format: "Score: %.0f%%", observer.data.aggregateScore * 100))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stateLabel: String {
        switch observer.data.postureState {
        case .absent:      return "Absent"
        case .calibrating: return "Calibrating"
        case .good:        return "Good"
        case .drifting:    return "Drifting"
        case .bad:         return "Bad"
        }
    }

    private var stateIcon: String {
        switch observer.data.postureState {
        case .absent:      return "person.slash"
        case .calibrating: return "arrow.triangle.2.circlepath"
        case .good:        return "checkmark.circle.fill"
        case .drifting:    return "exclamationmark.triangle"
        case .bad:         return "xmark.circle.fill"
        }
    }

    private var stateColor: Color {
        switch observer.data.postureState {
        case .absent, .calibrating: return .secondary
        case .good:                 return .green
        case .drifting:             return .orange
        case .bad:                  return .red
        }
    }
}
