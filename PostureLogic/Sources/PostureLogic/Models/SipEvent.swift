import Foundation

/// A confirmed sip event detected by `SipDetector`.
///
/// `confidence` is `nil` in the initial rule-based implementation and will be
/// populated later when a CreateML gesture model exists.
///
/// `label` is an optional training-mode annotation produced either by the
/// confirmation popup or by the explicit label action on an existing row. It
/// is `nil` when the detector's output has not been reviewed. Labels do not
/// affect hydration totals — they exist purely to produce training data.
public struct SipEvent: Identifiable, Codable {

    /// Training-mode annotation attached to a sip event.
    ///
    /// Added as part of the false-positive logging workflow. All categories
    /// except `confirmed` and `missed` indicate the detector was wrong.
    public enum Label: String, Codable, CaseIterable {
        /// The user explicitly confirmed this was a real sip.
        case confirmed
        /// The popup timed out or the app was backgrounded — detector's
        /// guess was kept but the event was not human-reviewed.
        case unconfirmed
        /// A manually-added sip the detector missed (false negative).
        case missed
        case chinRest
        case faceTouch
        case adjustingGlasses
        case phoneToFace
        case coughYawn
        case other

        /// True for categories that represent a detector mistake (i.e. a
        /// non-sip motion the rule-based engine mistook for a sip). Used by
        /// the training export to flag negative examples.
        public var isFalsePositive: Bool {
            switch self {
            case .chinRest, .faceTouch, .adjustingGlasses,
                 .phoneToFace, .coughYawn, .other:
                return true
            case .confirmed, .unconfirmed, .missed:
                return false
            }
        }
    }

    public let id: UUID
    /// Timestamp (seconds since reference date) when the wrist first entered
    /// the proximity zone — i.e., when the sip started.
    public let timestamp: TimeInterval
    /// How long the wrist remained near the face (seconds).
    public let duration: TimeInterval
    /// Model confidence score. `nil` until a CreateML classifier is added.
    public let confidence: Float?
    /// Training-mode label. `nil` on events the user has not reviewed.
    public var label: Label?

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        duration: TimeInterval,
        confidence: Float? = nil,
        label: Label? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.confidence = confidence
        self.label = label
    }

    /// Returns a copy with the given label applied. Used by `SipStore` when
    /// the user re-labels an existing row.
    public func withLabel(_ label: Label?) -> SipEvent {
        SipEvent(
            id: id,
            timestamp: timestamp,
            duration: duration,
            confidence: confidence,
            label: label
        )
    }

    // MARK: - Codable (migration-safe)
    //
    // `label` is decoded via `decodeIfPresent` so existing
    // `sips-YYYY-MM-DD.json` files written before the field existed decode
    // cleanly with `label = nil`. Re-persisting under the new build adds the
    // key back in.

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, duration, confidence, label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        self.duration = try container.decode(TimeInterval.self, forKey: .duration)
        self.confidence = try container.decodeIfPresent(Float.self, forKey: .confidence)
        self.label = try container.decodeIfPresent(Label.self, forKey: .label)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(duration, forKey: .duration)
        // `confidence` kept as `encode` (writes `null`) to match the existing
        // on-disk format exactly. `label` uses `encodeIfPresent` so old files
        // without the key continue to round-trip unchanged until a label is
        // actually applied.
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(label, forKey: .label)
    }
}
