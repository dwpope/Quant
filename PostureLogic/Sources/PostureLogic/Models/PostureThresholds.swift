import Foundation

public struct PostureThresholds: Codable {
    // MARK: - Detection Timing
    public var slouchDurationBeforeNudge: TimeInterval = 300
    public var recoveryGracePeriod: TimeInterval = 5
    public var driftingToBadThreshold: TimeInterval = 60
    
    // MARK: - Posture Metrics
    public var forwardCreepThreshold: Float = 0.03
    public var twistThreshold: Float = 15.0
    public var sideLeanThreshold: Float = 0.08
    /// Head-drop trip point, in shoulder widths: posture is off when `headDrop` is at or below
    /// MINUS this, the head that much closer to the shoulders than at calibration.
    ///
    /// **On the device a dropping head reads NEGATIVE**, the opposite of what the name says.
    /// `headDrop` is `baseline.neckHeight − sample.neckHeight`, and neck height is measured in
    /// image coordinates whose y runs DOWN (PoseService flips Vision's): ears above the shoulders
    /// give a negative neck height, which grows towards zero as the head drops, so the drop
    /// comes out negative. All 15 of Dave's slouches across five sessions read -0.013 to -0.186;
    /// every upright -0.007 or above. The old trip point, +0.15, assumed y runs up; on the device
    /// it fired once in 64 captures, on a chair swivel. Flipped 2026-10-05 to -0.015, the Jev
    /// wording's point. (A note here first put the sign down to the phone sitting below eye
    /// level. That was wrong: it's the coordinate direction.)
    public var headDropThreshold: Float = 0.015
    public var shoulderRoundingThreshold: Float = 10.0
    /// Shoulder sink at or above this, in calibrated shoulder widths, is a slouch: sinking down
    /// in the chair (2026-10-05). Session 8: sinks +0.086 to +0.103, uprights +0.005 to +0.020,
    /// swivels and head turns +0.018 or below.
    public var shoulderSinkThreshold: Float = 0.05

    // MARK: - Confidence Gates
    public var minTrackingQuality: Float = 0.7
    public var minKeypointVisibility: Float = 0.7
    public var depthConfidenceThreshold: Float = 0.6
    
    // MARK: - Nudge Behavior
    public var nudgeCooldown: TimeInterval = 600
    /// The most nudges in any hour, or 0 for no cap: the gap between nudges is then the only
    /// limit. No cap by default since 2026-10-05 (Dave: "don't worry about limiting the number of
    /// nudges in an hour yet"); silencing for a while replaces it.
    public var maxNudgesPerHour: Int = 0
    public var acknowledgementWindow: TimeInterval = 30
    
    // MARK: - Mode Switching
    public var depthRecoveryDelay: TimeInterval = 2.0
    public var absentThreshold: TimeInterval = 1.0
    public var absentResumeThreshold: TimeInterval = 30.0
    public var returnValidationWindow: TimeInterval = 2.0
    
    public init() {}

    // MARK: - Codable (tolerant)
    //
    // The limits are saved with every Jev record. A synthesized decoder throws on any missing
    // key, so a record saved before a limit existed would lose all of them. Each field decodes
    // if present and falls back to its default; encoding stays complete.

    private enum CodingKeys: String, CodingKey {
        case slouchDurationBeforeNudge, recoveryGracePeriod, driftingToBadThreshold, forwardCreepThreshold, twistThreshold, sideLeanThreshold, headDropThreshold, shoulderRoundingThreshold, shoulderSinkThreshold, minTrackingQuality, minKeypointVisibility, depthConfidenceThreshold, nudgeCooldown, maxNudgesPerHour, acknowledgementWindow, depthRecoveryDelay, absentThreshold, absentResumeThreshold, returnValidationWindow
    }

    public init(from decoder: Decoder) throws {
        let defaults = PostureThresholds()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slouchDurationBeforeNudge = try c.decodeIfPresent(TimeInterval.self, forKey: .slouchDurationBeforeNudge) ?? defaults.slouchDurationBeforeNudge
        recoveryGracePeriod = try c.decodeIfPresent(TimeInterval.self, forKey: .recoveryGracePeriod) ?? defaults.recoveryGracePeriod
        driftingToBadThreshold = try c.decodeIfPresent(TimeInterval.self, forKey: .driftingToBadThreshold) ?? defaults.driftingToBadThreshold
        forwardCreepThreshold = try c.decodeIfPresent(Float.self, forKey: .forwardCreepThreshold) ?? defaults.forwardCreepThreshold
        twistThreshold = try c.decodeIfPresent(Float.self, forKey: .twistThreshold) ?? defaults.twistThreshold
        sideLeanThreshold = try c.decodeIfPresent(Float.self, forKey: .sideLeanThreshold) ?? defaults.sideLeanThreshold
        headDropThreshold = try c.decodeIfPresent(Float.self, forKey: .headDropThreshold) ?? defaults.headDropThreshold
        shoulderRoundingThreshold = try c.decodeIfPresent(Float.self, forKey: .shoulderRoundingThreshold) ?? defaults.shoulderRoundingThreshold
        shoulderSinkThreshold = try c.decodeIfPresent(Float.self, forKey: .shoulderSinkThreshold) ?? defaults.shoulderSinkThreshold
        minTrackingQuality = try c.decodeIfPresent(Float.self, forKey: .minTrackingQuality) ?? defaults.minTrackingQuality
        minKeypointVisibility = try c.decodeIfPresent(Float.self, forKey: .minKeypointVisibility) ?? defaults.minKeypointVisibility
        depthConfidenceThreshold = try c.decodeIfPresent(Float.self, forKey: .depthConfidenceThreshold) ?? defaults.depthConfidenceThreshold
        nudgeCooldown = try c.decodeIfPresent(TimeInterval.self, forKey: .nudgeCooldown) ?? defaults.nudgeCooldown
        maxNudgesPerHour = try c.decodeIfPresent(Int.self, forKey: .maxNudgesPerHour) ?? defaults.maxNudgesPerHour
        acknowledgementWindow = try c.decodeIfPresent(TimeInterval.self, forKey: .acknowledgementWindow) ?? defaults.acknowledgementWindow
        depthRecoveryDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .depthRecoveryDelay) ?? defaults.depthRecoveryDelay
        absentThreshold = try c.decodeIfPresent(TimeInterval.self, forKey: .absentThreshold) ?? defaults.absentThreshold
        absentResumeThreshold = try c.decodeIfPresent(TimeInterval.self, forKey: .absentResumeThreshold) ?? defaults.absentResumeThreshold
        returnValidationWindow = try c.decodeIfPresent(TimeInterval.self, forKey: .returnValidationWindow) ?? defaults.returnValidationWindow
    }
}
