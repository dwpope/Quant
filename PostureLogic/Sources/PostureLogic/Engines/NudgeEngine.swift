import Foundation

/// The nudge decision engine — decides when to fire posture correction nudges.
///
/// ## How It Works
///
/// Think of this like a smart alarm system for your posture. It doesn't just
/// go off the moment something is wrong — it waits, checks the rules, and
/// only fires when it's truly appropriate.
///
/// ### The Decision Flow
///
/// Every time the PostureEngine says "posture is bad", this engine runs through
/// a checklist before deciding what to do:
///
/// ```
/// PostureState.bad(since: X)
///     │
///     ▼
/// ┌─ Is tracking quality good enough? ──── No ──→ .suppressed(.lowTrackingQuality)
/// │
/// ├─ Is user stretching? ──────────────── Yes ──→ .suppressed(.userStretching)
/// │
/// ├─ Is cooldown active? ──────────────── Yes ──→ .suppressed(.cooldownActive)
/// │
/// ├─ Max nudges per hour reached? ─────── Yes ──→ .suppressed(.maxNudgesReached)
/// │
/// ├─ Was this slouch already acknowledged? Yes ──→ .suppressed(.recentAcknowledgement)
/// │
/// ├─ Has bad posture lasted long enough? ─ No ──→ .pending(timeRemaining: ...)
/// │
/// └─ All checks passed! ───────────────────────→ .fire(reason: .sustainedSlouch)
/// ```
///
/// ### Cooldown System
///
/// After a nudge fires, a cooldown period starts (default: 10 minutes).
/// During this time, no new nudges will fire even if posture is still bad.
/// This prevents the app from nagging the user repeatedly.
///
/// ### Hourly Limit
///
/// There's also a cap on total nudges per hour (default: 2). Even if cooldown
/// has expired, once you've hit 2 nudges in the current hour, no more will fire.
/// The hour window rolls forward — it tracks nudge timestamps and only counts
/// nudges from the last 60 minutes.
///
/// ### Acknowledgement
///
/// When the user corrects their posture after a nudge (within the
/// `acknowledgementWindow`), we record that the nudge "worked". This prevents
/// re-nudging for the same slouch episode if the user briefly slumps again.
///
/// ## Example Timeline
///
/// ```
/// t=0:     User starts with good posture
/// t=60:    Posture degrades → PostureEngine: .drifting
/// t=120:   Still bad → PostureEngine: .bad(since: 60)
/// t=360:   Bad for 5 min → NudgeEngine: .fire! → Audio plays, watch taps
/// t=361:   NudgeEngine: recordNudgeFired() → cooldown starts
/// t=365:   User sits up → PostureEngine: .good → recordAcknowledgement()
/// t=500:   User slouches again...
/// t=800:   Bad for 5 min BUT cooldown active (need 10 min) → .suppressed
/// t=961:   Cooldown expired + 5 min bad → .fire! (if within hourly limit)
/// ```
public final class NudgeEngine: NudgeEngineProtocol {

    // MARK: - Debug State

    /// Exposes internal state for the debug overlay.
    ///
    /// This dictionary is displayed in DebugOverlayView so you can watch
    /// the nudge logic in real time. Useful for testing threshold values.
    ///
    /// Keys:
    /// - `nudgesThisHour`: How many nudges have fired in the rolling hour window.
    /// - `lastNudgeTime`: Timestamp of the most recent nudge (0 if none).
    /// - `cooldownRemaining`: Seconds left before a new nudge can fire.
    /// - `acknowledged`: Whether the most recent nudge was acknowledged.
    /// - `lastDecision`: Description of the last decision made.
    public var debugState: [String: Any] {
        [
            "nudgesThisHour": nudgeTimestamps.count,
            "lastNudgeTime": lastNudgeTime ?? 0,
            "cooldownRemaining": lastCooldownRemaining,
            "acknowledged": hasBeenAcknowledged,
            "lastDecision": lastDecisionDescription,
        ]
    }

    // MARK: - Configuration

    /// The thresholds that control nudge timing and limits.
    /// These come from PostureThresholds and include:
    /// - `slouchDurationBeforeNudge` (default: 300s = 5 minutes)
    /// - `nudgeCooldown` (default: 600s = 10 minutes)
    /// - `maxNudgesPerHour` (default: 2)
    /// - `acknowledgementWindow` (default: 30s)
    private let thresholds: PostureThresholds

    // MARK: - Internal State

    /// Timestamps of all nudges fired within the rolling hour window.
    ///
    /// We store individual timestamps rather than a simple counter so we can
    /// accurately implement a "rolling hour" — nudges older than 60 minutes
    /// are pruned, so the limit resets naturally over time.
    ///
    /// Example: If nudges fired at t=100 and t=800, and current time is t=3700,
    /// the first nudge (at t=100) is older than 3600s (1 hour) and gets pruned.
    /// Only the second nudge counts toward the limit.
    private var nudgeTimestamps: [TimeInterval] = []

    /// The timestamp of the most recent nudge. Used to calculate cooldown.
    /// `nil` means no nudge has ever fired (or state was reset).
    private var lastNudgeTime: TimeInterval?

    /// Whether the user has acknowledged (corrected posture after) the most
    /// recent nudge. When `true`, we suppress further nudges for the same
    /// slouch episode to avoid nagging about something they already fixed.
    ///
    /// This flag is cleared when:
    /// - A new nudge fires (new episode)
    /// - The engine is reset
    private var hasBeenAcknowledged: Bool = false

    /// Cached cooldown remaining for the debug overlay.
    /// Updated each time `evaluate()` is called.
    private var lastCooldownRemaining: TimeInterval = 0

    /// Human-readable description of the last decision for debugging.
    private var lastDecisionDescription: String = "none"

    // MARK: - Initialization

    /// Creates a new NudgeEngine with the given thresholds.
    ///
    /// - Parameter thresholds: The configurable thresholds that control nudge
    ///   timing and limits. Pass `PostureThresholds()` for defaults.
    public init(thresholds: PostureThresholds = PostureThresholds()) {
        self.thresholds = thresholds
    }

    // MARK: - NudgeEngineProtocol

    /// Evaluate whether a nudge should fire right now.
    ///
    /// This method runs through the suppression checklist (tracking quality,
    /// task mode, cooldown, hourly limit, acknowledgement) and then checks
    /// whether the bad-posture duration exceeds the threshold.
    ///
    /// The method is **pure** with respect to its inputs — it doesn't call
    /// `Date()` internally. Instead, you pass `currentTime` explicitly, which
    /// makes unit tests deterministic (you control time).
    ///
    /// - Parameters:
    ///   - state: The current posture state from PostureEngine.
    ///   - trackingQuality: How reliable the camera data is right now.
    ///   - movementLevel: How much the user is moving (0 = still, 1 = very active).
    ///   - taskMode: The current activity classification.
    ///   - currentTime: The current timestamp in seconds.
    /// - Returns: A `NudgeDecision` indicating what the caller should do.
    public func evaluate(
        state: PostureState,
        trackingQuality: TrackingQuality,
        movementLevel: Float,
        taskMode: TaskMode,
        currentTime: TimeInterval
    ) -> NudgeDecision {

        // ──────────────────────────────────────────────
        // STEP 1: Prune old nudge timestamps
        // ──────────────────────────────────────────────
        //
        // Remove nudges older than 1 hour from our tracking array.
        // This implements the "rolling hour" window — nudges from
        // 61 minutes ago no longer count toward the hourly limit.
        pruneOldNudges(currentTime: currentTime)

        // Update cached cooldown for debug overlay
        lastCooldownRemaining = cooldownRemaining(at: currentTime)

        // ──────────────────────────────────────────────
        // STEP 2: Check suppression conditions
        // ──────────────────────────────────────────────
        //
        // These are checked in order of "cheapest first" — simple
        // enum comparisons before timestamp math.

        // 2a. Low tracking quality — camera can't see the user clearly.
        //     This is the same safety rule the PostureEngine uses:
        //     if we're not sure what we're seeing, don't act on it.
        if !trackingQuality.allowsPostureJudgement {
            let decision = NudgeDecision.suppressed(reason: .lowTrackingQuality)
            lastDecisionDescription = "suppressed: lowTrackingQuality"
            return decision
        }

        // 2b. User is stretching — large intentional movements.
        //     Nudging someone who's stretching would be counterproductive!
        if taskMode == .stretching {
            let decision = NudgeDecision.suppressed(reason: .userStretching)
            lastDecisionDescription = "suppressed: userStretching"
            return decision
        }

        // 2c. Cooldown active — a nudge was recently fired.
        //     We don't want to nag the user. Wait at least `nudgeCooldown`
        //     seconds (default: 10 minutes) between nudges.
        if let lastTime = lastNudgeTime,
           currentTime - lastTime < thresholds.nudgeCooldown
        {
            let decision = NudgeDecision.suppressed(reason: .cooldownActive)
            lastDecisionDescription = "suppressed: cooldownActive (\(String(format: "%.0f", lastCooldownRemaining))s remaining)"
            return decision
        }

        // 2d. Hourly limit reached — too many nudges this hour.
        //     Even if cooldown has expired, cap total nudges per hour
        //     (default: 2) to prevent annoyance.
        if nudgeTimestamps.count >= thresholds.maxNudgesPerHour {
            let decision = NudgeDecision.suppressed(reason: .maxNudgesReached)
            lastDecisionDescription = "suppressed: maxNudgesReached (\(nudgeTimestamps.count)/\(thresholds.maxNudgesPerHour))"
            return decision
        }

        // 2e. Recent acknowledgement — user already corrected after last nudge.
        //     If the user fixed their posture after the last nudge but then
        //     slumped again, we suppress to avoid re-nudging for the same episode.
        //     The acknowledgement flag is cleared when a new nudge fires.
        if hasBeenAcknowledged {
            let decision = NudgeDecision.suppressed(reason: .recentAcknowledgement)
            lastDecisionDescription = "suppressed: recentAcknowledgement"
            return decision
        }

        // ──────────────────────────────────────────────
        // STEP 3: Check if posture is actually bad
        // ──────────────────────────────────────────────
        //
        // Only `.bad(since:)` state can trigger a nudge.
        // `.good`, `.drifting`, `.absent`, and `.calibrating` all
        // return `.none` — nothing to nudge about.
        guard case .bad(let since) = state else {
            let decision = NudgeDecision.none
            lastDecisionDescription = "none (state is not .bad)"
            return decision
        }

        // ──────────────────────────────────────────────
        // STEP 4: Check slouch duration
        // ──────────────────────────────────────────────
        //
        // Calculate how long the user has been in sustained bad posture.
        // The `since` timestamp comes from the PostureEngine — it's when
        // the state first transitioned to `.bad` (which preserves the
        // original `.drifting(since:)` timestamp).
        let duration = currentTime - since

        if duration >= thresholds.slouchDurationBeforeNudge {
            // ──────────────────────────────────────────
            // FIRE! All conditions met.
            // ──────────────────────────────────────────
            //
            // The caller (Pipeline or AppModel) should:
            // 1. Deliver feedback (audio cue, watch haptic)
            // 2. Call `recordNudgeFired(at:)` to start cooldown
            let decision = NudgeDecision.fire(reason: .sustainedSlouch)
            lastDecisionDescription = "FIRE: sustainedSlouch (bad for \(String(format: "%.0f", duration))s)"
            return decision
        }

        // ──────────────────────────────────────────────
        // STEP 5: Not yet — return pending with countdown
        // ──────────────────────────────────────────────
        //
        // Posture is bad but hasn't been bad long enough.
        // Return `.pending` with the time remaining so the UI can
        // show a countdown if desired.
        let remaining = thresholds.slouchDurationBeforeNudge - duration
        let decision = NudgeDecision.pending(reason: .sustainedSlouch, timeRemaining: remaining)
        lastDecisionDescription = "pending: \(String(format: "%.0f", remaining))s remaining"
        return decision
    }

    /// Record that a nudge was just fired and delivered to the user.
    ///
    /// This does three things:
    /// 1. Saves the nudge timestamp for cooldown calculation
    /// 2. Adds it to the rolling hour window for the hourly limit
    /// 3. Clears the acknowledgement flag (new nudge = new episode)
    ///
    /// - Parameter currentTime: When the nudge was delivered.
    public func recordNudgeFired(at currentTime: TimeInterval) {
        lastNudgeTime = currentTime
        nudgeTimestamps.append(currentTime)
        hasBeenAcknowledged = false  // New nudge episode
    }

    /// Record that the user corrected their posture after a nudge.
    ///
    /// Sets the acknowledgement flag, which suppresses further nudges
    /// for the same slouch episode. This prevents re-nudging if the user
    /// briefly corrects then slumps again within the same session.
    ///
    /// The flag is automatically cleared when:
    /// - A new nudge fires (`recordNudgeFired`)
    /// - The engine is reset (`reset()`)
    public func recordAcknowledgement() {
        hasBeenAcknowledged = true
    }

    /// Reset all internal state back to initial values.
    ///
    /// Call this when:
    /// - The app relaunches
    /// - Calibration restarts
    /// - The user has been absent for an extended period
    public func reset() {
        nudgeTimestamps = []
        lastNudgeTime = nil
        hasBeenAcknowledged = false
        lastCooldownRemaining = 0
        lastDecisionDescription = "none"
    }

    // MARK: - Private Helpers

    /// Calculate how many seconds remain in the cooldown period.
    ///
    /// Returns 0 if no nudge has been fired or cooldown has expired.
    ///
    /// - Parameter currentTime: The current timestamp.
    /// - Returns: Seconds remaining in cooldown (0 if none).
    private func cooldownRemaining(at currentTime: TimeInterval) -> TimeInterval {
        guard let lastTime = lastNudgeTime else { return 0 }
        let elapsed = currentTime - lastTime
        return max(0, thresholds.nudgeCooldown - elapsed)
    }

    /// Remove nudge timestamps older than 1 hour from the rolling window.
    ///
    /// This is called at the start of every `evaluate()` call to keep
    /// the `nudgeTimestamps` array clean and the hourly count accurate.
    ///
    /// - Parameter currentTime: The current timestamp.
    private func pruneOldNudges(currentTime: TimeInterval) {
        let oneHourAgo = currentTime - 3600  // 60 * 60 = 3600 seconds
        nudgeTimestamps.removeAll { $0 <= oneHourAgo }
    }
}
