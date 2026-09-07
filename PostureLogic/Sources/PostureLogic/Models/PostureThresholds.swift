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
    /// Head-drop trip point, in shoulder-widths of carriage loss. `headDrop` is
    /// **ear-sourced** (ear-midpoint carriage above the shoulders) rather than
    /// nose-relative.
    ///
    /// **Device-derived 2026-07-03**, first readings on honest instrumentation
    /// (3-decimal HUD, verified-fresh baseline, One Euro denoiser active):
    /// held-pose flicker ±0.001, mild slouch ≈ 0.10, clearly-bad carriage ≈ 0.22
    /// (max observed ≈ 0.24). `0.15` sits midway between mild and bad — everyday
    /// settling stays quiet, sustained bad carriage trips with ~50% margin, and
    /// the noise floor is two orders of magnitude below the trip point. Earlier
    /// values (0.06, then 0.018) were derived from readings later found to be
    /// display-truncated to 1 decimal — treat pre-2026-07-03 headDrop numbers
    /// as unreliable.
    public var headDropThreshold: Float = 0.15
    public var shoulderRoundingThreshold: Float = 10.0

    // MARK: - Confidence Gates
    public var minTrackingQuality: Float = 0.7
    public var minKeypointVisibility: Float = 0.7
    public var depthConfidenceThreshold: Float = 0.6
    
    // MARK: - Nudge Behavior
    public var nudgeCooldown: TimeInterval = 600
    public var maxNudgesPerHour: Int = 2
    public var acknowledgementWindow: TimeInterval = 30
    
    // MARK: - Mode Switching
    public var depthRecoveryDelay: TimeInterval = 2.0
    public var absentThreshold: TimeInterval = 1.0
    public var absentResumeThreshold: TimeInterval = 30.0
    public var returnValidationWindow: TimeInterval = 2.0
    
    public init() {}
}
