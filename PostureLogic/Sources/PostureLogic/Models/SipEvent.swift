import Foundation

/// A confirmed sip event detected by `SipDetector`.
///
/// `confidence` is `nil` in the initial rule-based implementation and will be
/// populated later when a CreateML gesture model exists.
public struct SipEvent: Identifiable, Codable {
    public let id: UUID
    /// Timestamp (seconds since reference date) when the wrist first entered
    /// the proximity zone — i.e., when the sip started.
    public let timestamp: TimeInterval
    /// How long the wrist remained near the face (seconds).
    public let duration: TimeInterval
    /// Model confidence score. `nil` until a CreateML classifier is added.
    public let confidence: Float?

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        duration: TimeInterval,
        confidence: Float? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
    }
}
