import XCTest
@testable import PostureLogic

/// Tests for TaskModeEngine activity classification.
///
/// The engine infers what the user is doing (reading, typing, meeting, stretching)
/// from a rolling window of movement metrics. Each test fills the window with
/// metrics matching a specific activity signature and verifies the classification.
final class TaskModeEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetrics(
        movementLevel: Float,
        headMovementPattern: MovementPattern,
        count: Int = 20
    ) -> [RawMetrics] {
        (0 ..< count).map { i in
            RawMetrics(
                timestamp: TimeInterval(i) * 0.1,
                forwardCreep: 0,
                headDrop: 0,
                shoulderRounding: 0,
                lateralLean: 0,
                twist: 0,
                movementLevel: movementLevel,
                headMovementPattern: headMovementPattern
            )
        }
    }

    // MARK: - Classification Tests

    func test_classifiesReading_withLowMovementSmallOscillations() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations)
        XCTAssertEqual(engine.infer(from: metrics), .reading)
    }

    func test_classifiesTyping_withModerateMovementLargeMovements() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.35, headMovementPattern: .largeMovements)
        XCTAssertEqual(engine.infer(from: metrics), .typing)
    }

    func test_classifiesStretching_withHighMovement() {
        let engine = TaskModeEngine()
        // Stretching doesn't care about head pattern — any pattern should work
        let metrics = makeMetrics(movementLevel: 0.8, headMovementPattern: .erratic)
        XCTAssertEqual(engine.infer(from: metrics), .stretching)
    }

    func test_classifiesMeeting_withLowMovementStill() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.25, headMovementPattern: .still)
        XCTAssertEqual(engine.infer(from: metrics), .meeting)
    }

    func test_returnsUnknown_withInsufficientSamples() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations, count: 5)
        XCTAssertEqual(engine.infer(from: metrics), .unknown)
    }

    func test_returnsUnknown_whenNoPatternMatches() {
        let engine = TaskModeEngine()
        // movementLevel 0.5–0.7 with .erratic doesn't match any pattern
        let metrics = makeMetrics(movementLevel: 0.6, headMovementPattern: .erratic)
        XCTAssertEqual(engine.infer(from: metrics), .unknown)
    }
}
