import SwiftUI

enum PostureAnimations {
    // MARK: - Standard Animations

    static let alertOnset: Animation = .spring(response: 0.6, dampingFraction: 0.7)
    static let metricUpdate: Animation = .interpolatingSpring(stiffness: 200, damping: 15)
    static let nudgePulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    static let modeTransition: Animation = .easeInOut(duration: 0.35)

    // MARK: - Reduced-Motion Alternatives

    static let alertOnsetReduced: Animation = .easeInOut(duration: 0.3)
    static let metricUpdateReduced: Animation = .easeInOut(duration: 0.3)
    static let nudgePulseReduced: Animation = .easeInOut(duration: 0.3)
    static let modeTransitionReduced: Animation = .easeInOut(duration: 0.25)

    // MARK: - Adaptive Factory Methods

    static func alertOnset(reduceMotion: Bool) -> Animation {
        reduceMotion ? alertOnsetReduced : alertOnset
    }

    static func metricUpdate(reduceMotion: Bool) -> Animation {
        reduceMotion ? metricUpdateReduced : metricUpdate
    }

    static func nudgePulse(reduceMotion: Bool) -> Animation {
        reduceMotion ? nudgePulseReduced : nudgePulse
    }

    static func modeTransition(reduceMotion: Bool) -> Animation {
        reduceMotion ? modeTransitionReduced : modeTransition
    }
}
