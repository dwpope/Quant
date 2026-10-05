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
    /// Head-rise trip point, in shoulder widths: posture is off when `headDrop` is at or below
    /// MINUS this, the head that much HIGHER in the image than at calibration. `headDrop` is
    /// **ear-sourced** (ear-midpoint carriage above the shoulders), positive when lower.
    ///
    /// **Flipped 2026-10-05.** With the phone below eye level, leaning towards it makes the head
    /// look higher: all 15 of Dave's slouches across five device sessions read -0.013 to -0.186,
    /// and every upright -0.007 or above. The old trip point, +0.15 downwards (derived on
    /// 2026-07-03 in a setup where slouching read positive), never caught one here and fired
    /// once in 64 captures, on a chair swivel. 0.015 is the Jev wording's point. Which way a
    /// slouch reads depends on where the camera sits relative to the eyes.
    public var headDropThreshold: Float = 0.015
    public var shoulderRoundingThreshold: Float = 10.0

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
}
