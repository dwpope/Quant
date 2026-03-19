import SwiftUI

enum PostureAnimations {
    static let alertOnset: Animation = .spring(response: 0.6, dampingFraction: 0.7)
    static let metricUpdate: Animation = .interpolatingSpring(stiffness: 200, damping: 15)
    static let nudgePulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    static let modeTransition: Animation = .easeInOut(duration: 0.35)

    /// Reduced-motion alternatives — simpler easing, no repeating animations.
    struct reducedMotion {
        static let alertOnset: Animation = .easeInOut(duration: 0.3)
        static let metricUpdate: Animation = .easeInOut(duration: 0.3)
        static let nudgePulse: Animation? = nil
        static let modeTransition: Animation = .easeInOut(duration: 0.3)
    }
}
