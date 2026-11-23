import Foundation

public enum NudgeDecision: Codable {
    case none
    case pending(reason: NudgeReason, timeRemaining: TimeInterval)
    case fire(reason: NudgeReason)
    case suppressed(reason: SuppressionReason)
}

public enum NudgeReason: String, Codable, Sendable {
    case sustainedSlouch
    case forwardCreep
    case headDrop
    /// The head held turned to one side with the shoulders still facing the phone, as when
    /// working on a second screen. Not a slouch; timed by `HeadTurnTracker`.
    case headTurned
    /// Sinking down in the chair: the shoulders lower in the frame than at calibration
    /// (`RawMetrics.shoulderSink`), 2026-10-05.
    case sink
    /// Leaning to one side: the shoulders' midpoint off to one side of where it was at
    /// calibration (`RawMetrics.lateralLean`), 2026-11-19. It was a slouch with no reason of its
    /// own, so its nudge said the general "Sit up".
    case sideLean
}

public enum SuppressionReason: String, Codable {
    case cooldownActive
    case maxNudgesReached
    case userStretching
    case lowTrackingQuality
    /// No longer produced: sitting up after a nudge stopped suppressing the next one on
    /// 2026-10-05. Kept so a stored decision still decodes.
    case recentAcknowledgement
    /// Silenced for a while from the phone or the Watch (2026-10-05). Every nudge waits.
    case silenced
}
