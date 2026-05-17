import Foundation

/// A recorded nudge event — persisted each time the NudgeEngine fires.
///
/// While `NudgeDecision` is transient (evaluated every frame), `NudgeEvent`
/// is the durable record written when a nudge actually delivered. Collecting
/// these over time powers `NudgeInsights` analytics.
///
/// Usage:
/// ```swift
/// let event = NudgeEvent(
///     timestamp: currentTime,
///     reason: .sustainedSlouch,
///     acknowledged: true,
///     responseTime: 12.5
/// )
/// ```
public struct NudgeEvent: Identifiable, Codable, Equatable {

    public let id: UUID

    /// When the nudge was delivered (seconds since reference date).
    public let timestamp: TimeInterval

    /// Why the nudge fired — the dominant posture violation.
    public let reason: NudgeReason

    /// Whether the user corrected their posture after the nudge.
    public var acknowledged: Bool

    /// How many seconds it took the user to correct after the nudge.
    /// `nil` if the nudge was not acknowledged.
    public var responseTime: TimeInterval?

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        reason: NudgeReason,
        acknowledged: Bool = false,
        responseTime: TimeInterval? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.reason = reason
        self.acknowledged = acknowledged
        self.responseTime = responseTime
    }

    /// Returns a copy marked as acknowledged with the given response time.
    public func withAcknowledgement(responseTime: TimeInterval) -> NudgeEvent {
        NudgeEvent(
            id: id,
            timestamp: timestamp,
            reason: reason,
            acknowledged: true,
            responseTime: responseTime
        )
    }
}
