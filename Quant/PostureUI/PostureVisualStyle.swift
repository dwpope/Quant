import SwiftUI
import PostureLogic

enum PostureVisualStyle {
    static func stateColor(for state: PostureState) -> Color {
        switch state {
        case .absent, .calibrating:
            return .secondary
        case .good:
            return Color(hue: 0.38, saturation: 0.6, brightness: 0.7)
        case .drifting:
            return Color(hue: 0.08, saturation: 0.8, brightness: 0.85)
        case .bad:
            return Color(hue: 0.02, saturation: 0.9, brightness: 0.8)
        }
    }

    static func metricColor(ratio: Float) -> Color {
        let t = Double(min(max(ratio, 0), 1.0))
        return Color(hue: (1.0 - t) * 0.35, saturation: 0.7, brightness: 0.75)
    }

    static func stateLabel(for state: PostureState) -> String {
        switch state {
        case .absent:      return "Waiting"
        case .calibrating: return "Calibrating"
        case .good:        return "Good"
        case .drifting:    return "Drifting"
        case .bad:         return "Bad"
        }
    }

    static func nudgeCountdownLabel(seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds))
        let minutes = clamped / 60
        let secs = clamped % 60
        return "\(minutes):\(String(format: "%02d", secs))"
    }

    static func stateAccessibilityLabel(for state: PostureState, worstOffender: MetricInfo?) -> String {
        let base = stateLabel(for: state)
        if let offender = worstOffender {
            return "\(base). Worst metric: \(offender.key.displayName)"
        }
        return base
    }
}
