import Foundation

/// Configurable thresholds for `SipDetector`.
///
/// Default values work for most desk setups. After running
/// `SipCalibrationCapture` with 5 recorded sips, replace these with the
/// personalised values derived from `SipCalibrationCapture.derivedThresholds`.
public struct SipThresholds: Codable {
    // MARK: - Proximity (Signal 1)

    /// Wrist-to-nose distance normalised by shoulder width.
    /// A value below this means the wrist is close to the face.
    /// Default: 0.35 (wrist within ~35% of shoulder-width distance from nose).
    public var proximityThreshold: Float = 0.35

    // MARK: - Velocity (Signal 2)

    /// Minimum normalised upward wrist speed (units/frame) required to
    /// credit the velocity signal. Chin-resting produces near-zero velocity
    /// and therefore never credits this signal.
    public var velocityThreshold: Float = 0.008

    // MARK: - Duration Band (Signal 3)

    /// Minimum time (seconds) the wrist must stay near the face.
    /// Sips shorter than this are ignored (e.g., a stray hand movement).
    public var minDuration: TimeInterval = 1.0

    /// Maximum time (seconds) the wrist can stay near the face.
    /// Exceeding this abandons the candidate (e.g., resting hand on chin).
    public var maxDuration: TimeInterval = 8.0

    // MARK: - Scoring

    /// Minimum number of signals (out of 3) required to confirm a sip.
    /// Default: 2.0 — proximity + at least one of velocity or duration.
    public var candidateScoreRequired: Float = 2.0

    // MARK: - Cooldown

    /// Seconds to suppress detection after a confirmed sip.
    public var cooldownDuration: TimeInterval = 30.0

    public init() {}
}
