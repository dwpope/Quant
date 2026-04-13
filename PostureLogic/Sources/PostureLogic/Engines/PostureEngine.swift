import Foundation

/// The posture state machine that tracks how the user's posture evolves over time.
///
/// ## How It Works
///
/// Think of the state machine like a traffic light for your posture:
///
/// ```
///  ┌─────────┐   bad metrics   ┌──────────┐  timeout  ┌─────────┐
///  │  GOOD   │ ──────────────> │ DRIFTING  │ ───────> │   BAD   │
///  │  (green)│ <────────────── │ (yellow)  │          │  (red)  │
///  └─────────┘   good metrics  └──────────┘          └─────────┘
///       ^                                                 │
///       └─────────────── good metrics ────────────────────┘
/// ```
///
/// - **Good**: All posture metrics are within acceptable thresholds.
/// - **Drifting**: At least one metric has crossed a threshold, but the user
///   hasn't been in this state long enough to count as "bad" yet.
///   This is a grace period — maybe the user just shifted temporarily.
/// - **Bad**: The user has been drifting for longer than `driftingToBadThreshold`
///   (default: 60 seconds). This is sustained poor posture.
///
/// ### Key Safety Rule
///
/// When tracking quality is not `.good` (e.g., the user stepped out of frame
/// or lighting is bad), the engine **freezes** — it does NOT count that time
/// toward the drifting-to-bad transition. This prevents false alarms when
/// the camera can't see the user clearly.
///
/// ### Task Mode Adjustments
///
/// Different activities get different tolerance levels. For example, reading
/// naturally involves a slight forward lean, so the `forwardCreep` threshold
/// is relaxed by 20% in reading mode. Stretching disables posture judgement
/// entirely (you *should* be moving around!).
final class PostureEngine: PostureEngineProtocol {

    // MARK: - Debug State

    /// Exposes the engine's internal state for the debug overlay.
    /// This dictionary is displayed in the DebugOverlayView so you can
    /// watch the state machine transitions in real time.
    var debugState: [String: Any] {
        [
            "state": stateDescription(currentState),
            "accumulatedDriftTime": accumulatedDriftTime,
            "recoveryStartTime": recoveryStartTime as Any,
            "lostQualityStart": lostQualityStart as Any,
            "absenceDeclaredAt": absenceDeclaredAt as Any,
            "returnValidationStart": returnValidationStart as Any,
        ]
    }

    // MARK: - Configuration

    /// The thresholds that control when posture is considered "bad".
    /// These come from PostureThresholds and can be changed at runtime
    /// via the settings screen (Ticket 7.3).
    var thresholds: PostureThresholds

    // MARK: - Internal State

    /// The current posture state. This is the "traffic light" value.
    private var currentState: PostureState = .absent

    /// Accumulated time (in seconds) that the user has been continuously
    /// drifting. This counter pauses whenever tracking quality drops below
    /// `.good`, so unreliable frames don't count against the user.
    ///
    /// When this exceeds `thresholds.driftingToBadThreshold`, the state
    /// transitions from `.drifting` to `.bad`.
    private var accumulatedDriftTime: TimeInterval = 0

    /// The timestamp of the last metrics update that had good tracking.
    /// Used to calculate how much time has passed between quality updates,
    /// so we can accurately accumulate drift time even if frames arrive
    /// at irregular intervals.
    private var lastGoodUpdateTimestamp: TimeInterval?

    /// When the user starts recovering from `.bad` posture, we record the
    /// timestamp here. The user must maintain good posture for at least
    /// `thresholds.recoveryGracePeriod` seconds before we transition back
    /// to `.good`. This prevents flickering between states if the user
    /// briefly straightens up then slumps again.
    private var recoveryStartTime: TimeInterval?

    // MARK: - Absence Tracking (internal)

    /// Timestamp when `.lost` quality was first observed in the current run.
    /// Nil when quality is not `.lost`. Used to enforce the absentThreshold dwell.
    private var lostQualityStart: TimeInterval?

    /// The posture state saved immediately before entering `.absent`.
    /// Restored when the user returns after a short absence.
    private var savedPostureState: PostureState?

    /// Accumulated drift time saved alongside savedPostureState.
    /// Restored so the drifting-to-bad timer picks up where it left off.
    private var savedDriftTime: TimeInterval = 0

    /// Timestamp when `.absent` was declared via saveAndDeclareAbsent.
    /// Nil during cold-start `.absent` (no real absence has been detected yet).
    private var absenceDeclaredAt: TimeInterval?

    /// Timestamp when return-validation started (quality first recovered to .good
    /// after a real absence). Nil when not in a validation window.
    private var returnValidationStart: TimeInterval?

    /// Set to true when a long-absence return commits. Pipeline reads and clears
    /// this via consumeRecalibrationPrompt() to show a dismissible prompt.
    var pendingRecalibrationPrompt: Bool = false

    // MARK: - Initialization

    /// Creates a new PostureEngine with the given thresholds.
    ///
    /// - Parameter thresholds: The configurable thresholds that control
    ///   sensitivity. Pass `PostureThresholds()` for defaults.
    init(thresholds: PostureThresholds = PostureThresholds()) {
        self.thresholds = thresholds
    }

    // MARK: - PostureEngineProtocol

    /// The main entry point called every time new metrics arrive.
    ///
    /// This method implements the state machine transitions:
    ///
    /// 1. If tracking quality is not `.good`, we **freeze** — return the
    ///    current state without advancing any timers.
    /// 2. If we're in `.absent` or `.calibrating`, move to `.good`
    ///    (the user just showed up or finished calibrating).
    /// 3. If we're in `.good`, check if metrics exceed thresholds.
    ///    If so, transition to `.drifting`.
    /// 4. If we're in `.drifting`, accumulate time. If metrics improve,
    ///    go back to `.good`. If time exceeds the threshold, go to `.bad`.
    /// 5. If we're in `.bad`, watch for recovery. The user must maintain
    ///    good posture for `recoveryGracePeriod` seconds to return to `.good`.
    ///
    /// - Parameters:
    ///   - metrics: The latest smoothed metrics from MetricsEngine + MetricsSmoother.
    ///   - taskMode: Current activity (reading, typing, etc.) — affects thresholds.
    ///   - trackingQuality: How reliable the current camera data is.
    /// - Returns: The updated PostureState.
    @discardableResult
    func update(
        metrics: RawMetrics,
        taskMode: TaskMode,
        trackingQuality: TrackingQuality
    ) -> PostureState {
        // ──────────────────────────────────────────────
        // SAFETY GATE: Don't judge posture with bad data
        // ──────────────────────────────────────────────
        //
        // When tracking quality is not good enough, we freeze the state
        // machine. We clear the last-good timestamp so that when quality
        // recovers, we don't count the gap as drift time.
        // handleNonGoodQuality also manages the lost-dwell timer for
        // absent detection and resets the return-validation window.
        guard trackingQuality.allowsPostureJudgement else {
            lastGoodUpdateTimestamp = nil
            handleNonGoodQuality(quality: trackingQuality, at: metrics.timestamp)
            return currentState
        }

        // Quality is .good — reset the lost-dwell tracker.
        lostQualityStart = nil

        // ──────────────────────────────────────────────
        // RETURN VALIDATION after a real absence
        // ──────────────────────────────────────────────
        //
        // After a tracked absence (absenceDeclaredAt != nil), require
        // returnValidationWindow seconds of continuous good-quality data
        // before committing to the restored state. This avoids a flicker
        // where one good frame immediately ends a long absence.
        if currentState == .absent, let declaredAt = absenceDeclaredAt {
            if returnValidationStart == nil {
                returnValidationStart = metrics.timestamp
            }
            let validationElapsed = metrics.timestamp - returnValidationStart!
            if validationElapsed < thresholds.returnValidationWindow {
                return currentState  // Still collecting validation data — stay absent
            }
            // Validation complete — commit the return from absence.
            returnValidationStart = nil
            commitReturnFromAbsence(absenceDuration: metrics.timestamp - declaredAt)
        }

        // Calculate elapsed time since the last reliable update.
        // This is used to accurately track how long the user has been drifting,
        // even if frames arrive at irregular intervals.
        let elapsed: TimeInterval
        if let lastTimestamp = lastGoodUpdateTimestamp {
            elapsed = metrics.timestamp - lastTimestamp
        } else {
            elapsed = 0  // First good frame after a gap — don't count any time
        }
        lastGoodUpdateTimestamp = metrics.timestamp

        // Check whether current posture exceeds thresholds
        let isPostureBad = checkPostureBad(metrics: metrics, taskMode: taskMode)

        // ──────────────────────────────────────
        // STATE MACHINE TRANSITIONS
        // ──────────────────────────────────────

        switch currentState {

        // ── ABSENT / CALIBRATING ──
        // The user just appeared or finished calibrating.
        // Move directly to .good — we assume calibration captured
        // their "good" posture as the baseline.
        case .absent, .calibrating:
            currentState = .good
            accumulatedDriftTime = 0
            recoveryStartTime = nil

        // ── GOOD ──
        // Everything is fine. Check if posture has started to degrade.
        case .good:
            if isPostureBad {
                // Posture just crossed a threshold — start the drifting timer.
                // We record the current metrics timestamp as the "since" value
                // so the debug UI can show how long the user has been drifting.
                currentState = .drifting(since: metrics.timestamp)
                accumulatedDriftTime = 0
                recoveryStartTime = nil
            }

        // ── DRIFTING ──
        // The user's posture is bad, but they haven't been bad long enough
        // to warrant a nudge. This is the "yellow light" zone.
        case .drifting(let since):
            if !isPostureBad {
                // Posture improved — go straight back to good.
                // No grace period needed when coming from drifting,
                // because we haven't committed to "bad" yet.
                currentState = .good
                accumulatedDriftTime = 0
                recoveryStartTime = nil
            } else {
                // Still bad — accumulate drift time.
                // We only add `elapsed` (time since last good-quality frame),
                // so paused-tracking gaps don't inflate this counter.
                accumulatedDriftTime += elapsed

                if accumulatedDriftTime >= thresholds.driftingToBadThreshold {
                    // Been drifting long enough — this is now sustained bad posture.
                    // We keep the original "since" timestamp from when drifting started,
                    // so the NudgeEngine (Sprint 4) can calculate total slouch duration.
                    currentState = .bad(since: since)
                    recoveryStartTime = nil
                }
            }

        // ── BAD ──
        // Sustained bad posture. The NudgeEngine (Sprint 4) will use this
        // state plus the "since" timestamp to decide when to fire a nudge.
        //
        // Recovery requires the user to maintain good posture for
        // `recoveryGracePeriod` seconds (default: 5). This prevents
        // the state from flickering between bad and good if the user
        // briefly sits up then slumps back.
        case .bad:
            if !isPostureBad {
                // Posture has improved! Start or continue recovery timer.
                if let recoveryStart = recoveryStartTime {
                    // Already in recovery — check if enough time has passed
                    let recoveryDuration = metrics.timestamp - recoveryStart
                    if recoveryDuration >= thresholds.recoveryGracePeriod {
                        // Successfully recovered!
                        currentState = .good
                        accumulatedDriftTime = 0
                        recoveryStartTime = nil
                    }
                    // else: still recovering, keep waiting
                } else {
                    // First frame of good posture after being bad — start timer
                    recoveryStartTime = metrics.timestamp
                }
            } else {
                // Still bad — reset any recovery progress.
                // The user briefly improved but slumped back before the
                // grace period elapsed.
                recoveryStartTime = nil
            }
        }

        return currentState
    }

    /// Resets the engine to `.absent` state and clears all timers.
    ///
    /// Call this when:
    /// - The user triggers recalibration
    /// - The user returns after being absent for >5 minutes
    /// - The app relaunches
    func reset() {
        currentState = .absent
        accumulatedDriftTime = 0
        lastGoodUpdateTimestamp = nil
        recoveryStartTime = nil
        lostQualityStart = nil
        savedPostureState = nil
        savedDriftTime = 0
        absenceDeclaredAt = nil
        returnValidationStart = nil
        pendingRecalibrationPrompt = false
    }

    // MARK: - Threshold Checking

    /// Determines whether the current metrics indicate bad posture.
    ///
    /// This compares each metric against its threshold, with adjustments
    /// based on the current task mode. For example:
    /// - **Reading**: Forward lean threshold is relaxed by 20% (it's normal
    ///   to lean forward slightly when reading)
    /// - **Stretching**: Returns `false` always (don't judge posture while stretching)
    ///
    /// A posture is considered "bad" if ANY single metric exceeds its threshold.
    /// This is intentionally conservative — we want to catch slouching from
    /// any direction (forward lean, twist, or side lean).
    ///
    /// - Parameters:
    ///   - metrics: The current smoothed metrics.
    ///   - taskMode: The current activity classification.
    /// - Returns: `true` if posture exceeds at least one threshold.
    private func checkPostureBad(metrics: RawMetrics, taskMode: TaskMode) -> Bool {
        // Stretching mode disables posture judgement entirely.
        // The user is intentionally moving around — that's a good thing!
        if taskMode == .stretching {
            return false
        }

        // Apply task-mode-specific multipliers to thresholds.
        // Higher multiplier = more lenient (allows more deviation).
        let forwardCreepMultiplier: Float
        switch taskMode {
        case .reading:
            // Reading naturally involves leaning forward slightly
            forwardCreepMultiplier = 1.3
        case .meeting:
            forwardCreepMultiplier = 1.2
        default:
            forwardCreepMultiplier = 1.0
        }

        let twistMultiplier: Float
        switch taskMode {
        case .meeting:
            // Looking around during meetings is normal
            twistMultiplier = 1.5
        case .typing:
            twistMultiplier = 1.2
        default:
            twistMultiplier = 1.0
        }

        let sideLeanMultiplier: Float
        switch taskMode {
        case .meeting:
            sideLeanMultiplier = 1.2
        default:
            sideLeanMultiplier = 1.0
        }

        let shoulderRoundingMultiplier: Float
        switch taskMode {
        case .reading, .meeting:
            shoulderRoundingMultiplier = 1.2
        default:
            shoulderRoundingMultiplier = 1.0
        }

        // Check each metric against its (possibly adjusted) threshold.
        // We use abs() for forwardCreep because the metric can be positive
        // (leaning forward) — the absolute value catches both directions.
        let forwardThreshold = thresholds.forwardCreepThreshold * forwardCreepMultiplier
        let twistThreshold = thresholds.twistThreshold * twistMultiplier
        let sideLeanThreshold = thresholds.sideLeanThreshold * sideLeanMultiplier
        let headDropThreshold = thresholds.headDropThreshold
        let shoulderRoundingThreshold = thresholds.shoulderRoundingThreshold * shoulderRoundingMultiplier

        return metrics.forwardCreep > forwardThreshold
            || metrics.twist > twistThreshold
            || metrics.lateralLean > sideLeanThreshold
            || metrics.headDrop > headDropThreshold
            || metrics.shoulderRounding > shoulderRoundingThreshold
    }

    // MARK: - Absence Handling

    /// Freezes based on non-good quality, managing the lost-dwell timer.
    ///
    /// - `.degraded`: user is present but tracking is struggling. We freeze the
    ///   engine silently (no PostureState change) and reset the lost-dwell timer,
    ///   since the user hasn't actually gone away.
    /// - `.lost`: user may have left. We accumulate dwell time. Once the dwell
    ///   exceeds `absentThreshold`, we save the current state and declare `.absent`.
    private func handleNonGoodQuality(quality: TrackingQuality, at timestamp: TimeInterval) {
        switch quality {
        case .degraded:
            // User present, tracking struggling — freeze silently.
            // Reset lost-dwell (degraded ≠ lost) and any in-progress return validation.
            lostQualityStart = nil
            returnValidationStart = nil

        case .lost:
            // Reset return validation — we're moving away from a good signal.
            returnValidationStart = nil
            let dwellStart = lostQualityStart ?? timestamp
            lostQualityStart = dwellStart
            if timestamp - dwellStart >= thresholds.absentThreshold, currentState != .absent {
                saveAndDeclareAbsent(at: timestamp)
            }

        case .good:
            break  // unreachable: handled by guard above
        }
    }

    /// Saves the current real posture state and transitions to `.absent`.
    private func saveAndDeclareAbsent(at timestamp: TimeInterval) {
        switch currentState {
        case .good, .drifting, .bad:
            savedPostureState = currentState
            if case .drifting = currentState {
                savedDriftTime = accumulatedDriftTime
            } else {
                savedDriftTime = 0  // only .drifting carries a meaningful drift timer
            }
        default:
            break  // already in .absent/.calibrating — don't overwrite saved state
        }
        currentState = .absent
        absenceDeclaredAt = timestamp
    }

    /// Commits the return from a real absence after the validation window passes.
    ///
    /// Short absence (< absentResumeThreshold): restores the saved state.
    /// Long absence (≥ absentResumeThreshold): resets to `.good` and sets
    /// `pendingRecalibrationPrompt` so Pipeline can show the dismissible prompt.
    private func commitReturnFromAbsence(absenceDuration: TimeInterval) {
        defer {
            savedPostureState = nil
            savedDriftTime = 0
            absenceDeclaredAt = nil
        }
        if absenceDuration < thresholds.absentResumeThreshold, let saved = savedPostureState {
            // Short absence — resume where we left off.
            currentState = saved
            accumulatedDriftTime = savedDriftTime
        } else {
            // Long absence — fall through to .absent → .good via state machine.
            // Leave currentState as .absent (absenceDeclaredAt is cleared by defer,
            // so the guard in update() won't re-enter the validation path).
            currentState = .absent
            accumulatedDriftTime = 0
            recoveryStartTime = nil
            if absenceDuration >= thresholds.absentResumeThreshold {
                pendingRecalibrationPrompt = true
            }
        }
    }

    /// Returns true and clears the flag if a recalibration prompt is pending.
    ///
    /// Called by Pipeline after each `update` to check whether to show the
    /// "Welcome back — tap to recalibrate" dismissible prompt.
    func consumeRecalibrationPrompt() -> Bool {
        guard pendingRecalibrationPrompt else { return false }
        pendingRecalibrationPrompt = false
        return true
    }

    // MARK: - Helpers

    /// Produces a human-readable string for the current state.
    /// Used in the debug overlay to show exactly what's happening.
    private func stateDescription(_ state: PostureState) -> String {
        switch state {
        case .absent:
            return "absent"
        case .calibrating:
            return "calibrating"
        case .good:
            return "good"
        case .drifting(let since):
            return "drifting(since: \(String(format: "%.1f", since)))"
        case .bad(let since):
            return "bad(since: \(String(format: "%.1f", since)))"
        }
    }
}
