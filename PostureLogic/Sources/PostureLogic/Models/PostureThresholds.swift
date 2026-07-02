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
    /// nose-relative. Because the ear moves much less than the nose for the same
    /// look-down, the old `0.06` never tripped: on device, bad carriage only reached
    /// ~0.025 and mild ~0.012. Lowered to **0.018** to sit between mild and bad.
    ///
    /// **Provisional.** This value came from raw on-device readings taken *before*
    /// `headDrop` gained its dedicated One Euro denoiser (see ``MetricsSmoother``).
    /// Re-tune on device against the now-smoothed signal — the smoothed `headDrop`
    /// should flicker far less at a fixed pose, so the mild/bad separation this
    /// straddles should be cleaner than the raw numbers above.
    public var headDropThreshold: Float = 0.018
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
