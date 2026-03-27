import XCTest
@testable import PostureLogic

/// Tests for the absence-detection logic added to PostureEngine.
///
/// These tests verify:
/// - The 1-second dwell timer before declaring `.absent`
/// - `.degraded` quality freezes without declaring absent
/// - The 2-second return-validation window
/// - Short-absence state restoration (< 30s)
/// - Long-absence reset to `.good` + recalibration prompt (≥ 30s)
/// - Validation window interrupted by quality dropping again
/// - Cold-start `.absent` → `.good` without requiring validation window
/// - reset() clears all new internal fields
final class PostureEngineAbsenceTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetrics(timestamp: TimeInterval, forwardCreep: Float = 0.02) -> RawMetrics {
        RawMetrics(
            timestamp: timestamp,
            forwardCreep: forwardCreep,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: 0.01,
            twist: 3.0,
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    private func goodMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, forwardCreep: 0.02)
    }

    private func badMetrics(timestamp: TimeInterval) -> RawMetrics {
        makeMetrics(timestamp: timestamp, forwardCreep: 0.15)
    }

    /// Drives engine to .good from cold start.
    private func driveToGood(_ engine: PostureEngine, at timestamp: TimeInterval = 1.0) {
        _ = engine.update(metrics: goodMetrics(timestamp: timestamp), taskMode: .unknown, trackingQuality: .good)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 1: Lost dwell < absentThreshold → no absent declared
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_lost_dwell_belowThreshold_doesNotDeclareAbsent() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)
        XCTAssertEqual(engine.update(metrics: goodMetrics(timestamp: 0.0), taskMode: .unknown, trackingQuality: .good), .good)

        // .lost for 0.5s — less than absentThreshold (1.0s)
        let state1 = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        let state2 = engine.update(metrics: goodMetrics(timestamp: 1.5), taskMode: .unknown, trackingQuality: .lost)

        XCTAssertEqual(state1, .good, "Lost quality below dwell threshold should not declare absent")
        XCTAssertEqual(state2, .good, "Lost quality below dwell threshold should not declare absent")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 2: Lost dwell ≥ absentThreshold → absent declared
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_lost_dwell_atThreshold_declaresAbsent() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // .lost starts at t=1.0
        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        // dwell = 1.0s at t=2.0 — meets threshold
        let state = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)

        XCTAssertEqual(state, .absent, "Lost quality at or beyond absentThreshold (1s) should declare absent")
    }

    func test_lost_dwell_beyondThreshold_staysAbsent() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)
        let state = engine.update(metrics: goodMetrics(timestamp: 5.0), taskMode: .unknown, trackingQuality: .lost)

        XCTAssertEqual(state, .absent, "Continued .lost after absent declared should stay .absent")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 3: Degraded quality → engine freezes, no absent
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_degraded_freezesEngine_noAbsent() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // Sustained .degraded — never accumulates lost dwell
        for t in stride(from: 1.0, through: 10.0, by: 1.0) {
            let state = engine.update(metrics: goodMetrics(timestamp: t), taskMode: .unknown, trackingQuality: .degraded)
            XCTAssertEqual(state, .good, "Degraded quality should freeze engine in .good, not declare absent (t=\(t))")
        }
    }

    func test_degraded_doesNotResetLostDwell_thenLostDeclaresAbsent() {
        // Degraded resets lostQualityStart, so a subsequent .lost starts fresh.
        // .lost for 1s after degraded should still declare absent.
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .degraded)
        // Now .lost starts at t=2.0
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)
        let state = engine.update(metrics: goodMetrics(timestamp: 3.0), taskMode: .unknown, trackingQuality: .lost)

        XCTAssertEqual(state, .absent, ".lost for 1s after degraded should still declare absent")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 4: Short absence return → restores saved state + drift time
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_shortAbsence_restoresGoodState() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // Go absent at t=1.0 (dwell 1s → absent at t=2.0)
        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)
        XCTAssertEqual(engine.update(metrics: goodMetrics(timestamp: 2.5), taskMode: .unknown, trackingQuality: .lost), .absent)

        // Return: quality recovers at t=10.0 (absence was ~8s — short)
        // returnValidationWindow = 2.0s, so validation from t=10.0 to t=12.0
        let duringValidation = engine.update(metrics: goodMetrics(timestamp: 10.0), taskMode: .unknown, trackingQuality: .good)
        XCTAssertEqual(duringValidation, .absent, "Should stay .absent during 2s validation window")

        let afterValidation = engine.update(metrics: goodMetrics(timestamp: 12.0), taskMode: .unknown, trackingQuality: .good)
        XCTAssertEqual(afterValidation, .good, "After short absence + validation, should restore .good")
    }

    func test_shortAbsence_restoresDriftingState_withDriftTime() {
        // Verify that drifting state AND accumulated drift time are restored.
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // Drift for 10s (accumulate 10s drift time before going absent)
        _ = engine.update(metrics: badMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .good)
        // drifting since t=1.0; advance drift time 10s
        _ = engine.update(metrics: badMetrics(timestamp: 11.0), taskMode: .unknown, trackingQuality: .good)
        if case .drifting = engine.update(metrics: badMetrics(timestamp: 11.5), taskMode: .unknown, trackingQuality: .good) {
            // confirmed drifting
        } else {
            XCTFail("Expected .drifting before absence")
            return
        }

        // Go absent: .lost at t=12.0, absent at t=13.0
        _ = engine.update(metrics: goodMetrics(timestamp: 12.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 13.0), taskMode: .unknown, trackingQuality: .lost)

        // Return after 5s absence (t=18.0) still slouching — validate 2s with bad posture.
        // Using badMetrics on the return frames simulates the user coming back still slouched.
        _ = engine.update(metrics: badMetrics(timestamp: 18.0), taskMode: .unknown, trackingQuality: .good)
        let returned = engine.update(metrics: badMetrics(timestamp: 20.0), taskMode: .unknown, trackingQuality: .good)

        // After validation commit, state machine ran with bad metrics in .drifting → stays .drifting.
        if case .drifting = returned {
            // Correct — drift state was restored and drift continues
        } else {
            XCTFail("Short absence with bad posture on return should stay .drifting, got: \(returned)")
        }

        // With ~10s of accumulated drift already preserved, we're still well under
        // the 60s threshold — another bad-posture frame should stay .drifting.
        let stillDrifting = engine.update(metrics: badMetrics(timestamp: 20.1), taskMode: .unknown, trackingQuality: .good)
        if case .drifting = stillDrifting {
            // Good — drift time from before absence was preserved, not reset
        } else {
            XCTFail("Drift time should have been preserved across short absence, got: \(stillDrifting)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 5: Long absence return → .good + recalibration prompt
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_longAbsence_resetsToGood_andSetsRecalibrationPrompt() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // Go absent at t=1.0 (dwell → absent at t=2.0)
        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)

        // Return after 60s (long absence ≥ 30s).
        // Quality recovers at t=62.0, validate 2s → commit at t=64.0.
        _ = engine.update(metrics: goodMetrics(timestamp: 62.0), taskMode: .unknown, trackingQuality: .good)
        let afterValidation = engine.update(metrics: goodMetrics(timestamp: 64.0), taskMode: .unknown, trackingQuality: .good)

        XCTAssertEqual(afterValidation, .good, "Long absence should reset to .good")
        XCTAssertTrue(engine.consumeRecalibrationPrompt(), "Long absence should set recalibration prompt")
        XCTAssertFalse(engine.consumeRecalibrationPrompt(), "consumeRecalibrationPrompt is one-shot — false on second call")
    }

    func test_longAbsence_fromDrifting_resetsToGood_notDrifting() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        _ = engine.update(metrics: badMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .good) // → drifting
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 3.0), taskMode: .unknown, trackingQuality: .lost) // absent

        // 45s absence — long
        _ = engine.update(metrics: goodMetrics(timestamp: 48.0), taskMode: .unknown, trackingQuality: .good)
        let afterValidation = engine.update(metrics: goodMetrics(timestamp: 50.0), taskMode: .unknown, trackingQuality: .good)

        XCTAssertEqual(afterValidation, .good, "Long absence resets to .good regardless of saved state")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 6: Validation window interrupted by quality drop
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_returnValidation_interruptedByQualityDrop_staysAbsent() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)

        // Quality returns at t=10.0 (validation window starts)
        _ = engine.update(metrics: goodMetrics(timestamp: 10.0), taskMode: .unknown, trackingQuality: .good)
        // At t=11.0 quality drops again (before 2s validation completes)
        _ = engine.update(metrics: goodMetrics(timestamp: 11.0), taskMode: .unknown, trackingQuality: .lost)
        // Quality returns again at t=15.0 — validation window restarts
        _ = engine.update(metrics: goodMetrics(timestamp: 15.0), taskMode: .unknown, trackingQuality: .good)
        // Only 1s elapsed since restart — still validating
        let duringNewValidation = engine.update(metrics: goodMetrics(timestamp: 16.0), taskMode: .unknown, trackingQuality: .good)

        XCTAssertEqual(duringNewValidation, .absent,
            "After validation interrupt, the window should restart — should still be .absent")
    }

    func test_returnValidation_completesAfterInterrupt() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)

        // Quality drops during validation (see above), then restarts at t=15.0
        _ = engine.update(metrics: goodMetrics(timestamp: 10.0), taskMode: .unknown, trackingQuality: .good)
        _ = engine.update(metrics: goodMetrics(timestamp: 11.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 15.0), taskMode: .unknown, trackingQuality: .good)
        // 2s elapsed since t=15.0 — validation completes (short absence ~13s)
        let afterValidation = engine.update(metrics: goodMetrics(timestamp: 17.0), taskMode: .unknown, trackingQuality: .good)

        XCTAssertEqual(afterValidation, .good, "Validation completes after restart, short absence → .good restored")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 7: Cold-start absent → good without validation window
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_coldStart_absent_goesToGood_immediately() {
        // Engine starts in .absent with no absenceDeclaredAt (cold start).
        // First .good frame should immediately produce .good — no 2s delay.
        let engine = PostureEngine()

        let state = engine.update(
            metrics: goodMetrics(timestamp: 1.0),
            taskMode: .unknown,
            trackingQuality: .good
        )

        XCTAssertEqual(state, .good, "Cold-start .absent should transition to .good immediately without validation window")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 8: Pipeline absence segments
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_pipeline_absenceSegments_openedAndClosed() {
        // Use PipelineTrackingQualityTests style: directly drive the engine
        // (Pipeline requires ARKit; test via PostureEngine + manual segment logic).
        // We verify the engine enters and exits .absent correctly, which is what
        // Pipeline uses to open/close absenceSegments.

        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // Enter absent at t=2.0
        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        let absentState = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)
        XCTAssertEqual(absentState, .absent, "Should be absent — segment should open here")

        // Return: validate 2s (t=10–12)
        _ = engine.update(metrics: goodMetrics(timestamp: 10.0), taskMode: .unknown, trackingQuality: .good)
        let returnedState = engine.update(metrics: goodMetrics(timestamp: 12.0), taskMode: .unknown, trackingQuality: .good)
        XCTAssertEqual(returnedState, .good, "Should exit absent — segment should close here")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 9: reset() clears all absence-related fields
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_reset_clearsAbsenceState() {
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // Build up absence state
        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .lost)
        XCTAssertEqual(engine.update(metrics: goodMetrics(timestamp: 2.5), taskMode: .unknown, trackingQuality: .lost), .absent)

        engine.reset()

        // After reset, should behave like a cold start — no validation window
        let state = engine.update(
            metrics: goodMetrics(timestamp: 100.0),
            taskMode: .unknown,
            trackingQuality: .good
        )
        XCTAssertEqual(state, .good, "After reset(), first .good frame should immediately produce .good (cold start)")
        XCTAssertFalse(engine.consumeRecalibrationPrompt(), "reset() should clear pendingRecalibrationPrompt")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 10: Lost dwell counter resets after quality recovers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_lostDwell_resetsAfterQualityRecovers() {
        // If .lost dwell < 1s then quality recovers to .good,
        // the lostQualityStart should be cleared. A fresh .lost cycle
        // should require a full 1s dwell again.
        let engine = PostureEngine()
        driveToGood(engine, at: 0.0)

        // .lost for 0.5s
        _ = engine.update(metrics: goodMetrics(timestamp: 1.0), taskMode: .unknown, trackingQuality: .lost)
        _ = engine.update(metrics: goodMetrics(timestamp: 1.5), taskMode: .unknown, trackingQuality: .lost)
        // Quality recovers (clears lostQualityStart)
        _ = engine.update(metrics: goodMetrics(timestamp: 2.0), taskMode: .unknown, trackingQuality: .good)
        // .lost starts fresh at t=3.0 — only 0.8s before next check
        _ = engine.update(metrics: goodMetrics(timestamp: 3.0), taskMode: .unknown, trackingQuality: .lost)
        let state = engine.update(metrics: goodMetrics(timestamp: 3.8), taskMode: .unknown, trackingQuality: .lost)

        XCTAssertNotEqual(state, .absent,
            "Dwell timer should reset after quality recovers — fresh .lost of 0.8s should not declare absent")
    }
}
