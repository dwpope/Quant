import XCTest
@testable import PostureLogic

final class PostureEngineTests: XCTestCase {

    // MARK: - Helper Methods

    private func createEngine() -> PostureEngine {
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 60
        thresholds.forwardCreepThreshold = 0.10
        thresholds.twistThreshold = 15.0
        thresholds.sideLeanThreshold = 0.08
        return PostureEngine(thresholds: thresholds)
    }

    private func createMetrics(
        timestamp: TimeInterval,
        forwardCreep: Float = 0.05,
        twist: Float = 5.0,
        lateralLean: Float = 0.02
    ) -> RawMetrics {
        RawMetrics(
            timestamp: timestamp,
            forwardCreep: forwardCreep,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: 0,
            headMovementPattern: .still
        )
    }

    // MARK: - State Transition Tests

    func test_transitionsToGood_afterCalibration() {
        // Given
        let engine = createEngine()
        let metrics = createMetrics(timestamp: 100)

        // When
        let state = engine.update(
            metrics: metrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state, got \(state)")
        }
    }

    func test_transitionsToDrifting_whenPostureBad() {
        // Given
        let engine = createEngine()

        // First transition to good
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Bad posture detected
        let badMetrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.15  // Exceeds threshold of 0.10
        )

        let state = engine.update(
            metrics: badMetrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then
        if case .drifting(let since) = state {
            XCTAssertEqual(since, 200)
        } else {
            XCTFail("Expected .drifting state, got \(state)")
        }
    }

    func test_transitionsToBad_afterDriftingTimeout() {
        // Given
        let engine = createEngine()

        // First transition to good
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then transition to drifting
        let badMetrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.15
        )
        _ = engine.update(
            metrics: badMetrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Stay in bad posture for >= 60 seconds
        let laterMetrics = createMetrics(
            timestamp: 260,  // 60 seconds later
            forwardCreep: 0.15
        )

        let state = engine.update(
            metrics: laterMetrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then
        if case .bad(let since) = state {
            XCTAssertEqual(since, 200)  // Should keep original drifting timestamp
        } else {
            XCTFail("Expected .bad state, got \(state)")
        }
    }

    func test_recoversToGood_whenPostureImproves() {
        // Given
        let engine = createEngine()

        // Get to drifting state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        _ = engine.update(
            metrics: createMetrics(timestamp: 200, forwardCreep: 0.15),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Posture improves
        let goodMetrics = createMetrics(
            timestamp: 210,
            forwardCreep: 0.05
        )

        let state = engine.update(
            metrics: goodMetrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state, got \(state)")
        }
    }

    func test_pausesTimer_whenTrackingQualityLow() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Tracking quality degrades
        let badMetrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.15  // Bad posture, but tracking quality is degraded
        )

        let state = engine.update(
            metrics: badMetrics,
            taskMode: .typing,
            trackingQuality: .degraded
        )

        // Then: Should stay in good state (timer paused)
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state (paused), got \(state)")
        }
    }

    // MARK: - Task Mode Tests

    func test_usesLenientThreshold_whenReading() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Forward creep of 0.12 while reading
        // (threshold is 0.10 * 1.3 = 0.13 for reading)
        let metrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.12
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .reading,
            trackingQuality: .good
        )

        // Then: Should stay good (0.12 < 0.13)
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state with reading mode, got \(state)")
        }
    }

    func test_usesStrictThreshold_whenTyping() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Forward creep of 0.11 while typing
        // (threshold is 0.10 for typing)
        let metrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.11
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then: Should transition to drifting (0.11 > 0.10)
        if case .drifting = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .drifting state with typing mode, got \(state)")
        }
    }

    func test_usesLenientTwistThreshold_whenTyping() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Twist of 17 degrees while typing
        // (threshold is 15.0 * 1.2 = 18.0 for typing)
        let metrics = createMetrics(
            timestamp: 200,
            twist: 17.0
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then: Should stay good (17.0 < 18.0)
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state with typing mode and moderate twist, got \(state)")
        }
    }

    func test_meetingMode_usesLenientThresholds() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .meeting,
            trackingQuality: .good
        )

        // When: Multiple metrics slightly elevated (meeting mode allows more movement)
        // Forward: 0.11 (threshold is 0.10 * 1.2 = 0.12)
        // Twist: 20 (threshold is 15.0 * 1.5 = 22.5)
        // Lean: 0.09 (threshold is 0.08 * 1.2 = 0.096)
        let metrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.11,
            twist: 20.0,
            lateralLean: 0.09
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .meeting,
            trackingQuality: .good
        )

        // Then: Should stay good (all under adjusted thresholds)
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state with meeting mode, got \(state)")
        }
    }

    func test_stretchingMode_neverJudgesPosture() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Extremely bad posture while stretching
        let badMetrics = createMetrics(
            timestamp: 200,
            forwardCreep: 0.50,  // Way over threshold
            twist: 45.0,         // Way over threshold
            lateralLean: 0.30    // Way over threshold
        )

        let state = engine.update(
            metrics: badMetrics,
            taskMode: .stretching,
            trackingQuality: .good
        )

        // Then: Should stay good (stretching disables judgement)
        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state with stretching mode, got \(state)")
        }
    }

    func test_transitionToBad_notSuppressedByStretching() {
        // Given
        let engine = createEngine()

        // Get to bad state with typing mode
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        _ = engine.update(
            metrics: createMetrics(timestamp: 200, forwardCreep: 0.15),
            taskMode: .typing,
            trackingQuality: .good
        )

        let badState = engine.update(
            metrics: createMetrics(timestamp: 260, forwardCreep: 0.15),
            taskMode: .typing,
            trackingQuality: .good
        )

        // Verify we're in bad state
        if case .bad = badState {
            // Good, we're in bad state
        } else {
            XCTFail("Should be in bad state")
        }

        // When: User starts stretching (still bad posture but stretching)
        let stretchingMetrics = createMetrics(
            timestamp: 270,
            forwardCreep: 0.15  // Still bad posture
        )

        let state = engine.update(
            metrics: stretchingMetrics,
            taskMode: .stretching,
            trackingQuality: .good
        )

        // Then: Should transition to drifting (treated as improvement from bad)
        // This is because stretching makes checkPostureBad return false
        if case .drifting = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .drifting state when switching to stretching from bad, got \(state)")
        }
    }

    // MARK: - Bad Posture Detection Tests

    func test_detectsBadPosture_fromTwist() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Excessive twist
        let metrics = createMetrics(
            timestamp: 200,
            twist: 20.0  // Exceeds threshold of 15.0
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then
        if case .drifting = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .drifting state from twist, got \(state)")
        }
    }

    func test_detectsBadPosture_fromLateralLean() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Excessive lateral lean
        let metrics = createMetrics(
            timestamp: 200,
            lateralLean: 0.10  // Exceeds threshold of 0.08
        )

        let state = engine.update(
            metrics: metrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then
        if case .drifting = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .drifting state from lateral lean, got \(state)")
        }
    }

    // MARK: - Reset Tests

    func test_reset_returnsToAbsent() {
        // Given
        let engine = createEngine()

        // Get to good state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When
        engine.reset()

        // Then: Next update should transition from absent to good
        let state = engine.update(
            metrics: createMetrics(timestamp: 200),
            taskMode: .typing,
            trackingQuality: .good
        )

        if case .good = state {
            XCTAssert(true)
        } else {
            XCTFail("Expected .good state after reset, got \(state)")
        }
    }

    // MARK: - Recovery Tests

    func test_recoversFromBad_throughDrifting() {
        // Given
        let engine = createEngine()

        // Get to bad state
        _ = engine.update(
            metrics: createMetrics(timestamp: 100),
            taskMode: .typing,
            trackingQuality: .good
        )

        _ = engine.update(
            metrics: createMetrics(timestamp: 200, forwardCreep: 0.15),
            taskMode: .typing,
            trackingQuality: .good
        )

        _ = engine.update(
            metrics: createMetrics(timestamp: 260, forwardCreep: 0.15),
            taskMode: .typing,
            trackingQuality: .good
        )

        // When: Posture improves from bad
        let goodMetrics = createMetrics(
            timestamp: 270,
            forwardCreep: 0.05
        )

        let state = engine.update(
            metrics: goodMetrics,
            taskMode: .typing,
            trackingQuality: .good
        )

        // Then: Should go to drifting (grace period)
        if case .drifting(let since) = state {
            XCTAssertEqual(since, 270)
        } else {
            XCTFail("Expected .drifting state during recovery, got \(state)")
        }
    }
}
