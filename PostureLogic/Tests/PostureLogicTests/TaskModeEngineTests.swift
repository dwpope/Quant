import XCTest
@testable import PostureLogic

final class TaskModeEngineTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func test_returnsUnknown_whenInsufficientMetrics() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(count: 5)

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .unknown)
    }

    func test_returnsUnknown_whenMetricsAreAmbiguous() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.35,  // Between reading and meeting
            pattern: .smallOscillations
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .unknown)
    }

    // MARK: - Reading Mode Detection

    func test_detectsReadingMode_withLowMovementAndStill() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.1,  // Low movement
            pattern: .still
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .reading)
    }

    func test_detectsReadingMode_withSmallOscillations() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.15,  // Low movement
            pattern: .smallOscillations
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .reading)
    }

    func test_detectsReadingMode_withMixedStillAndSmallOscillations() {
        // Given
        var engine = TaskModeEngine()
        var metrics: [RawMetrics] = []

        // Create 10 metrics: 5 still, 5 small oscillations
        for i in 0..<10 {
            metrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: 0.15,
                pattern: i % 2 == 0 ? .still : .smallOscillations
            ))
        }

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .reading)
    }

    func test_doesNotDetectReading_withHighMovement() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.5,  // Too high for reading
            pattern: .still
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertNotEqual(mode, .reading)
    }

    func test_doesNotDetectReading_withLargeMovements() {
        // Given
        var engine = TaskModeEngine()
        var metrics: [RawMetrics] = []

        // Create metrics with some large movements
        for i in 0..<10 {
            metrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: 0.15,
                pattern: i < 3 ? .largeMovements : .still
            ))
        }

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertNotEqual(mode, .reading)
    }

    // MARK: - Typing Mode Detection

    func test_detectsTypingMode_withModerateMovementAndLargeMovements() {
        // Given
        var engine = TaskModeEngine()
        var metrics: [RawMetrics] = []

        // Create metrics simulating typing (moderate movement, some large movements)
        for i in 0..<10 {
            metrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: 0.3,
                pattern: i % 3 == 0 ? .largeMovements : .smallOscillations
            ))
        }

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .typing)
    }

    func test_doesNotDetectTyping_withoutLargeMovements() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.3,
            pattern: .still
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertNotEqual(mode, .typing)
    }

    func test_doesNotDetectTyping_withTooMuchMovement() {
        // Given
        var engine = TaskModeEngine()
        var metrics: [RawMetrics] = []

        for i in 0..<10 {
            metrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: 0.6,  // Too high for typing
                pattern: .largeMovements
            ))
        }

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertNotEqual(mode, .typing)
    }

    // MARK: - Meeting Mode Detection

    func test_detectsMeetingMode_withModerateHighMovement() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.5,  // Between typing and stretching
            pattern: .smallOscillations
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .meeting)
    }

    func test_detectsMeetingMode_atLowerBound() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.4,  // Lower bound of meeting range
            pattern: .erratic
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .meeting)
    }

    func test_detectsMeetingMode_atUpperBound() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.7,  // Upper bound of meeting range
            pattern: .largeMovements
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .meeting)
    }

    // MARK: - Stretching Mode Detection

    func test_detectsStretchingMode_withHighMovement() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.8,  // High movement
            pattern: .largeMovements
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .stretching)
    }

    func test_detectsStretchingMode_atThreshold() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.71,  // Just above 0.7 threshold
            pattern: .erratic
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .stretching)
    }

    func test_stretchingMode_hasPriority_overOtherModes() {
        // Given
        var engine = TaskModeEngine()
        // Even with still pattern, high movement should trigger stretching
        let metrics = createMetrics(
            count: 10,
            movementLevel: 0.9,
            pattern: .still
        )

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .stretching)
    }

    // MARK: - Mode Transitions

    func test_transitionsFromReadingToTyping() {
        // Given
        var engine = TaskModeEngine()

        // Start with reading
        let readingMetrics = createMetrics(count: 10, movementLevel: 0.1, pattern: .still)
        let mode1 = engine.infer(from: readingMetrics)
        XCTAssertEqual(mode1, .reading)

        // Transition to typing
        var typingMetrics: [RawMetrics] = []
        for i in 0..<10 {
            typingMetrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: 0.3,
                pattern: i % 3 == 0 ? .largeMovements : .smallOscillations
            ))
        }

        // When
        let mode2 = engine.infer(from: typingMetrics)

        // Then
        XCTAssertEqual(mode2, .typing)
    }

    func test_transitionsToStretching_fromAnyMode() {
        // Given
        var engine = TaskModeEngine()

        // Start with reading
        let readingMetrics = createMetrics(count: 10, movementLevel: 0.1, pattern: .still)
        _ = engine.infer(from: readingMetrics)

        // Transition to stretching
        let stretchingMetrics = createMetrics(count: 10, movementLevel: 0.9, pattern: .erratic)

        // When
        let mode = engine.infer(from: stretchingMetrics)

        // Then
        XCTAssertEqual(mode, .stretching)
    }

    // MARK: - DebugDumpable Tests

    func test_debugState_containsExpectedKeys() {
        // Given
        let engine = TaskModeEngine()

        // When
        let debugState = engine.debugState

        // Then
        XCTAssertNotNil(debugState["lastInferredMode"])
        XCTAssertNotNil(debugState["metricsWindowSize"])
    }

    func test_debugState_updatesAfterInference() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(count: 10, movementLevel: 0.1, pattern: .still)

        // When
        _ = engine.infer(from: metrics)
        let debugState = engine.debugState

        // Then
        let lastMode = debugState["lastInferredMode"] as? String
        XCTAssertEqual(lastMode, "reading")
    }

    // MARK: - Edge Cases

    func test_handlesEmptyMetricsArray() {
        // Given
        var engine = TaskModeEngine()
        let metrics: [RawMetrics] = []

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .unknown)
    }

    func test_handlesExtremeMovementLevels() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(count: 10, movementLevel: 1.0, pattern: .erratic)

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .stretching)
    }

    func test_handlesZeroMovementLevel() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(count: 10, movementLevel: 0.0, pattern: .still)

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .reading)
    }

    func test_handlesAllErraticPatterns() {
        // Given
        var engine = TaskModeEngine()
        let metrics = createMetrics(count: 10, movementLevel: 0.5, pattern: .erratic)

        // When
        let mode = engine.infer(from: metrics)

        // Then
        XCTAssertEqual(mode, .meeting)
    }

    // MARK: - Acceptance Criteria Tests

    func test_distinguishesReadingFromTyping_scenario1() {
        // Given: Reading scenario - low movement, small oscillations
        var engine = TaskModeEngine()
        let readingMetrics = createMetrics(
            count: 10,
            movementLevel: 0.15,
            pattern: .smallOscillations
        )

        // When
        let readingMode = engine.infer(from: readingMetrics)

        // Then
        XCTAssertEqual(readingMode, .reading)

        // Given: Typing scenario - moderate movement with large movements
        var typingMetrics: [RawMetrics] = []
        for i in 0..<10 {
            typingMetrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: 0.35,
                pattern: i % 2 == 0 ? .largeMovements : .smallOscillations
            ))
        }

        // When
        let typingMode = engine.infer(from: typingMetrics)

        // Then
        XCTAssertEqual(typingMode, .typing)
        XCTAssertNotEqual(readingMode, typingMode)
    }

    // MARK: - Helper Functions

    private func createMetrics(
        count: Int,
        movementLevel: Float = 0.0,
        pattern: MovementPattern = .still
    ) -> [RawMetrics] {
        var metrics: [RawMetrics] = []
        for i in 0..<count {
            metrics.append(createSingleMetric(
                timestamp: Double(i),
                movementLevel: movementLevel,
                pattern: pattern
            ))
        }
        return metrics
    }

    private func createSingleMetric(
        timestamp: TimeInterval,
        movementLevel: Float,
        pattern: MovementPattern
    ) -> RawMetrics {
        return RawMetrics(
            timestamp: timestamp,
            forwardCreep: 0.0,
            headDrop: 0.0,
            shoulderRounding: 0.0,
            lateralLean: 0.0,
            twist: 0.0,
            movementLevel: movementLevel,
            headMovementPattern: pattern
        )
    }
}
