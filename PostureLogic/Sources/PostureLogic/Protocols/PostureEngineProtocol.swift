import Foundation

/// Protocol for the posture state machine that judges posture over time.
///
/// Implementations receive smoothed metrics each frame and decide whether the
/// user's posture is currently good, drifting toward bad, or sustained-bad.
/// The engine should pause its internal timers when tracking quality is too
/// low to make reliable judgements.
protocol PostureEngineProtocol: DebugDumpable {
    /// Evaluate the latest metrics and return the updated posture state.
    ///
    /// - Parameters:
    ///   - metrics: Smoothed posture metrics (deltas from baseline).
    ///   - taskMode: Current activity classification (reading, typing, etc.).
    ///   - trackingQuality: How reliable the current pose data is.
    ///   - chairTurned: The whole chair is turned (head and shoulders), so a head drop
    ///     isn't counted as a slouch.
    ///   - reclined: Leaning back against the backrest, so neither a shoulder sink nor a head
    ///     drop is counted as a slouch.
    ///   - neckTurned: The head turned with the shoulders square, so forward creep isn't counted.
    /// - Returns: The new `PostureState` after this update.
    func update(
        metrics: RawMetrics,
        taskMode: TaskMode,
        trackingQuality: TrackingQuality,
        chairTurned: Bool,
        reclined: Bool,
        neckTurned: Bool
    ) -> PostureState

    /// Reset the state machine back to `.absent`. Call this when calibration
    /// restarts, the user leaves and returns, or the app relaunches.
    func reset()
}
