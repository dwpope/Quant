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
/// ┌─ Anything to nudge for? ────────────── No ──→ .none  (sitting well or away)
/// │
/// ├─ Is tracking quality good enough? ──── No ──→ .suppressed(.lowTrackingQuality)
/// │
/// ├─ Is user stretching? ──────────────── Yes ──→ .suppressed(.userStretching)
/// │
/// ├─ Is cooldown active? ──────────────── Yes ──→ .suppressed(.cooldownActive)
/// │
/// ├─ Max nudges per hour reached? ─────── Yes ──→ .suppressed(.maxNudgesReached)
/// │
/// ├─ Has bad posture lasted long enough? ─ No ──→ .pending(timeRemaining: ...)
/// │
/// └─ All checks passed! ───────────────────────→ .fire(reason: .sustainedSlouch)
/// ```
///
/// ### Cooldown System
///
/// After a nudge fires, a cooldown period starts (default: 10 minutes).
/// A slouch left uncorrected isn't nudged again until it ends, so the app
/// doesn't nag. Sitting well for 30 s (or leaving the desk) ends it early: the
/// next slouch is nudged like any other (2026-10-08).
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
/// `acknowledgementWindow`), we record that the nudge "worked". It doesn't hold
/// anything back: a slouch after sitting up is timed like any other and nudged
/// once it's held long enough, subject to the cooldown and the hourly cap. Until
/// 2026-10-05 it suppressed slouch nudges, and nothing cleared it, so one
/// corrected nudge silenced slouch nudges until the app was quit.
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
/// t=380:   User slouches again...
/// t=680:   Bad for 5 min BUT cooldown active (need 10 min) → .suppressed
/// t=961:   Cooldown expired + 5 min bad → .fire! (if within hourly limit)
/// ```
final class NudgeEngine: NudgeEngineProtocol {

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
    var debugState: [String: Any] {
        [
            "nudgesThisHour": nudgeTimestamps.count,
            "lastNudgeTime": lastNudgeTime ?? 0,
            "cooldownRemaining": lastCooldownRemaining,
            "acknowledged": hasBeenAcknowledged,
            "lastDecision": lastDecisionDescription,
            "slouchedTime": slouchedTime,
        ]
    }

    // MARK: - Configuration

    /// The thresholds that control nudge timing and limits.
    /// These come from PostureThresholds and include:
    /// - `slouchDurationBeforeNudge` (default: 300s = 5 minutes)
    /// - `nudgeCooldown` (default: 600s = 10 minutes)
    /// - `maxNudgesPerHour` (default: 2)
    /// - `acknowledgementWindow` (default: 30s)
    ///
    /// Settable so `Pipeline.thresholds` can pass changes on. Until 2026-10-01 this was fixed
    /// at init, so limits changed later reached the posture engine and not this one.
    var thresholds: PostureThresholds

    /// How long a head held turned waits before its nudge. Settable for the same reason.
    var headTurnThresholds: HeadTurnThresholds

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
    /// recent nudge. Recorded for the debug overlay; it suppresses nothing.
    ///
    /// Until 2026-10-05 it suppressed slouch nudges until a new nudge fired or the
    /// engine was reset. The app never resets the engine, and a suppressed slouch
    /// can't fire, so one corrected nudge silenced slouch nudges until the app was
    /// quit. Dave expects to be nudged again when he slouches again.
    ///
    /// This flag is cleared when:
    /// - A new nudge fires
    /// - The engine is reset
    private var hasBeenAcknowledged: Bool = false

    /// Cached cooldown remaining for the debug overlay.
    /// Updated each time `evaluate()` is called.
    private var lastCooldownRemaining: TimeInterval = 0

    /// Human-readable description of the last decision for debugging.
    private var lastDecisionDescription: String = "none"

    // MARK: - Slouched time (2026-10-07)
    //
    // Dave worked for an hour and got no nudge: it took `slouchDurationBeforeNudge` of unbroken
    // slouching, and the posture engine restarts its episode on one good frame while drifting or
    // 5 s of good once bad. Reaching for the mouse was enough. So slouched time is added up here
    // instead: frames while drifting or bad add to it, brief good moments pause it, and
    // `slouchEpisodeEndsAfterGood` of good posture ends the episode.

    /// How long sitting well ends a slouch episode. Shorter is a sit-up or a reach.
    var slouchEpisodeEndsAfterGood: TimeInterval = 30

    /// A gap between frames longer than this (the app paused) is a break, not slouching.
    private let maxFrameGap: TimeInterval = 60

    /// Slouched seconds in the current episode.
    private var slouchedTime: TimeInterval = 0
    /// Good seconds since the last slouched frame.
    private var goodStreak: TimeInterval = 0
    private var lastEvaluationTime: TimeInterval?

    /// Whether a slouch episode has ended (sitting well for `slouchEpisodeEndsAfterGood`) since
    /// the last nudge. The cooldown only holds back the slouch that was nudged, left uncorrected;
    /// after sitting up, the next slouch is nudged like any other (2026-10-08). Dave saw the
    /// cooldown hold back slouches that began after he'd sat up.
    private var correctedSinceLastNudge = false

    // MARK: - Initialization

    /// Creates a new NudgeEngine with the given thresholds.
    ///
    /// - Parameter thresholds: The configurable thresholds that control nudge
    ///   timing and limits. Pass `PostureThresholds()` for defaults.
    init(thresholds: PostureThresholds = PostureThresholds(),
         headTurnThresholds: HeadTurnThresholds = HeadTurnThresholds()) {
        self.thresholds = thresholds
        self.headTurnThresholds = headTurnThresholds
    }

    // MARK: - NudgeEngineProtocol

    /// Evaluate whether a nudge should fire right now.
    ///
    /// This method runs through the suppression checklist (tracking quality,
    /// task mode, cooldown, hourly limit) and then checks
    /// whether the bad-posture duration exceeds the threshold.
    ///
    /// When a nudge fires or is pending, the engine determines the specific
    /// reason by comparing current metrics against their thresholds. The metric
    /// with the largest `value / threshold` ratio is the dominant violation.
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
    ///   - metrics: The current posture metrics, used to determine the specific
    ///     nudge reason. Pass `nil` to default to `.sustainedSlouch`.
    ///   - headTurnedSince: When the head was last turned and held there (`HeadTurnTracker`),
    ///     or nil. A second thing to nudge for, sharing the cooldown and the hourly cap.
    ///   - silenced: Whether the user has silenced nudges for now. Every nudge waits.
    /// - Returns: A `NudgeDecision` indicating what the caller should do.
    func evaluate(
        state: PostureState,
        trackingQuality: TrackingQuality,
        movementLevel: Float,
        taskMode: TaskMode,
        currentTime: TimeInterval,
        metrics: RawMetrics? = nil,
        headTurnedSince: TimeInterval? = nil,
        silenced: Bool = false
    ) -> NudgeDecision {

        // ──────────────────────────────────────────────
        // STEP 1: Prune old nudge timestamps
        // ──────────────────────────────────────────────
        //
        // Remove nudges older than 1 hour from our tracking array.
        // This implements the "rolling hour" window — nudges from
        // 61 minutes ago no longer count toward the hourly limit.
        pruneOldNudges(currentTime: currentTime)

        // Add up slouched time, before any early return so it keeps counting through a cooldown.
        let slouchedNow = isSlouched(state)
        countSlouchedTime(state: state, slouched: slouchedNow, trackingQuality: trackingQuality,
                          currentTime: currentTime)

        // Update cached cooldown for debug overlay
        lastCooldownRemaining = cooldownRemaining(at: currentTime)

        // ──────────────────────────────────────────────
        // STEP 2: Check suppression conditions
        // ──────────────────────────────────────────────
        //
        // These are checked in order of "cheapest first" — simple
        // enum comparisons before timestamp math.

        // 2·. Silenced — the user asked for quiet for a while, from the phone or the Watch.
        //     Every nudge waits. Timers keep running, so a slouch still going when the
        //     silence ends is nudged straight away.
        if silenced {
            lastDecisionDescription = "suppressed: silenced"
            return .suppressed(reason: .silenced)
        }

        // Nothing to nudge for — sitting well, or nobody in view, and no head held turned:
        // say so. "Suppressed" means a nudge is being held back, and Dave saw it while sitting
        // well through a cooldown (2026-10-08).
        if !slouchedNow && headTurnedSince == nil {
            lastDecisionDescription = "none (nothing to nudge for)"
            return .none
        }

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

        // 2c. Cooldown active — a nudge was recently fired and the slouch it was for goes on.
        //     We don't want to nag the user: an uncorrected slouch waits `nudgeCooldown`
        //     (default: 10 minutes) to be nudged again. Sitting up ends that slouch and the
        //     wait with it (2026-10-08).
        if isCoolingDown(at: currentTime) {
            let decision = NudgeDecision.suppressed(reason: .cooldownActive)
            lastDecisionDescription = "suppressed: cooldownActive (\(String(format: "%.0f", lastCooldownRemaining))s remaining)"
            return decision
        }

        // 2d. Hourly limit reached — too many nudges this hour.
        //     Even if cooldown has expired, cap total nudges per hour
        //     (default: 2) to prevent annoyance.
        if thresholds.maxNudgesPerHour > 0,
           nudgeTimestamps.count >= thresholds.maxNudgesPerHour {
            let decision = NudgeDecision.suppressed(reason: .maxNudgesReached)
            lastDecisionDescription = "suppressed: maxNudgesReached (\(nudgeTimestamps.count)/\(thresholds.maxNudgesPerHour))"
            return decision
        }

        // An acknowledged nudge (the user sat up after it) suppresses nothing: a slouch after
        // sitting up is timed from its own start like any other (2026-10-05).

        // ──────────────────────────────────────────────
        // STEP 3: The head held turned
        // ──────────────────────────────────────────────
        //
        // While the head is turned its nudge wins: a turned head reads the shoulders wider
        // (6 of 8 measured head turns, +0.06 to +0.16), which is what the slouch thresholds
        // look for, so a "slouch" then is likelier the turn. Its advice is to turn the chair.
        var headTurnRemaining: TimeInterval?
        if let turnedSince = headTurnedSince {
            let turnedFor = currentTime - turnedSince
            if turnedFor >= headTurnThresholds.durationBeforeNudge {
                lastDecisionDescription = "FIRE: headTurned (turned for \(String(format: "%.0f", turnedFor))s)"
                return .fire(reason: .headTurned)
            }
            headTurnRemaining = headTurnThresholds.durationBeforeNudge - turnedFor
        }

        // ──────────────────────────────────────────────
        // STEP 4: Check if posture is actually bad
        // ──────────────────────────────────────────────
        //
        // Only a slouch going on now can trigger a slouch nudge: `.drifting` or `.bad`.
        // `.good`, `.absent` and `.calibrating` leave only the head turn, if any, counting down.
        guard slouchedNow else {
            if let remaining = headTurnRemaining {
                lastDecisionDescription = "pending (headTurned): \(String(format: "%.0f", remaining))s remaining"
                return .pending(reason: .headTurned, timeRemaining: remaining)
            }
            let decision = NudgeDecision.none
            lastDecisionDescription = "none (state is not .bad)"
            return decision
        }

        // ──────────────────────────────────────────────
        // STEP 5: Check slouch duration
        // ──────────────────────────────────────────────
        //
        // How long the user has been slouched in this episode, added up across brief
        // sit-ups (see "Slouched time" above).
        let duration = slouchedTime

        // Determine the dominant violation from the current metrics.
        // Compare each metric against its threshold as a ratio — the
        // metric with the highest ratio is the primary reason.
        let reason = dominantReason(from: metrics)

        if duration >= thresholds.slouchDurationBeforeNudge {
            // ──────────────────────────────────────────
            // FIRE! All conditions met.
            // ──────────────────────────────────────────
            //
            // The caller (Pipeline or AppModel) should:
            // 1. Deliver feedback (audio cue, watch haptic)
            // 2. Call `Pipeline.recordNudgeFired()` to start cooldown, on the frame clock
            let decision = NudgeDecision.fire(reason: reason)
            lastDecisionDescription = "FIRE: \(reason.rawValue) (slouched \(String(format: "%.0f", duration))s)"
            return decision
        }

        // ──────────────────────────────────────────────
        // STEP 6: Not yet — return pending with countdown
        // ──────────────────────────────────────────────
        //
        // Posture is bad but hasn't been bad long enough.
        // Return `.pending` with the time remaining so the UI can
        // show a countdown if desired: whichever nudge is sooner.
        let remaining = thresholds.slouchDurationBeforeNudge - duration
        if let turnRemaining = headTurnRemaining, turnRemaining < remaining {
            lastDecisionDescription = "pending (headTurned): \(String(format: "%.0f", turnRemaining))s remaining"
            return .pending(reason: .headTurned, timeRemaining: turnRemaining)
        }
        let decision = NudgeDecision.pending(reason: reason, timeRemaining: remaining)
        lastDecisionDescription = "pending (\(reason.rawValue)): \(String(format: "%.0f", remaining))s remaining"
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
    func recordNudgeFired(at currentTime: TimeInterval) {
        lastNudgeTime = currentTime
        nudgeTimestamps.append(currentTime)
        hasBeenAcknowledged = false  // New nudge episode
        slouchedTime = 0  // the next nudge needs its own slouched time
        goodStreak = 0
        correctedSinceLastNudge = false
    }

    /// Record that the user corrected their posture after a nudge.
    ///
    /// Sets the acknowledgement flag: the nudge worked. It suppresses nothing; a
    /// slouch after this is nudged once it's held long enough.
    ///
    /// The flag is automatically cleared when:
    /// - A new nudge fires (`recordNudgeFired`)
    /// - The engine is reset (`reset()`)
    func recordAcknowledgement() {
        hasBeenAcknowledged = true
    }

    /// Reset all internal state back to initial values.
    ///
    /// Call this when:
    /// - The app relaunches
    /// - Calibration restarts
    /// - The user has been absent for an extended period
    func reset() {
        nudgeTimestamps = []
        lastNudgeTime = nil
        hasBeenAcknowledged = false
        lastCooldownRemaining = 0
        lastDecisionDescription = "none"
        slouchedTime = 0
        goodStreak = 0
        lastEvaluationTime = nil
        correctedSinceLastNudge = false
    }

    // MARK: - Slouched time

    private func isSlouched(_ state: PostureState) -> Bool {
        switch state {
        case .drifting, .bad: return true
        case .good, .absent, .calibrating: return false
        }
    }

    /// Adds this frame's time to the slouched total or the good streak. Nothing counts without a
    /// clear view; a long gap between frames is a break. On the very first frame there's no
    /// interval yet, so a slouch already under way counts from the posture engine's start.
    private func countSlouchedTime(state: PostureState, slouched: Bool, trackingQuality: TrackingQuality,
                                   currentTime: TimeInterval) {
        defer { lastEvaluationTime = currentTime }
        guard let last = lastEvaluationTime else {
            switch state {
            case .drifting(let since), .bad(let since): slouchedTime = max(0, currentTime - since)
            default: slouchedTime = 0
            }
            return
        }
        let dt = currentTime - last
        guard dt >= 0, dt <= maxFrameGap else {
            slouchedTime = 0
            goodStreak = 0
            return
        }
        // Away from the desk ends a slouch like sitting well does, though nothing can be seen.
        if state == .absent {
            endsTheSlouch(after: dt)
            return
        }
        guard trackingQuality.allowsPostureJudgement else { return }
        if slouched {
            // Only the part of the interval since the slouch began: frames can be sparse.
            let since: TimeInterval
            switch state {
            case .drifting(let s), .bad(let s): since = s
            default: since = last
            }
            slouchedTime += currentTime - max(last, min(since, currentTime))
            goodStreak = 0
        } else {
            endsTheSlouch(after: dt)
        }
    }

    /// Good time, toward ending the slouch: `slouchEpisodeEndsAfterGood` of it does, and with it
    /// the cooldown after a nudge.
    private func endsTheSlouch(after dt: TimeInterval) {
        goodStreak += dt
        if goodStreak >= slouchEpisodeEndsAfterGood {
            slouchedTime = 0
            correctedSinceLastNudge = true
        }
    }

    // MARK: - Private Helpers

    /// Determine the dominant posture violation from the current metrics.
    ///
    /// Compares each metric against its threshold as a ratio (`value / threshold`).
    /// The metric with the highest ratio is the primary reason for the nudge.
    /// Falls back to `.sustainedSlouch` when no metrics are provided or no
    /// single metric clearly dominates.
    ///
    /// - Parameter metrics: The current posture metrics, or `nil`.
    /// - Returns: The `NudgeReason` for the dominant violation.
    private func dominantReason(from metrics: RawMetrics?) -> NudgeReason {
        guard let metrics = metrics else { return .sustainedSlouch }

        // Compute ratio of each metric to its threshold.
        // Higher ratio = more severe violation relative to its threshold.
        let forwardCreepRatio: Float = thresholds.forwardCreepThreshold > 0
            ? metrics.forwardCreep / thresholds.forwardCreepThreshold
            : 0

        // A dropping head reads NEGATIVE on the device (image y runs down; see
        // `PostureThresholds.headDropThreshold`), so it's the negated value that's compared.
        let headDropRatio: Float = thresholds.headDropThreshold > 0
            ? -metrics.headDrop / thresholds.headDropThreshold
            : 0

        let sinkRatio: Float = thresholds.shoulderSinkThreshold > 0
            ? metrics.shoulderSink / thresholds.shoulderSinkThreshold
            : 0

        // Pick the metric with the highest ratio, if it's past its line and alone at the top.
        // A tie, or nothing past its line, falls back to the general reason.
        let ratios: [(NudgeReason, Float)] = [
            (.forwardCreep, forwardCreepRatio), (.headDrop, headDropRatio), (.sink, sinkRatio),
        ]
        guard let top = ratios.map(\.1).max(), top > 1.0,
              ratios.filter({ $0.1 == top }).count == 1,
              let winner = ratios.first(where: { $0.1 == top })
        else { return .sustainedSlouch }
        return winner.0
    }

    /// Calculate how many seconds remain in the cooldown period.
    ///
    /// Returns 0 if no nudge has been fired or cooldown has expired.
    ///
    /// - Parameter currentTime: The current timestamp.
    /// - Returns: Seconds remaining in cooldown (0 if none).
    private func cooldownRemaining(at currentTime: TimeInterval) -> TimeInterval {
        guard isCoolingDown(at: currentTime), let lastTime = lastNudgeTime else { return 0 }
        return max(0, thresholds.nudgeCooldown - (currentTime - lastTime))
    }

    /// Within `nudgeCooldown` of the last nudge, and the slouch it was for hasn't ended.
    private func isCoolingDown(at currentTime: TimeInterval) -> Bool {
        guard let lastTime = lastNudgeTime, !correctedSinceLastNudge else { return false }
        return currentTime - lastTime <= thresholds.nudgeCooldown
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

// MARK: - User-Facing Copy

extension NudgeReason {

    /// A short, actionable coaching line for the dominant violation — the
    /// user-facing guidance a nudge carries (audio caption / watch text).
    ///
    /// Keyed off the same `NudgeReason` the engine already picks in
    /// `dominantReason(from:)`, so the specific correction matches the specific
    /// slouch: forward creep asks the user to sit back, head/neck carriage asks
    /// them to lift, and the general slouch gets the neutral "sit up" line.
    /// Kept to one imperative clause each so it fits a glanceable prompt (same
    /// tone as the analytics copy in `NudgeInsights.dominantReasonDescription`).
    public var coachingMessage: String {
        switch self {
        case .sustainedSlouch: return "Sit up — reset your posture"
        case .forwardCreep:    return "Sit back — you're leaning in"
        case .headDrop:        return "Lift your head — ease your neck back"
        case .headTurned:      return "Turn your chair to face that screen"
        case .sink:            return "Sit up — slide back in your chair"
        }
    }
}
