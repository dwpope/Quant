import Foundation

/// What the app does when it suspects the seat has moved since calibration.
public enum SeatChangeMode: String, Codable, CaseIterable, Sendable {
    /// Don't look.
    case off
    /// Look and log each suggestion, but never ask or hold a nudge.
    case logOnly
    /// Look, log, and ask "Moved your seat?" while nudges wait.
    case ask
}

/// How an open seat-change question ended.
public enum SeatChangeOutcome: String, Sendable {
    case recalibrate, dismiss, timeout, away, modeChanged, newTimeline
}

/// The question put to the user: the suggestion that raised it.
public struct SeatChangeQuestion: Equatable, Sendable {
    public let suggestion: SeatChangeSuggestion
}
