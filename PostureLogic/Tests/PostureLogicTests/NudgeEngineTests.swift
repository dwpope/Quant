import XCTest
@testable import PostureLogic

/// Tests for the NudgeEngine (Ticket 4.1).
///
/// The NudgeEngine sits at the end of the posture detection pipeline and
/// decides **when** to actually deliver a nudge to the user. It enforces:
///
/// - **Duration threshold**: Only nudge after sustained bad posture (default: 5 min)
/// - **Cooldown**: Minimum gap between nudges (default: 10 min)
/// - **Hourly limit**: Max nudges per hour (default: 2)
/// - **Suppression**: No nudges during stretching, low tracking, or after acknowledgement
///
/// ## How Time Works in These Tests
///
/// The NudgeEngine accepts an explicit `currentTime` parameter instead of
/// calling `Date()` internally. This means we can "fast-forward" time by
/// just passing a larger number. For example:
///
/// ```swift
/// // Simulate 5 minutes passing:
/// engine.evaluate(..., currentTime: 300)
/// ```
///
/// All timestamps are in seconds. The PostureState `.bad(since: X)` tells
/// the engine when bad posture started, and `currentTime` tells it "now".
/// The difference is the slouch duration.
final class NudgeEngineTests: XCTestCase {

    // MARK: - Test Helpers

    /// Creates a NudgeEngine with shorter thresholds for faster testing.
    ///
    /// Default test thresholds:
    /// - `slouchDurationBeforeNudge`: 10s (instead of 300s / 5 min)
    /// - `nudgeCooldown`: 20s (instead of 600s / 10 min)
    /// - `maxNudgesPerHour`: 2
    /// - `acknowledgementWindow`: 5s (instead of 30s)
    private func makeEngine(
        slouchDuration: TimeInterval = 10,
        cooldown: TimeInterval = 20,
        maxPerHour: Int = 2,
        ackWindow: TimeInterval = 5
    ) -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = slouchDuration
        thresholds.nudgeCooldown = cooldown
        thresholds.maxNudgesPerHour = maxPerHour
        thresholds.acknowledgementWindow = ackWindow
        return NudgeEngine(thresholds: thresholds)
    }

    /// Helper to call evaluate with common defaults.
    ///
    /// Most tests only care about the PostureState and currentTime.
    /// This helper fills in sensible defaults for the other parameters
    /// so tests can focus on what they're actually testing.
    ///
    /// - Parameters:
    ///   - engine: The NudgeEngine to evaluate.
    ///   - state: The current posture state.
    ///   - currentTime: The current timestamp in seconds.
    ///   - trackingQuality: Camera tracking quality (default: .good).
    ///   - movementLevel: User movement level (default: 0.1 = mostly still).
    ///   - taskMode: Current activity (default: .unknown).
    /// - Returns: The NudgeDecision.
    @discardableResult
    private func evaluate(
        _ engine: NudgeEngine,
        state: PostureState,
        currentTime: TimeInterval,
        trackingQuality: TrackingQuality = .good,
        movementLevel: Float = 0.1,
        taskMode: TaskMode = .unknown,
        metrics: RawMetrics? = nil
    ) -> NudgeDecision {
        engine.evaluate(
            state: state,
            trackingQuality: trackingQuality,
            movementLevel: movementLevel,
            taskMode: taskMode,
            currentTime: currentTime,
            metrics: metrics
        )
    }

    /// Helper to create RawMetrics with specific values for testing nudge reasons.
    private func makeMetrics(
        forwardCreep: Float = 0,
        headDrop: Float = 0,
        shoulderRounding: Float = 0,
        lateralLean: Float = 0,
        twist: Float = 0
    ) -> RawMetrics {
        RawMetrics(
            timestamp: 0,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: 0.1,
            headMovementPattern: .still
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 1: Basic Fire After Sustained Slouch
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The most basic scenario: posture has been bad long enough
    // that the engine should fire a nudge.

    func test_firesNudge_afterSufficientSlouchDuration() {
        // Create engine with 10-second slouch threshold
        let engine = makeEngine(slouchDuration: 10)

        // Posture has been bad since t=0, and it's now t=15.
        // That's 15 seconds of bad posture, which exceeds the 10s threshold.
        let decision = evaluate(engine, state: .bad(since: 0), currentTime: 15)

        // The engine should tell us to fire a nudge
        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .sustainedSlouch,
                "Nudge reason should be sustainedSlouch when bad posture exceeds duration threshold")
        } else {
            XCTFail("Expected .fire decision after 15s of bad posture (threshold: 10s), got: \(decision)")
        }
    }

    func test_firesNudge_atExactThreshold() {
        let engine = makeEngine(slouchDuration: 10)

        // Exactly at the threshold boundary
        let decision = evaluate(engine, state: .bad(since: 0), currentTime: 10)

        if case .fire = decision {
            // Expected — >= threshold should fire
        } else {
            XCTFail("Expected .fire at exactly the slouch threshold, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 2: Pending Before Threshold
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // When posture is bad but hasn't been bad long enough,
    // the engine returns .pending with a countdown.

    func test_returnsPending_beforeSlouchThreshold() {
        let engine = makeEngine(slouchDuration: 10)

        // Only 5 seconds of bad posture (need 10s)
        let decision = evaluate(engine, state: .bad(since: 0), currentTime: 5)

        if case .pending(let reason, let remaining) = decision {
            XCTAssertEqual(reason, .sustainedSlouch)
            XCTAssertEqual(remaining, 5.0, accuracy: 0.01,
                "Should have 5 seconds remaining (10s threshold - 5s elapsed)")
        } else {
            XCTFail("Expected .pending before threshold, got: \(decision)")
        }
    }

    func test_pendingCountdown_decreasesOverTime() {
        let engine = makeEngine(slouchDuration: 10)

        // At t=2: 8 seconds remaining
        let decision1 = evaluate(engine, state: .bad(since: 0), currentTime: 2)
        if case .pending(_, let remaining1) = decision1 {
            XCTAssertEqual(remaining1, 8.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .pending at t=2")
        }

        // At t=7: 3 seconds remaining
        let decision2 = evaluate(engine, state: .bad(since: 0), currentTime: 7)
        if case .pending(_, let remaining2) = decision2 {
            XCTAssertEqual(remaining2, 3.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .pending at t=7")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 3: Returns None for Non-Bad States
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Nudges only fire for .bad state. All other posture states
    // should return .none — nothing to do.

    func test_returnsNone_whenPostureIsGood() {
        let engine = makeEngine()

        let decision = evaluate(engine, state: .good, currentTime: 100)

        if case .none = decision {
            // Expected — good posture, no nudge needed
        } else {
            XCTFail("Should return .none for .good posture, got: \(decision)")
        }
    }

    func test_returnsNone_whenPostureIsDrifting() {
        let engine = makeEngine()

        // Drifting is a "yellow light" — not bad enough for a nudge yet.
        // The PostureEngine will eventually transition to .bad if drifting persists.
        let decision = evaluate(engine, state: .drifting(since: 0), currentTime: 100)

        if case .none = decision {
            // Expected
        } else {
            XCTFail("Should return .none for .drifting posture, got: \(decision)")
        }
    }

    func test_returnsNone_whenPostureIsAbsent() {
        let engine = makeEngine()

        let decision = evaluate(engine, state: .absent, currentTime: 100)

        if case .none = decision {
            // Expected — user isn't even in frame
        } else {
            XCTFail("Should return .none for .absent, got: \(decision)")
        }
    }

    func test_returnsNone_whenPostureIsCalibrating() {
        let engine = makeEngine()

        let decision = evaluate(engine, state: .calibrating, currentTime: 100)

        if case .none = decision {
            // Expected — still setting up
        } else {
            XCTFail("Should return .none for .calibrating, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 4: Cooldown Suppression
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // After a nudge fires, there's a cooldown period during which
    // no new nudges will fire, even if posture is still bad.

    func test_suppressesDuringCooldown() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20)

        // First nudge fires at t=15 (bad since t=0, duration=15 > threshold=10)
        let decision1 = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        if case .fire = decision1 {
            engine.recordNudgeFired(at: 15)
        } else {
            XCTFail("First nudge should fire")
        }

        // At t=25: cooldown is still active (15 + 20 = 35 is when it expires).
        // Even though we have a new bad episode since t=20, cooldown blocks it.
        let decision2 = evaluate(engine, state: .bad(since: 20), currentTime: 35)

        if case .suppressed(let reason) = decision2 {
            XCTAssertEqual(reason, .cooldownActive,
                "Should be suppressed due to cooldown")
        } else {
            XCTFail("Expected .suppressed(.cooldownActive) during cooldown, got: \(decision2)")
        }
    }

    func test_firesAgain_afterCooldownExpires() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20)

        // First nudge at t=15
        let decision1 = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        if case .fire = decision1 {
            engine.recordNudgeFired(at: 15)
        }

        // At t=46: cooldown has expired (15 + 20 = 35), and new slouch
        // started at t=25, so duration = 46 - 25 = 21s > 10s threshold.
        let decision2 = evaluate(engine, state: .bad(since: 25), currentTime: 46)

        if case .fire = decision2 {
            // Expected — cooldown expired, duration met
        } else {
            XCTFail("Should fire after cooldown expires, got: \(decision2)")
        }
    }

    func test_cooldownRemaining_countsDown() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20)

        // Fire at t=10
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)

        // Check debug state at t=20 — should show 15s remaining (35 - 20)
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 20)
        let debugState = engine.debugState
        let remaining = debugState["cooldownRemaining"] as? TimeInterval ?? -1
        XCTAssertEqual(remaining, 15.0, accuracy: 0.01,
            "Cooldown remaining should be 15s at t=20 (fired at t=15, cooldown=20)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 5: Hourly Limit
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The engine caps total nudges per hour (default: 2).
    // Once the limit is reached, no more nudges until old ones
    // fall outside the 1-hour rolling window.

    func test_suppressesAfterMaxNudgesPerHour() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 5, maxPerHour: 2)

        // Fire nudge 1 at t=15
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)

        // Fire nudge 2 at t=35 (cooldown expired at t=20, new slouch from t=22)
        _ = evaluate(engine, state: .bad(since: 22), currentTime: 35)
        engine.recordNudgeFired(at: 35)

        // Try nudge 3 at t=55 (cooldown expired at t=40, new slouch from t=42)
        // Should be suppressed — already at 2/2 for the hour.
        let decision = evaluate(engine, state: .bad(since: 42), currentTime: 55)

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .maxNudgesReached,
                "Should be suppressed after reaching hourly limit")
        } else {
            XCTFail("Expected .suppressed(.maxNudgesReached), got: \(decision)")
        }
    }

    func test_hourlyLimitResetsAfterOneHour() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 5, maxPerHour: 2)

        // Fire 2 nudges within the hour
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)

        _ = evaluate(engine, state: .bad(since: 22), currentTime: 35)
        engine.recordNudgeFired(at: 35)

        // At t=3616: first nudge (t=15) is older than 1 hour (3600s).
        // The rolling window prunes it, so only 1 nudge counts.
        // New slouch from t=3600, duration = 3616 - 3600 = 16s > 10s.
        let decision = evaluate(engine, state: .bad(since: 3600), currentTime: 3616)

        if case .fire = decision {
            // Expected — hourly limit refreshed, first nudge pruned
        } else {
            XCTFail("Should fire after old nudges fall outside the hour window, got: \(decision)")
        }
    }

    func test_nudgesThisHour_tracksCorrectly() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 5, maxPerHour: 3)

        // Fire 2 nudges
        engine.recordNudgeFired(at: 100)
        engine.recordNudgeFired(at: 200)

        let debugState = engine.debugState
        let count = debugState["nudgesThisHour"] as? Int ?? -1
        XCTAssertEqual(count, 2, "Should track 2 nudges this hour")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 6: Tracking Quality Suppression
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // When the camera can't see the user clearly, suppress nudges.
    // This mirrors the PostureEngine's safety rule.

    func test_suppressesWhenTrackingIsLost() {
        let engine = makeEngine(slouchDuration: 10)

        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            trackingQuality: .lost
        )

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .lowTrackingQuality)
        } else {
            XCTFail("Expected .suppressed(.lowTrackingQuality), got: \(decision)")
        }
    }

    func test_suppressesWhenTrackingIsDegraded() {
        let engine = makeEngine(slouchDuration: 10)

        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            trackingQuality: .degraded
        )

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .lowTrackingQuality)
        } else {
            XCTFail("Expected .suppressed(.lowTrackingQuality), got: \(decision)")
        }
    }

    func test_firesWhenTrackingIsGood() {
        let engine = makeEngine(slouchDuration: 10)

        // With .good tracking and sufficient duration, should fire
        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            trackingQuality: .good
        )

        if case .fire = decision {
            // Expected
        } else {
            XCTFail("Should fire with .good tracking quality, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 7: Task Mode Suppression
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Stretching mode suppresses nudges because the user is
    // intentionally moving around — that's good behavior!

    func test_suppressesDuringStretching() {
        let engine = makeEngine(slouchDuration: 10)

        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            taskMode: .stretching
        )

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .userStretching)
        } else {
            XCTFail("Expected .suppressed(.userStretching), got: \(decision)")
        }
    }

    func test_doesNotSuppressDuringReading() {
        let engine = makeEngine(slouchDuration: 10)

        // Reading mode should NOT suppress nudges
        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            taskMode: .reading
        )

        if case .fire = decision {
            // Expected — reading doesn't suppress nudges
        } else {
            XCTFail("Reading mode should not suppress nudges, got: \(decision)")
        }
    }

    func test_doesNotSuppressDuringTyping() {
        let engine = makeEngine(slouchDuration: 10)

        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            taskMode: .typing
        )

        if case .fire = decision {
            // Expected
        } else {
            XCTFail("Typing mode should not suppress nudges, got: \(decision)")
        }
    }

    func test_doesNotSuppressDuringMeeting() {
        let engine = makeEngine(slouchDuration: 10)

        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            taskMode: .meeting
        )

        if case .fire = decision {
            // Expected
        } else {
            XCTFail("Meeting mode should not suppress nudges, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 8: Acknowledgement Suppression
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // After the user corrects their posture (acknowledges the nudge),
    // we don't re-nudge for the same episode.

    func test_suppressesAfterAcknowledgement() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 5)

        // Fire a nudge
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)

        // User corrects posture — acknowledged!
        engine.recordAcknowledgement()

        // User slumps again after cooldown expires.
        // Even though duration threshold is met and cooldown expired,
        // the acknowledgement flag should suppress it.
        let decision = evaluate(engine, state: .bad(since: 22), currentTime: 40)

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .recentAcknowledgement,
                "Should suppress after user acknowledged the previous nudge")
        } else {
            XCTFail("Expected .suppressed(.recentAcknowledgement), got: \(decision)")
        }
    }

    func test_acknowledgementClearsOnNewNudge() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 5, maxPerHour: 5)

        // Fire nudge 1
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)

        // Acknowledge
        engine.recordAcknowledgement()

        // Record a new nudge (simulating the caller deciding to nudge anyway
        // after clearing the ack flag, or a fresh episode)
        engine.recordNudgeFired(at: 50)

        // The new recordNudgeFired should have cleared the acknowledgement flag.
        // So after cooldown (50 + 5 = 55), new slouch should be able to fire.
        let decision = evaluate(engine, state: .bad(since: 58), currentTime: 72)

        if case .fire = decision {
            // Expected — acknowledgement was cleared by the new nudge
        } else {
            XCTFail("Acknowledgement should be cleared by recordNudgeFired, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 9: Reset
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Reset clears all internal state — cooldown, counters, ack flag.

    func test_resetClearsAllState() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20, maxPerHour: 1)

        // Fire a nudge and acknowledge it
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)
        engine.recordAcknowledgement()

        // At this point: cooldown active, 1/1 nudges used, acknowledged

        // Reset everything
        engine.reset()

        // After reset, should be able to fire again immediately
        // (no cooldown, no hourly limit, no acknowledgement)
        let decision = evaluate(engine, state: .bad(since: 20), currentTime: 35)

        if case .fire = decision {
            // Expected — clean slate after reset
        } else {
            XCTFail("Should fire after reset clears all state, got: \(decision)")
        }
    }

    func test_resetClearsDebugState() {
        let engine = makeEngine()

        engine.recordNudgeFired(at: 100)

        engine.reset()

        let debugState = engine.debugState
        XCTAssertEqual(debugState["nudgesThisHour"] as? Int, 0,
            "Nudge count should be 0 after reset")
        XCTAssertEqual(debugState["cooldownRemaining"] as? TimeInterval, 0,
            "Cooldown should be 0 after reset")
        XCTAssertEqual(debugState["acknowledged"] as? Bool, false,
            "Acknowledgement should be false after reset")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 10: Debug State
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // The debug overlay needs access to internal state.

    func test_debugState_exposesExpectedKeys() {
        let engine = makeEngine()

        let debugState = engine.debugState

        XCTAssertNotNil(debugState["nudgesThisHour"],
            "Debug state should include nudgesThisHour")
        XCTAssertNotNil(debugState["lastNudgeTime"],
            "Debug state should include lastNudgeTime")
        XCTAssertNotNil(debugState["cooldownRemaining"],
            "Debug state should include cooldownRemaining")
        XCTAssertNotNil(debugState["acknowledged"],
            "Debug state should include acknowledged flag")
        XCTAssertNotNil(debugState["lastDecision"],
            "Debug state should include lastDecision description")
    }

    func test_debugState_updatesAfterNudge() {
        let engine = makeEngine()

        engine.recordNudgeFired(at: 100)

        let debugState = engine.debugState
        let lastTime = debugState["lastNudgeTime"] as? TimeInterval ?? -1
        XCTAssertEqual(lastTime, 100.0, accuracy: 0.01,
            "lastNudgeTime should update to 100 after recording a nudge")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 11: Suppression Priority Order
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // When multiple suppression conditions are active simultaneously,
    // the engine checks them in a specific order. These tests verify
    // that the highest-priority suppression wins.

    func test_lowTrackingTakesPriorityOverStretching() {
        let engine = makeEngine(slouchDuration: 10)

        // Both low tracking AND stretching
        let decision = evaluate(
            engine,
            state: .bad(since: 0),
            currentTime: 15,
            trackingQuality: .lost,
            taskMode: .stretching
        )

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .lowTrackingQuality,
                "Low tracking should take priority over stretching")
        } else {
            XCTFail("Expected suppression, got: \(decision)")
        }
    }

    func test_stretchingTakesPriorityOverCooldown() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20)

        // Fire a nudge first to create cooldown
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        engine.recordNudgeFired(at: 15)

        // Now stretching AND cooldown are both active
        let decision = evaluate(
            engine,
            state: .bad(since: 18),
            currentTime: 20,
            taskMode: .stretching
        )

        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .userStretching,
                "Stretching should take priority over cooldown")
        } else {
            XCTFail("Expected suppression, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 12: Full Session Flow (End-to-End)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Simulates a realistic session:
    // 1. Good posture → no nudge
    // 2. Slouch → pending → fire
    // 3. Cooldown → suppressed
    // 4. User corrects → acknowledged
    // 5. User slouches again → suppressed (ack)
    // 6. Reset → fire again

    func test_fullSessionFlow() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20, maxPerHour: 2)

        // ── Phase 1: Good posture ──
        var decision = evaluate(engine, state: .good, currentTime: 0)
        if case .none = decision { /* Expected */ }
        else { XCTFail("Phase 1: Good posture should be .none, got: \(decision)") }

        // ── Phase 2a: Bad posture starts, not long enough yet ──
        decision = evaluate(engine, state: .bad(since: 5), currentTime: 10)
        if case .pending(_, let remaining) = decision {
            XCTAssertEqual(remaining, 5.0, accuracy: 0.1,
                "Phase 2a: Should have 5s remaining")
        } else {
            XCTFail("Phase 2a: Should be .pending, got: \(decision)")
        }

        // ── Phase 2b: Bad posture long enough → FIRE! ──
        decision = evaluate(engine, state: .bad(since: 5), currentTime: 16)
        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .sustainedSlouch, "Phase 2b: Should fire for sustained slouch")
            engine.recordNudgeFired(at: 16)
        } else {
            XCTFail("Phase 2b: Should fire, got: \(decision)")
        }

        // ── Phase 3: Cooldown active ──
        decision = evaluate(engine, state: .bad(since: 20), currentTime: 32)
        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .cooldownActive, "Phase 3: Should be in cooldown")
        } else {
            XCTFail("Phase 3: Should be suppressed (cooldown), got: \(decision)")
        }

        // ── Phase 4: User corrects posture ──
        engine.recordAcknowledgement()

        // ── Phase 5: User slouches again after cooldown, but acknowledged ──
        decision = evaluate(engine, state: .bad(since: 40), currentTime: 55)
        if case .suppressed(let reason) = decision {
            XCTAssertEqual(reason, .recentAcknowledgement,
                "Phase 5: Should be suppressed after acknowledgement")
        } else {
            XCTFail("Phase 5: Should be suppressed (ack), got: \(decision)")
        }

        // ── Phase 6: After reset, fire again ──
        engine.reset()
        decision = evaluate(engine, state: .bad(since: 60), currentTime: 75)
        if case .fire = decision {
            // Expected — fresh start after reset
        } else {
            XCTFail("Phase 6: Should fire after reset, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 12.5: Specific Nudge Reasons (Ticket 4.6)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // When metrics are provided, the nudge reason should reflect
    // the dominant posture violation rather than always being
    // .sustainedSlouch. The dominant metric is the one with the
    // highest value/threshold ratio.

    func test_fireReason_isForwardCreep_whenForwardCreepDominates() {
        let engine = makeEngine(slouchDuration: 10)

        // forwardCreep = 0.15 / 0.10 threshold = 1.5 ratio
        // headDrop = 0.03 / 0.06 threshold = 0.5 ratio
        // → forwardCreep dominates
        let metrics = makeMetrics(forwardCreep: 0.15, headDrop: 0.03)

        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 15, metrics: metrics
        )

        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .forwardCreep,
                "Nudge reason should be .forwardCreep when forward creep ratio is highest")
        } else {
            XCTFail("Expected .fire, got: \(decision)")
        }
    }

    func test_fireReason_isHeadDrop_whenHeadDropDominates() {
        let engine = makeEngine(slouchDuration: 10)

        // forwardCreep = 0.05 / 0.10 threshold = 0.5 ratio
        // headDrop = 0.12 / 0.06 threshold = 2.0 ratio
        // → headDrop dominates
        let metrics = makeMetrics(forwardCreep: 0.05, headDrop: 0.12)

        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 15, metrics: metrics
        )

        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .headDrop,
                "Nudge reason should be .headDrop when head drop ratio is highest")
        } else {
            XCTFail("Expected .fire, got: \(decision)")
        }
    }

    func test_fireReason_isSustainedSlouch_whenNoMetricsProvided() {
        let engine = makeEngine(slouchDuration: 10)

        // No metrics → falls back to .sustainedSlouch
        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 15, metrics: nil
        )

        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .sustainedSlouch,
                "Nudge reason should default to .sustainedSlouch when no metrics provided")
        } else {
            XCTFail("Expected .fire, got: \(decision)")
        }
    }

    func test_fireReason_isSustainedSlouch_whenNeitherMetricExceedsThreshold() {
        let engine = makeEngine(slouchDuration: 10)

        // Both metrics below threshold
        // forwardCreep = 0.015 / 0.03 = 0.5 ratio (below 1.0)
        // headDrop = 0.03 / 0.06 = 0.5 ratio (below 1.0)
        // → general sustained slouch (other metrics like twist/lean triggered the bad state)
        let metrics = makeMetrics(forwardCreep: 0.015, headDrop: 0.03, twist: 20.0)

        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 15, metrics: metrics
        )

        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .sustainedSlouch,
                "Nudge reason should be .sustainedSlouch when no single metric dominates")
        } else {
            XCTFail("Expected .fire, got: \(decision)")
        }
    }

    func test_pendingReason_reflectsMetrics() {
        let engine = makeEngine(slouchDuration: 10)

        // Pending (only 5s of bad posture, need 10s) with forward creep dominant
        let metrics = makeMetrics(forwardCreep: 0.20, headDrop: 0.02)

        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 5, metrics: metrics
        )

        if case .pending(let reason, let remaining) = decision {
            XCTAssertEqual(reason, .forwardCreep,
                "Pending reason should reflect the dominant metric")
            XCTAssertEqual(remaining, 5.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .pending, got: \(decision)")
        }
    }

    func test_fireReason_isSustainedSlouch_whenBothMetricsEqualAboveThreshold() {
        let engine = makeEngine(slouchDuration: 10)

        // Both at exactly the same ratio above threshold
        // forwardCreep = 0.06 / 0.03 = 2.0
        // headDrop = 0.12 / 0.06 = 2.0
        // Equal → falls back to .sustainedSlouch
        let metrics = makeMetrics(forwardCreep: 0.06, headDrop: 0.12)

        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 15, metrics: metrics
        )

        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .sustainedSlouch,
                "When both metrics have equal ratios, should fall back to .sustainedSlouch")
        } else {
            XCTFail("Expected .fire, got: \(decision)")
        }
    }

    func test_headDrop_notAffectedByTaskMode() {
        let engine = makeEngine(slouchDuration: 10)

        // headDrop dominant, reading mode — reason should still be headDrop
        let metrics = makeMetrics(forwardCreep: 0.05, headDrop: 0.12)

        let decision = evaluate(
            engine, state: .bad(since: 0), currentTime: 15,
            taskMode: .reading, metrics: metrics
        )

        if case .fire(let reason) = decision {
            XCTAssertEqual(reason, .headDrop,
                "headDrop reason should not be affected by task mode")
        } else {
            XCTFail("Expected .fire, got: \(decision)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 13: Edge Cases
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_handlesZeroSlouchDuration() {
        // If threshold is 0, should fire immediately when .bad
        let engine = makeEngine(slouchDuration: 0)

        let decision = evaluate(engine, state: .bad(since: 100), currentTime: 100)

        if case .fire = decision {
            // Expected — 0 duration threshold means fire immediately
        } else {
            XCTFail("Should fire immediately with 0 slouch duration threshold, got: \(decision)")
        }
    }

    func test_handlesVeryLargeTimestamps() {
        // Ensure no overflow with large timestamps (realistic for
        // Date().timeIntervalSince1970 which is ~1.7 billion)
        let engine = makeEngine(slouchDuration: 10)

        let baseTime: TimeInterval = 1_700_000_000  // ~2024
        let decision = evaluate(engine, state: .bad(since: baseTime), currentTime: baseTime + 15)

        if case .fire = decision {
            // Expected — should handle large numbers fine
        } else {
            XCTFail("Should handle large timestamps without overflow, got: \(decision)")
        }
    }

    func test_multipleRapidEvaluations_dontCauseDuplicateFires() {
        let engine = makeEngine(slouchDuration: 10, cooldown: 20)

        // First call should fire
        let decision1 = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        if case .fire = decision1 {
            engine.recordNudgeFired(at: 15)
        }

        // Immediate second call should be suppressed (cooldown)
        let decision2 = evaluate(engine, state: .bad(since: 0), currentTime: 15)
        if case .suppressed(let reason) = decision2 {
            XCTAssertEqual(reason, .cooldownActive,
                "Second rapid evaluation should be blocked by cooldown")
        } else {
            XCTFail("Expected cooldown suppression for rapid duplicate, got: \(decision2)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 14: Default Thresholds
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // Verify the engine works with the default PostureThresholds
    // (the real production values).

    func test_defaultThresholds_requiresFiveMinutesOfBadPosture() {
        // Use default thresholds (no customization)
        let engine = NudgeEngine()

        // 4 minutes of bad posture — not enough (need 5 min = 300s)
        let decision1 = evaluate(engine, state: .bad(since: 0), currentTime: 240)
        if case .pending = decision1 {
            // Expected — 240s < 300s
        } else {
            XCTFail("Should be .pending at 4 minutes with default thresholds, got: \(decision1)")
        }

        // 5 minutes of bad posture — should fire
        let decision2 = evaluate(engine, state: .bad(since: 0), currentTime: 300)
        if case .fire = decision2 {
            // Expected — 300s >= 300s
        } else {
            XCTFail("Should fire at exactly 5 minutes with default thresholds, got: \(decision2)")
        }
    }

    func test_defaultThresholds_tenMinuteCooldown() {
        let engine = NudgeEngine()

        // Fire at 5 minutes
        _ = evaluate(engine, state: .bad(since: 0), currentTime: 300)
        engine.recordNudgeFired(at: 300)

        // 9 minutes later (t=840) — cooldown still active (300 + 600 = 900)
        let decision1 = evaluate(engine, state: .bad(since: 540), currentTime: 840)
        if case .suppressed(.cooldownActive) = decision1 {
            // Expected
        } else {
            XCTFail("Should still be in cooldown at 9 min after nudge, got: \(decision1)")
        }

        // 10 minutes later (t=900+) — cooldown expired
        let decision2 = evaluate(engine, state: .bad(since: 600), currentTime: 901)
        if case .fire = decision2 {
            // Expected — cooldown expired
        } else {
            XCTFail("Should fire after 10-minute cooldown expires, got: \(decision2)")
        }
    }
}
