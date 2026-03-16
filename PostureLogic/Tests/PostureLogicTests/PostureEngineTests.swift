import XCTest
@testable import PostureLogic

/// Tests for the PostureEngine state machine (Ticket 3.2).
///
/// The engine tracks posture over time using this state flow:
///
///     absent/calibrating → good ↔ drifting → bad → (recovery) → good
///
/// These tests verify every transition, including the safety rule that
/// timers pause when tracking quality is too low to trust.
final class PostureEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a `RawMetrics` value with sensible defaults.
    /// You can override individual fields to simulate specific posture scenarios.
    ///
    /// - Parameters:
    ///   - timestamp: The time of this metrics reading (seconds).
    ///   - forwardCreep: How far forward the user has leaned vs baseline.
    ///     Positive = leaning forward. Default thresholds.forwardCreepThreshold is 0.03.
    ///   - twist: Shoulder rotation in degrees. Default threshold is 15.0°.
    ///   - lateralLean: Side-to-side offset. Default threshold is 0.08.
    private func makeMetrics(
        timestamp: TimeInterval = 0,
        forwardCreep: Float = 0,
        headDrop: Float = 0,
        shoulderRounding: Float = 0,
        lateralLean: Float = 0,
        twist: Float = 0,
        movementLevel: Float = 0,
        headMovementPattern: MovementPattern = .still
    ) -> RawMetrics {
        RawMetrics(
            timestamp: timestamp,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: movementLevel,
            headMovementPattern: headMovementPattern
        )
    }

    /// Creates "good posture" metrics — all values well within thresholds.
    private func goodMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, forwardCreep: 0.02, lateralLean: 0.01, twist: 3.0)
    }

    /// Creates "bad posture" metrics — forward creep exceeds the default 0.10 threshold.
    private func badMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, forwardCreep: 0.15, lateralLean: 0.02, twist: 5.0)
    }

    /// Creates metrics with excessive twist — exceeds the 15.0° threshold.
    private func twistedMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, forwardCreep: 0.02, lateralLean: 0.01, twist: 20.0)
    }

    /// Creates metrics with excessive side lean — exceeds the 0.08 threshold.
    private func leaningMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, forwardCreep: 0.02, lateralLean: 0.12, twist: 3.0)
    }

    /// Creates metrics with excessive head drop — exceeds the 0.06 threshold.
    private func headDropMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, headDrop: 0.10)
    }

    /// Creates metrics with excessive shoulder rounding — exceeds the 10.0° threshold.
    private func shoulderRoundingMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, shoulderRounding: 15.0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 1: Transitions to Good after calibration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // When the engine starts (state = .absent) and receives its first
    // good-quality metrics, it should move to .good.

    func test_transitionsToGood_afterCalibration() {
        // Create engine — starts in .absent state
        let engine = PostureEngine()

        // Send the first metrics update with good tracking
        let state = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // The engine should now be in the .good state
        // because we came from .absent and the user is being tracked
        XCTAssertEqual(state, .good,
            "After the first update from .absent, state should become .good")
    }

    func test_transitionsToGood_fromCalibrating() {
        // Verify it also works when starting from .calibrating
        // (though .calibrating is typically set externally, the transition
        // logic is the same as .absent)
        let engine = PostureEngine()

        // First update moves from absent → good
        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Reset explicitly to test calibrating scenario
        engine.reset()

        // After reset, engine is .absent. Send good metrics.
        let state = engine.update(
            metrics: goodMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 2: Transitions to Drifting when posture is bad
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // When the user is in .good state and metrics exceed thresholds,
    // the state should transition to .drifting.

    func test_transitionsToDrifting_whenPostureBad() {
        let engine = PostureEngine()

        // Move to .good first
        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Now send bad metrics — forward creep exceeds threshold
        let state = engine.update(
            metrics: badMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Should be drifting now, with "since" = the timestamp of the bad metrics
        if case .drifting(let since) = state {
            XCTAssertEqual(since, 2.0, accuracy: 0.001,
                "Drifting 'since' should match the timestamp when bad posture was first detected")
        } else {
            XCTFail("Expected .drifting state, got: \(state)")
        }
    }

    func test_transitionsToDrifting_whenTwistExceedsThreshold() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        let state = engine.update(
            metrics: twistedMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .drifting = state {
            // Expected
        } else {
            XCTFail("Excessive twist should trigger drifting, got: \(state)")
        }
    }

    func test_transitionsToDrifting_whenLateralLeanExceedsThreshold() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        let state = engine.update(
            metrics: leaningMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .drifting = state {
            // Expected
        } else {
            XCTFail("Excessive side lean should trigger drifting, got: \(state)")
        }
    }

    func test_transitionsToDrifting_whenHeadDropExceedsThreshold() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        let state = engine.update(
            metrics: headDropMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .drifting = state {
            // Expected
        } else {
            XCTFail("Excessive head drop should trigger drifting, got: \(state)")
        }
    }

    func test_transitionsToDrifting_whenShoulderRoundingExceedsThreshold() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        let state = engine.update(
            metrics: shoulderRoundingMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .drifting = state {
            // Expected
        } else {
            XCTFail("Excessive shoulder rounding should trigger drifting, got: \(state)")
        }
    }

    func test_headDrop_notAffectedByTaskMode() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Head drop of 0.10 exceeds the 0.06 threshold.
        // Reading mode should NOT relax head drop (no multiplier applied).
        let state = engine.update(
            metrics: headDropMetrics(timestamp: 2.0),
            taskMode: .reading,
            trackingQuality: .good
        )

        if case .drifting = state {
            // Expected — head drop is bad regardless of task mode
        } else {
            XCTFail("Head drop should trigger drifting even in reading mode, got: \(state)")
        }
    }

    func test_shoulderRounding_relaxedInReadingMode() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Shoulder rounding of 11.0 exceeds the base 10.0° threshold,
        // but reading mode applies forwardCreepMultiplier (1.2×),
        // so the effective threshold is 12.0°. 11.0 < 12.0 → should stay good.
        let metrics = makeMetrics(timestamp: 2.0, shoulderRounding: 11.0)

        let state = engine.update(
            metrics: metrics,
            taskMode: .reading,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good,
            "Reading mode should tolerate slightly more shoulder rounding (11.0 < 12.0)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 3: Transitions to Bad after drifting timeout
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // After being in .drifting for `driftingToBadThreshold` seconds
    // (default: 60s), the state should transition to .bad.

    func test_transitionsToBad_afterDriftingTimeout() {
        // Use shorter thresholds for faster testing
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 10.0  // 10 seconds instead of 60

        let engine = PostureEngine(thresholds: thresholds)

        // Move to .good
        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Start drifting at t=1
        _ = engine.update(
            metrics: badMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Continue bad posture — simulate updates every 2 seconds
        // At t=3, accumulated drift = 2s (not enough)
        var state = engine.update(
            metrics: badMetrics(timestamp: 3.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        if case .drifting = state {
            // Still drifting — good, not enough time has passed
        } else {
            XCTFail("Should still be drifting at t=3, got: \(state)")
        }

        // At t=5, accumulated drift = 4s
        state = engine.update(
            metrics: badMetrics(timestamp: 5.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        if case .drifting = state {
            // Still drifting
        } else {
            XCTFail("Should still be drifting at t=5, got: \(state)")
        }

        // At t=9, accumulated drift = 8s (still not 10s)
        state = engine.update(
            metrics: badMetrics(timestamp: 9.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        if case .drifting = state {
            // Still drifting
        } else {
            XCTFail("Should still be drifting at t=9, got: \(state)")
        }

        // At t=12, accumulated drift = 11s > 10s threshold → should be .bad
        state = engine.update(
            metrics: badMetrics(timestamp: 12.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .bad(let since) = state {
            XCTAssertEqual(since, 1.0, accuracy: 0.001,
                "Bad 'since' should preserve the original drifting start time")
        } else {
            XCTFail("Expected .bad state after drifting timeout, got: \(state)")
        }
    }

    func test_doesNotTransitionToBad_beforeTimeout() {
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 60.0

        let engine = PostureEngine(thresholds: thresholds)

        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Start drifting
        _ = engine.update(
            metrics: badMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Only 30 seconds of drifting — should NOT be .bad
        let state = engine.update(
            metrics: badMetrics(timestamp: 31.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .drifting = state {
            // Still drifting — correct, 30s < 60s threshold
        } else {
            XCTFail("Should still be drifting before timeout, got: \(state)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 4: Recovers to Good when posture improves
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // From .drifting: immediately returns to .good when metrics improve.
    // From .bad: requires `recoveryGracePeriod` seconds of good posture.

    func test_recoversToGood_fromDrifting_immediately() {
        let engine = PostureEngine()

        // Good → drifting
        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        _ = engine.update(
            metrics: badMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Posture improves — should go back to .good immediately
        let state = engine.update(
            metrics: goodMetrics(timestamp: 2.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good,
            "Improving posture while drifting should return to .good immediately")
    }

    func test_recoversToGood_fromBad_afterGracePeriod() {
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 5.0
        thresholds.recoveryGracePeriod = 3.0

        let engine = PostureEngine(thresholds: thresholds)

        // Drive to .bad state: good → drifting → bad
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: badMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: badMetrics(timestamp: 7.0), taskMode: .unknown, trackingQuality: .good)

        // Verify we're in .bad
        let badState = engine.update(
            metrics: badMetrics(timestamp: 8.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertTrue(badState.isBad, "Should be in .bad state")

        // Start recovery — first good frame
        let state1 = engine.update(
            metrics: goodMetrics(timestamp: 10.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertTrue(state1.isBad,
            "Should still be .bad — recovery just started, grace period not met")

        // 1 second of good posture — not enough (need 3s)
        let state2 = engine.update(
            metrics: goodMetrics(timestamp: 11.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertTrue(state2.isBad,
            "Should still be .bad — only 1s of good posture, need 3s")

        // 3+ seconds of good posture — should recover!
        let state3 = engine.update(
            metrics: goodMetrics(timestamp: 13.5),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertEqual(state3, .good,
            "After 3+ seconds of sustained good posture, should recover to .good")
    }

    func test_recoveryResets_ifPostureWorsensAgain() {
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 5.0
        thresholds.recoveryGracePeriod = 3.0

        let engine = PostureEngine(thresholds: thresholds)

        // Drive to .bad
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: badMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: badMetrics(timestamp: 7.0), taskMode: .unknown, trackingQuality: .good)

        // Start recovery
        _ = engine.update(metrics: goodMetrics(timestamp: 10.0), taskMode: .unknown, trackingQuality: .good)

        // Slump back before grace period expires!
        _ = engine.update(metrics: badMetrics(timestamp: 11.0), taskMode: .unknown, trackingQuality: .good)

        // Try recovering again — timer should have reset
        _ = engine.update(metrics: goodMetrics(timestamp: 12.0), taskMode: .unknown, trackingQuality: .good)

        // Only 1s since new recovery attempt — should still be bad
        let state = engine.update(
            metrics: goodMetrics(timestamp: 13.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertTrue(state.isBad,
            "Recovery timer should have reset when posture worsened again")

        // Now sustain good posture for 3+ seconds from the new recovery start (t=12)
        let finalState = engine.update(
            metrics: goodMetrics(timestamp: 15.5),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertEqual(finalState, .good,
            "Should eventually recover after sustained good posture")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Test 5: Pauses timer when tracking quality is low
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // This is the KEY safety feature: when the camera can't see the user
    // clearly, we DON'T count that time as slouching.

    func test_pausesTimer_whenTrackingQualityLow() {
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 10.0

        let engine = PostureEngine(thresholds: thresholds)

        // Good → drifting
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: badMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .good)

        // 3 seconds of good-quality drifting (accumulated = 3s)
        _ = engine.update(metrics: badMetrics(timestamp: 4.0), taskMode: .unknown, trackingQuality: .good)

        // Now tracking quality drops to .degraded for 20 seconds!
        // This time should NOT count toward the drifting timeout.
        _ = engine.update(metrics: badMetrics(timestamp: 10.0), taskMode: .unknown, trackingQuality: .degraded)
        _ = engine.update(metrics: badMetrics(timestamp: 15.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: badMetrics(timestamp: 24.0), taskMode: .unknown, trackingQuality: .degraded)

        // Should still be drifting — bad-quality time doesn't count
        let stateAfterGap = engine.update(
            metrics: badMetrics(timestamp: 25.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        if case .drifting = stateAfterGap {
            // Good — still drifting, accumulated time should be ~3s not 24s
        } else {
            XCTFail("Should still be .drifting after quality gap, got: \(stateAfterGap)")
        }

        // Now add enough good-quality drifting time to cross the threshold
        // We need ~7 more seconds (3 already accumulated + 7 = 10 = threshold)
        _ = engine.update(metrics: badMetrics(timestamp: 27.0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: badMetrics(timestamp: 30.0), taskMode: .unknown, trackingQuality: .good)
        let finalState = engine.update(
            metrics: badMetrics(timestamp: 33.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        if case .bad = finalState {
            // Expected: 3s (before gap) + 8s (after gap) = 11s > 10s threshold
        } else {
            XCTFail("Should transition to .bad after accumulating enough good-quality drift time, got: \(finalState)")
        }
    }

    func test_doesNotChangeState_whenTrackingIsLost() {
        let engine = PostureEngine()

        // Move to .good
        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Send bad metrics but with lost tracking — state should NOT change
        let state = engine.update(
            metrics: badMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .lost
        )

        XCTAssertEqual(state, .good,
            "State should remain .good when tracking quality is .lost")
    }

    func test_doesNotChangeState_whenTrackingIsDegraded() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        let state = engine.update(
            metrics: badMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .degraded
        )

        XCTAssertEqual(state, .good,
            "State should remain .good when tracking quality is .degraded")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Task Mode Adjustments
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_readingMode_isMoreLenientOnForwardCreep() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Forward creep of 0.035 exceeds the default 0.03 threshold,
        // but reading mode has a 1.3x multiplier, so the effective
        // threshold is 0.039.
        let metrics = makeMetrics(
            timestamp: 1.0,
            forwardCreep: 0.035,  // Between 0.03 (default) and 0.039 (reading)
            lateralLean: 0.01,
            twist: 3.0
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .reading,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good,
            "Reading mode should tolerate slightly more forward lean (0.035 < 0.039)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Step 37: Spec-Aligned Threshold Multiplier Tests
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_readingMode_relaxesForwardCreepAndShoulderRounding() {
        let engine = PostureEngine()
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)

        // forwardCreep 0.038 exceeds default 0.03 but is below reading's 0.039 (1.3×)
        // shoulderRounding 11.5 exceeds default 10.0 but is below reading's 12.0 (1.2×)
        let metrics = makeMetrics(
            timestamp: 1.0,
            forwardCreep: 0.038,
            shoulderRounding: 11.5
        )

        let state = engine.update(metrics: metrics, taskMode: .reading, trackingQuality: .good)
        XCTAssertEqual(state, .good,
            "Reading mode: forwardCreep 1.3× (0.038 < 0.039) and shoulderRounding 1.2× (11.5 < 12.0)")

        // Verify the same metrics trigger drifting in unknown mode
        let engine2 = PostureEngine()
        _ = engine2.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)
        let state2 = engine2.update(metrics: metrics, taskMode: .unknown, trackingQuality: .good)
        if case .drifting = state2 {
            // Expected — without reading multipliers, these metrics exceed thresholds
        } else {
            XCTFail("Same metrics should trigger drifting in unknown mode, got: \(state2)")
        }
    }

    func test_typingMode_relaxesTwist() {
        let engine = PostureEngine()
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)

        // twist 17.0 exceeds default 15.0 but is below typing's 18.0 (1.2×)
        let metrics = makeMetrics(timestamp: 1.0, twist: 17.0)

        let state = engine.update(metrics: metrics, taskMode: .typing, trackingQuality: .good)
        XCTAssertEqual(state, .good,
            "Typing mode: twist 1.2× (17.0 < 18.0)")

        // Verify drifts in unknown mode
        let engine2 = PostureEngine()
        _ = engine2.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)
        let state2 = engine2.update(metrics: metrics, taskMode: .unknown, trackingQuality: .good)
        if case .drifting = state2 {
            // Expected
        } else {
            XCTFail("Twist 17.0 should trigger drifting in unknown mode, got: \(state2)")
        }
    }

    func test_meetingMode_relaxesMultipleMetrics() {
        let engine = PostureEngine()
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)

        // All metrics exceed defaults but within meeting multipliers:
        // forwardCreep 0.035 < 0.036 (1.2×), twist 20.0 < 22.5 (1.5×),
        // sideLean 0.09 < 0.096 (1.2×), shoulderRounding 11.0 < 12.0 (1.2×)
        let metrics = makeMetrics(
            timestamp: 1.0,
            forwardCreep: 0.035,
            shoulderRounding: 11.0,
            lateralLean: 0.09,
            twist: 20.0
        )

        let state = engine.update(metrics: metrics, taskMode: .meeting, trackingQuality: .good)
        XCTAssertEqual(state, .good,
            "Meeting mode relaxes forwardCreep(1.2×), twist(1.5×), sideLean(1.2×), shoulderRounding(1.2×)")
    }

    func test_stretchingMode_disablesAllJudgement() {
        let engine = PostureEngine()
        _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)

        // Extreme values across all metrics — stretching should ignore all of them
        let metrics = makeMetrics(
            timestamp: 1.0,
            forwardCreep: 1.0,
            headDrop: 0.5,
            shoulderRounding: 50.0,
            lateralLean: 0.5,
            twist: 45.0
        )

        let state = engine.update(metrics: metrics, taskMode: .stretching, trackingQuality: .good)
        XCTAssertEqual(state, .good,
            "Stretching mode disables all posture judgement — even extreme metrics stay .good")
    }

    func test_headDrop_notAffectedByAnyTaskMode() {
        // headDrop has no multiplier in ANY task mode (always 1.0×)
        let modes: [TaskMode] = [.reading, .typing, .meeting, .unknown]

        for mode in modes {
            let engine = PostureEngine()
            _ = engine.update(metrics: goodMetrics(timestamp: 0), taskMode: .unknown, trackingQuality: .good)

            // headDrop 0.10 exceeds the 0.06 threshold regardless of mode
            let metrics = makeMetrics(timestamp: 1.0, headDrop: 0.10)
            let state = engine.update(metrics: metrics, taskMode: mode, trackingQuality: .good)

            if case .drifting = state {
                // Expected — headDrop is strict in all modes
            } else {
                XCTFail("headDrop should trigger drifting in \(mode) mode, got: \(state)")
            }
        }
    }

    func test_stretchingMode_disablesPostureJudgement() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        // Really bad posture during stretching
        let metrics = makeMetrics(
            timestamp: 1.0,
            forwardCreep: 0.5,
            lateralLean: 0.3,
            twist: 30.0
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .stretching,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good,
            "Stretching mode should never trigger drifting, no matter how 'bad' the metrics")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Reset
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_resetReturnsToAbsent() {
        let engine = PostureEngine()

        _ = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        _ = engine.update(
            metrics: badMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        engine.reset()

        // After reset, the next update should go through absent → good
        let state = engine.update(
            metrics: goodMetrics(timestamp: 10.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good,
            "After reset, engine should transition from .absent to .good on first update")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Debug State
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_debugState_exposesCurrentState() {
        let engine = PostureEngine()
        let debugState = engine.debugState

        XCTAssertNotNil(debugState["state"],
            "Debug state should include the current state for the debug overlay")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Full Flow Integration
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //
    // End-to-end test simulating a real session:
    // 1. Good posture (10s)
    // 2. Gradual slouch (drifts → bad)
    // 3. Recovery

    func test_fullSessionFlow() {
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 5.0
        thresholds.recoveryGracePeriod = 2.0

        let engine = PostureEngine(thresholds: thresholds)

        // Phase 1: User sits down (absent → good)
        var state = engine.update(
            metrics: goodMetrics(timestamp: 0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertEqual(state, .good, "Phase 1: Should start as good")

        // Phase 2: 5 seconds of good posture
        for t in stride(from: 1.0, through: 5.0, by: 1.0) {
            state = engine.update(
                metrics: goodMetrics(timestamp: t),
                taskMode: .unknown,
                trackingQuality: .good
            )
            XCTAssertEqual(state, .good, "Phase 2: Should remain good at t=\(t)")
        }

        // Phase 3: Posture starts to degrade → drifting
        state = engine.update(
            metrics: badMetrics(timestamp: 6.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        if case .drifting = state {
            // Expected
        } else {
            XCTFail("Phase 3: Should be drifting, got: \(state)")
        }

        // Phase 4: Continue bad posture → transitions to bad after 5s
        for t in stride(from: 7.0, through: 11.0, by: 1.0) {
            state = engine.update(
                metrics: badMetrics(timestamp: t),
                taskMode: .unknown,
                trackingQuality: .good
            )
        }
        XCTAssertTrue(state.isBad, "Phase 4: Should be .bad after 5s of drifting")

        // Phase 5: User corrects posture
        state = engine.update(
            metrics: goodMetrics(timestamp: 12.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertTrue(state.isBad, "Phase 5: Still .bad (recovery just started)")

        // Phase 6: Sustained good posture for 2s+ → recovery
        state = engine.update(
            metrics: goodMetrics(timestamp: 13.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertTrue(state.isBad, "Phase 6a: Still .bad (1s of recovery, need 2s)")

        state = engine.update(
            metrics: goodMetrics(timestamp: 14.5),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertEqual(state, .good, "Phase 6b: Should be .good after 2.5s of recovery")
    }
}
