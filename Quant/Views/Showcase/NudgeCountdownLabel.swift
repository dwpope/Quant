import SwiftUI

enum NudgeCountdownStyle {
    case compact   // "3:45"
    case verbose   // "Nudge in 3m 45s"
    case hud       // "T-3:45"
}

struct NudgeCountdownLabel: View {
    let seconds: TimeInterval?
    var style: NudgeCountdownStyle = .compact

    var body: some View {
        if let seconds, seconds >= 0 {
            Text(formatted(seconds))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Nudge in \(accessibilityFormatted(seconds))")
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds))
        let m = clamped / 60
        let s = clamped % 60
        switch style {
        case .compact:
            return "\(m):\(String(format: "%02d", s))"
        case .verbose:
            return "Nudge in \(m)m \(String(format: "%02d", s))s"
        case .hud:
            return "T-\(m):\(String(format: "%02d", s))"
        }
    }

    private func accessibilityFormatted(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds))
        let m = clamped / 60
        let s = clamped % 60
        if m > 0 {
            return "\(m) minutes \(s) seconds"
        }
        return "\(s) seconds"
    }

    private var font: Font {
        switch style {
        case .compact: return .subheadline
        case .verbose: return .callout
        case .hud:     return .system(.subheadline, design: .monospaced)
        }
    }
}
