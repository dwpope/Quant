import Foundation

public enum NudgeDecision: Codable {
    case none
    case pending(reason: NudgeReason, timeRemaining: TimeInterval)
    case fire(reason: NudgeReason)
    case suppressed(reason: SuppressionReason)
}

public enum NudgeReason: String, Codable {
    case sustainedSlouch
    case forwardCreep
    case headDrop
    /// The head held turned to one side with the shoulders still facing the phone, as when
    /// working on a second screen. Not a slouch; timed by `HeadTurnTracker`.
    case headTurned
}

public enum SuppressionReason: String, Codable {
    case cooldownActive
    case maxNudgesReached
    case userStretching
    case lowTrackingQuality
    case recentAcknowledgement
}
