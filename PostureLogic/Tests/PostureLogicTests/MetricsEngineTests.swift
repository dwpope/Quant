import XCTest
@testable import PostureLogic
import simd

final class MetricsEngineTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func test_returnsZeroMetrics_whenNoBaseline() {
        // Given
        var engine = MetricsEngine()
        let sample = createSample(mode: .depthFusion)

        // When
        let metrics = engine.compute(from: sample, baseline: nil)

        // Then
        XCTAssertEqual(metrics.forwardCreep, 0)
        XCTAssertEqual(metrics.headDrop, 0)
        XCTAssertEqual(metrics.shoulderRounding, 0)
        XCTAssertEqual(metrics.lateralLean, 0)
        XCTAssertEqual(metrics.twist, 0)
    }

    // MARK: - 3D Metrics Tests (Depth Fusion Mode)

    func test_3DMode_detectsForwardCreep() {
        // Given
        var engine = MetricsEngine()
        let baseline = createBaseline(
            shoulderZ: 0.90,
            mode: .depthFusion
        )

        // When: User moves 8cm closer to camera
        let sample = createSample(
            mode: .depthFusion,
            shoulderMidpoint: SIMD3(0, 0, 0.82)  // Closer = smaller Z
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Forward creep should be positive (0.90 - 0.82 = 0.08)
        XCTAssertEqual(metrics.forwardCreep, 0.08, accuracy: 0.01)
    }

    func test_3DMode_detectsHeadDrop() {
        // Given
        var engine = MetricsEngine()
        let baseline = createBaseline(
            headY: 0.15,
            mode: .depthFusion
        )

        // When: Head drops 5cm
        let sample = createSample(
            mode: .depthFusion,
            headPosition: SIMD3(0, 0.10, 0.88)  // Lower Y = head dropped
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Head drop should be positive (0.15 - 0.10 = 0.05)
        XCTAssertEqual(metrics.headDrop, 0.05, accuracy: 0.01)
    }

    func test_3DMode_detectsLateralLean() {
        // Given
        var engine = MetricsEngine()
        let baseline = createBaseline(
            shoulderX: 0.0,
            mode: .depthFusion
        )

        // When: User leans to the right
        let sample = createSample(
            mode: .depthFusion,
            shoulderMidpoint: SIMD3(0.08, 0, 0.90)
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Lateral lean should detect the offset
        XCTAssertEqual(metrics.lateralLean, 0.08, accuracy: 0.01)
    }

    // MARK: - 2D Metrics Tests (Fallback Mode) - Ticket 3.2

    func test_2DMode_usesShoulderWidthNormalization() {
        // Given
        var engine = MetricsEngine()

        // Baseline with shoulder width of 0.3 (normalized units)
        let baseline = create2DBaseline(
            leftShoulder: SIMD3(0.35, 0.5, 0),
            rightShoulder: SIMD3(0.65, 0.5, 0)  // Width = 0.3
        )

        // When: User leans forward (shoulders move down in frame)
        let sample = create2DSample(
            leftShoulder: SIMD3(0.35, 0.55, 0),   // Moved down by 0.05
            rightShoulder: SIMD3(0.65, 0.55, 0)
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Forward creep should be normalized by shoulder width
        // Expected: 0.05 / 0.3 ≈ 0.167
        XCTAssertGreaterThan(metrics.forwardCreep, 0.15)
        XCTAssertLessThan(metrics.forwardCreep, 0.20)
    }

    func test_2DMode_detectsForwardCreepWithoutDepth() {
        // Given
        var engine = MetricsEngine()
        let baseline = create2DBaseline(
            shoulderY: 0.5
        )

        // When: User leans forward (shoulders move down)
        let sample = create2DSample(
            shoulderY: 0.58  // Moved down (higher Y in normalized coords)
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Should detect forward movement
        XCTAssertGreaterThan(metrics.forwardCreep, 0)
    }

    func test_2DMode_detectsHeadDrop() {
        // Given
        var engine = MetricsEngine()
        let baseline = create2DBaseline(
            headY: 0.3
        )

        // When: Head drops
        let sample = create2DSample(
            headY: 0.35
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Should detect head drop
        XCTAssertGreaterThan(metrics.headDrop, 0)
    }

    func test_2DMode_detectsLateralLean() {
        // Given
        var engine = MetricsEngine()
        let baseline = create2DBaseline(
            shoulderX: 0.5
        )

        // When: User leans sideways
        let sample = create2DSample(
            shoulderX: 0.55
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Should detect lateral movement (normalized by shoulder width)
        XCTAssertGreaterThan(metrics.lateralLean, 0)
    }

    func test_2DMode_detectsTwistFromShoulderWidthChange() {
        // Given
        var engine = MetricsEngine()

        // Baseline with normal shoulder width
        let baseline = create2DBaseline(
            leftShoulder: SIMD3(0.35, 0.5, 0),
            rightShoulder: SIMD3(0.65, 0.5, 0)  // Width = 0.3
        )

        // When: User twists (one shoulder forward, reducing apparent width)
        let sample = create2DSample(
            leftShoulder: SIMD3(0.40, 0.5, 0),   // Shoulders closer together
            rightShoulder: SIMD3(0.60, 0.5, 0)   // Width = 0.2
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Should detect twist from width change
        XCTAssertGreaterThan(metrics.twist, 0)
    }

    func test_2DMode_detectsTwistFromAsymmetry() {
        // Given
        var engine = MetricsEngine()

        // Baseline with symmetric shoulders
        let baseline = create2DBaseline(
            leftShoulder: SIMD3(0.35, 0.5, 0),
            rightShoulder: SIMD3(0.65, 0.5, 0)
        )

        // When: Shoulders become asymmetric (one forward)
        let sample = create2DSample(
            leftShoulder: SIMD3(0.40, 0.5, 0),
            rightShoulder: SIMD3(0.65, 0.5, 0)
        )

        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Should detect twist from asymmetry
        XCTAssertGreaterThan(metrics.twist, 0)
    }

    // MARK: - Mode Comparison Tests (Ticket 3.2 Acceptance)

    func test_metricsAreComparable_betweenDepthAnd2DModes() {
        // Given: Same posture change in both modes
        var engine3D = MetricsEngine()
        var engine2D = MetricsEngine()

        // 3D baseline
        let baseline3D = createBaseline(
            shoulderZ: 0.90,
            mode: .depthFusion
        )

        // 2D baseline (same relative positions)
        let baseline2D = create2DBaseline(
            shoulderY: 0.5
        )

        // Simulate leaning forward in 3D (8cm closer)
        let sample3D = createSample(
            mode: .depthFusion,
            shoulderMidpoint: SIMD3(0, 0, 0.82)
        )

        // Simulate leaning forward in 2D (proportional Y change)
        let sample2D = create2DSample(
            shoulderY: 0.55  // Moved down proportionally
        )

        // When
        let metrics3D = engine3D.compute(from: sample3D, baseline: baseline3D)
        let metrics2D = engine2D.compute(from: sample2D, baseline: baseline2D)

        // Then: Both should detect forward creep (values should be comparable in magnitude)
        XCTAssertGreaterThan(metrics3D.forwardCreep, 0)
        XCTAssertGreaterThan(metrics2D.forwardCreep, 0)

        // Both should be in similar ranges (normalized)
        // 3D: 0.08 units, 2D: should be similar when normalized
        XCTAssertLessThan(abs(metrics3D.forwardCreep - metrics2D.forwardCreep), 0.2,
                         "Metrics should be comparable between modes")
    }

    // MARK: - Edge Cases

    func test_handlesZeroShoulderWidth() {
        // Given
        var engine = MetricsEngine()
        let baseline = create2DBaseline(
            leftShoulder: SIMD3(0.5, 0.5, 0),
            rightShoulder: SIMD3(0.5, 0.5, 0)  // Zero width
        )

        let sample = create2DSample()

        // When
        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then: Should return zero metrics without crashing
        XCTAssertEqual(metrics.forwardCreep, 0)
        XCTAssertEqual(metrics.headDrop, 0)
    }

    func test_movementLevel_startsAtZero() {
        // Given
        var engine = MetricsEngine()
        let baseline = createBaseline()
        let sample = createSample()

        // When: First sample (no previous for comparison)
        let metrics = engine.compute(from: sample, baseline: baseline)

        // Then
        XCTAssertEqual(metrics.movementLevel, 0)
        XCTAssertEqual(metrics.headMovementPattern, .still)
    }

    func test_movementLevel_increasesWithMovement() {
        // Given
        var engine = MetricsEngine()
        let baseline = createBaseline()

        // When: Process multiple samples with increasing movement
        let sample1 = createSample(headPosition: SIMD3(0, 0.15, 0.88))
        _ = engine.compute(from: sample1, baseline: baseline)

        let sample2 = createSample(headPosition: SIMD3(0, 0.16, 0.88))
        let metrics2 = engine.compute(from: sample2, baseline: baseline)

        // Then: Movement level should be > 0
        XCTAssertGreaterThan(metrics2.movementLevel, 0)
    }

    // MARK: - Helper Functions

    private func createBaseline(
        shoulderX: Float = 0,
        shoulderY: Float = 0,
        shoulderZ: Float = 0.90,
        headY: Float = 0.15,
        mode: DepthMode = .depthFusion
    ) -> Baseline {
        return Baseline(
            timestamp: Date(),
            shoulderMidpoint: SIMD3(shoulderX, shoulderY, shoulderZ),
            headPosition: SIMD3(0, headY, 0.88),
            torsoAngle: 2.0,
            shoulderWidth: 0.3,
            depthAvailable: mode == .depthFusion
        )
    }

    private func create2DBaseline(
        leftShoulder: SIMD3<Float>? = nil,
        rightShoulder: SIMD3<Float>? = nil,
        shoulderX: Float = 0.5,
        shoulderY: Float = 0.5,
        headY: Float = 0.3
    ) -> Baseline {
        let left = leftShoulder ?? SIMD3(0.35, shoulderY, 0)
        let right = rightShoulder ?? SIMD3(0.65, shoulderY, 0)
        let shoulderWidth = sqrt(pow(right.x - left.x, 2) + pow(right.y - left.y, 2))

        return Baseline(
            timestamp: Date(),
            shoulderMidpoint: SIMD3(shoulderX, shoulderY, 0),
            headPosition: SIMD3(shoulderX, headY, 0),
            torsoAngle: 0,
            shoulderWidth: shoulderWidth,
            depthAvailable: false
        )
    }

    private func createSample(
        mode: DepthMode = .depthFusion,
        headPosition: SIMD3<Float> = SIMD3(0, 0.15, 0.88),
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0.90)
    ) -> PoseSample {
        return PoseSample(
            timestamp: Date().timeIntervalSince1970,
            depthMode: mode,
            headPosition: headPosition,
            shoulderMidpoint: shoulderMidpoint,
            leftShoulder: SIMD3(-0.15, 0, 0.90),
            rightShoulder: SIMD3(0.15, 0, 0.90),
            torsoAngle: 2.0,
            headForwardOffset: 0.02,
            shoulderTwist: 0,
            trackingQuality: .good
        )
    }

    private func create2DSample(
        leftShoulder: SIMD3<Float>? = nil,
        rightShoulder: SIMD3<Float>? = nil,
        shoulderMidpoint: SIMD3<Float>? = nil,
        shoulderX: Float = 0.5,
        shoulderY: Float = 0.5,
        headY: Float = 0.3
    ) -> PoseSample {
        let left = leftShoulder ?? SIMD3(0.35, shoulderY, 0)
        let right = rightShoulder ?? SIMD3(0.65, shoulderY, 0)

        // Compute midpoint from actual shoulder positions if provided, otherwise use defaults
        let mid: SIMD3<Float>
        if let providedMid = shoulderMidpoint {
            mid = providedMid
        } else if leftShoulder != nil || rightShoulder != nil {
            mid = (left + right) / 2.0
        } else {
            mid = SIMD3(shoulderX, shoulderY, 0)
        }

        return PoseSample(
            timestamp: Date().timeIntervalSince1970,
            depthMode: .twoDOnly,
            headPosition: SIMD3(shoulderX, headY, 0),
            shoulderMidpoint: mid,
            leftShoulder: left,
            rightShoulder: right,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            trackingQuality: .good
        )
    }
}
