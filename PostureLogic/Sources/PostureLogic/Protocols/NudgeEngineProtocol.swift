import Foundation

/// Protocol for the nudge decision engine.
///
/// The NudgeEngine is the "final gatekeeper" in the posture detection pipeline.
/// It sits downstream of the PostureEngine and decides **when** to actually
/// bother the user with a nudge (haptic, audio, or watch tap).
///
/// ## Why This Exists
///
/// Just because posture is "bad" doesn't mean we should immediately nudge.
/// There are many reasons to delay or suppress a nudge:
/// - **Cooldown**: Don't spam the user — wait at least `nudgeCooldown` seconds
///   between nudges (default: 10 minutes).
/// - **Hourly limit**: Cap total nudges per hour (default: 2) to avoid annoyance.
/// - **Duration threshold**: Only nudge after sustained bad posture for
///   `slouchDurationBeforeNudge` seconds (default: 5 minutes).
/// - **Stretching**: If the user is intentionally stretching, don't fire.
/// - **Low tracking**: If the camera can't see the user clearly, don't fire.
///
/// ## How It Fits in the Pipeline
///
/// ```
/// Camera → PoseService → Fusion → Metrics → PostureEngine → NudgeEngine → Feedback
///                                              (state)        (decision)    (haptic/audio)
/// ```
///
/// The PostureEngine outputs the current `PostureState` (good/drifting/bad).
/// The NudgeEngine takes that state and all the suppression rules to produce
/// a `NudgeDecision`: fire, pending, suppressed, or none.
public protocol NudgeEngineProtocol: DebugDumpable {

    /// Evaluate whether a nudge should fire right now.
    ///
    /// Call this every time the PostureEngine produces a new state update.
    /// The engine checks the posture state against all the nudge rules
    /// (duration threshold, cooldown, hourly limit, suppression conditions)
    /// and returns a decision.
    ///
    /// - Parameters:
    ///   - state: The current posture state from PostureEngine.
    ///   - trackingQuality: How reliable the camera data is right now.
    ///   - movementLevel: How much the user is moving (0 = still, 1 = very active).
    ///   - taskMode: The current activity classification (reading, typing, etc.).
    ///   - currentTime: The current timestamp (seconds). Using an explicit parameter
    ///     instead of `Date()` makes this testable — tests can control time.
    /// - Returns: A `NudgeDecision` telling the caller what to do.
    func evaluate(
        state: PostureState,
        trackingQuality: TrackingQuality,
        movementLevel: Float,
        taskMode: TaskMode,
        currentTime: TimeInterval
    ) -> NudgeDecision

    /// Record that a nudge was just fired and delivered to the user.
    ///
    /// Call this immediately after the feedback layer (audio/haptic/watch)
    /// successfully delivers the nudge. This starts the cooldown timer
    /// and increments the hourly nudge counter.
    ///
    /// - Parameter currentTime: The timestamp when the nudge was delivered.
    func recordNudgeFired(at currentTime: TimeInterval)

    /// Record that the user corrected their posture after a nudge.
    ///
    /// Call this when the PostureEngine transitions from `.bad` back to `.good`
    /// within the `acknowledgementWindow` after a nudge was fired. This tells
    /// the engine "the user responded — the nudge worked."
    ///
    /// This can be used to suppress duplicate nudges for the same slouch episode
    /// and to track nudge effectiveness over time.
    func recordAcknowledgement()

    /// Reset all internal state (counters, timers, cooldowns).
    ///
    /// Call this when the app relaunches, calibration restarts, or the user
    /// has been absent for an extended period.
    func reset()
}
