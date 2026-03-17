import SwiftUI

enum PostureAnimations {
    static let alertOnset: Animation = .spring(response: 0.6, dampingFraction: 0.7)
    static let metricUpdate: Animation = .interpolatingSpring(stiffness: 200, damping: 15)
    static let nudgePulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    static let modeTransition: Animation = .easeInOut(duration: 0.35)
}
