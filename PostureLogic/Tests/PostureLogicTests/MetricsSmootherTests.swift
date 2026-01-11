import XCTest
@testable import PostureLogic

/// Tests for MetricsSmoother (Ticket 3.4)
/// Validates exponential moving average smoothing reduces jitter without hiding real changes
final class MetricsSmootherTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func test_firstSample_returnsUnchanged() {
        // Given
        var smoother = MetricsSmoother(alpha: 0.3)
        let metrics = createMetrics(forwardCreep: 0.5, headDrop: 0.3)

        // When
        let smoothed = smoother.smooth(metrics)

        // Then: First sample should pass through unchanged
        XCTAssertEqual(smoothed.forwardCreep, 0.5)
        XCTAssertEqual(smoothed.headDrop, 0.3)
        XCTAssertEqual(smoothed.timestamp, metrics.timestamp)
    }

    func test_secondSample_appliesEMA() {
        // Given
        var smoother = MetricsSmoother(alpha: 0.3)
        let first = createMetrics(forwardCreep: 0.0, headDrop: 0.0)
        let second = createMetrics(forwardCreep: 1.0, headDrop: 1.0, timestamp: 1.0)

        // When
        _ = smoother.smooth(first)
        let smoothed = smoother.smooth(second)

        // Then: Should blend previous (0.0) with current (1.0) using alpha (0.3)
        // Formula: smoothed = prev + alpha * (current - prev)
        //        = 0.0 + 0.3 * (1.0 - 0.0) = 0.3
        XCTAssertEqual(smoothed.forwardCreep, 0.3, accuracy: 0.001)
        XCTAssertEqual(smoothed.headDrop, 0.3, accuracy: 0.001)
    }

    func test_multipleSamples_convergeToTarget() {
        // Given
        var smoother = MetricsSmoother(alpha: 0.3)
        let initial = createMetrics(forwardCreep: 0.0)

        // When: Feed constant value through smoother
        _ = smoother.smooth(initial)
        var smoothed = initial
        for i in 1...10 {
            let sample = createMetrics(forwardCreep: 1.0, timestamp: TimeInterval(i))
            smoothed = smoother.smooth(sample)
        }

        // Then: Should converge toward 1.0 (won't reach exactly, but close)
        // After many iterations, EMA converges: should be > 0.9
        XCTAssertGreaterThan(smoothed.forwardCreep, 0.9)
    }

    func test_allMetricsFieldsAreSmoothed() {
        // Given
        var smoother = MetricsSmoother(alpha: 0.3)
        let first = createMetrics(
            forwardCreep: 0.0,
            headDrop: 0.0,
            shoulderRounding: 0.0,
            lateralLean: 0.0,
            twist: 0.0,
            movementLevel: 0.0
        )
        let second = createMetrics(
            forwardCreep: 1.0,
            headDrop: 2.0,
            shoulderRounding: 3.0,
            lateralLean: 4.0,
            twist: 5.0,
            movementLevel: 0.5,
            timestamp: 1.0
        )

        // When
        _ = smoother.smooth(first)
        let smoothed = smoother.smooth(second)

        // Then: All fields should be smoothed using alpha=0.3
        XCTAssertEqual(smoothed.forwardCreep, 0.3, accuracy: 0.001)
        XCTAssertEqual(smoothed.headDrop, 0.6, accuracy: 0.001)
        XCTAssertEqual(smoothed.shoulderRounding, 0.9, accuracy: 0.001)
        XCTAssertEqual(smoothed.lateralLean, 1.2, accuracy: 0.001)
        XCTAssertEqual(smoothed.twist, 1.5, accuracy: 0.001)
        XCTAssertEqual(smoothed.movementLevel, 0.15, accuracy: 0.001)
    }

    func test_timestampIsNotSmoothed() {
        // Given
        var smoother = MetricsSmoother(alpha: 0.3)
        let first = createMetrics(timestamp: 0.0)
        let second = createMetrics(timestamp: 1.5)

        // When
        _ = smoother.smooth(first)
        let smoothed = smoother.smooth(second)

        // Then: Timestamp should use current value, not smoothed
        XCTAssertEqual(smoothed.timestamp, 1.5)
    }

    func test_movementPatternIsNotSmoothed() {
        // Given
        var smoother = MetricsSmoother(alpha: 0.3)
        let first = createMetrics(pattern: .still)
        let second = createMetrics(pattern: .erratic, timestamp: 1.0)

        // When
        _ = smoother.smooth(first)
        let smoothed = smoother.smooth(second)

        // Then: Pattern should use current value (can't smooth enums)
        XCTAssertEqual(smoothed.headMovementPattern, .erratic)
    }

    // MARK: - Alpha Configuration Tests

    func test_highAlpha_isMoreResponsive() {
        // Given: High alpha (0.9) is more responsive
        var responsiveSmoother = MetricsSmoother(alpha: 0.9)
        let first = createMetrics(forwardCreep: 0.0)
        let second = createMetrics(forwardCreep: 1.0, timestamp: 1.0)

        // When
        _ = responsiveSmoother.smooth(first)
        let smoothed = responsiveSmoother.smooth(second)

        // Then: Should be closer to current value (0.9)
        // smoothed = 0.0 + 0.9 * (1.0 - 0.0) = 0.9
        XCTAssertEqual(smoothed.forwardCreep, 0.9, accuracy: 0.001)
    }

    func test_lowAlpha_isLessResponsive() {
        // Given: Low alpha (0.1) is less responsive
        var smoothSmoother = MetricsSmoother(alpha: 0.1)
        let first = createMetrics(forwardCreep: 0.0)
        let second = createMetrics(forwardCreep: 1.0, timestamp: 1.0)

        // When
        _ = smoothSmoother.smooth(first)
        let smoothed = smoothSmoother.smooth(second)

        // Then: Should be closer to previous value (0.1)
        // smoothed = 0.0 + 0.1 * (1.0 - 0.0) = 0.1
        XCTAssertEqual(smoothed.forwardCreep, 0.1, accuracy: 0.001)
    }

    // MARK: - Acceptance Tests (Ticket 3.4)

    func test_smoothing_reducesJitter() {
        // Given: Noisy input with small oscillations
        var smoother = MetricsSmoother(alpha: 0.3)
        let noisyValues: [Float] = [0.50, 0.52, 0.48, 0.51, 0.49, 0.50, 0.52]
        var smoothedValues: [Float] = []

        // When: Apply smoothing
        for (index, value) in noisyValues.enumerated() {
            let metrics = createMetrics(forwardCreep: value, timestamp: TimeInterval(index))
            let smoothed = smoother.smooth(metrics)
            smoothedValues.append(smoothed.forwardCreep)
        }

        // Then: Smoothed values should have less variance than raw
        let rawVariance = variance(noisyValues)
        let smoothedVariance = variance(smoothedValues)
        XCTAssertLessThan(smoothedVariance, rawVariance,
                         "Smoothed values should have less variance than raw")
    }

    func test_smoothing_doesNotHideRealChanges() {
        // Given: Real posture change (gradual slouch)
        var smoother = MetricsSmoother(alpha: 0.3)
        let realChange: [Float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        var smoothedValues: [Float] = []

        // When: Apply smoothing
        for (index, value) in realChange.enumerated() {
            let metrics = createMetrics(forwardCreep: value, timestamp: TimeInterval(index))
            let smoothed = smoother.smooth(metrics)
            smoothedValues.append(smoothed.forwardCreep)
        }

        // Then: Smoothed trend should still increase monotonically
        for i in 1..<smoothedValues.count {
            XCTAssertGreaterThan(smoothedValues[i], smoothedValues[i-1],
                                "Smoothed values should preserve upward trend")
        }

        // And final value should be reasonably close to target
        XCTAssertGreaterThan(smoothedValues.last!, 0.3,
                            "Should track toward real change")
    }

    func test_smoothing_handlesStepChange() {
        // Given: Sudden posture change
        var smoother = MetricsSmoother(alpha: 0.3)
        let stepChange: [Float] = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]
        var smoothedValues: [Float] = []

        // When: Apply smoothing
        for (index, value) in stepChange.enumerated() {
            let metrics = createMetrics(forwardCreep: value, timestamp: TimeInterval(index))
            let smoothed = smoother.smooth(metrics)
            smoothedValues.append(smoothed.forwardCreep)
        }

        // Then: Should gradually transition (not instant)
        // After step, first smoothed value should be between 0 and 1
        XCTAssertGreaterThan(smoothedValues[3], 0.2,
                            "Should start transitioning")
        XCTAssertLessThan(smoothedValues[3], 0.5,
                         "Should not jump instantly")

        // Eventually converge toward 1.0
        XCTAssertGreaterThan(smoothedValues.last!, 0.7,
                            "Should converge toward new value")
    }

    // MARK: - Reset Tests

    func test_reset_clearsState() {
        // Given: Smoother with history
        var smoother = MetricsSmoother(alpha: 0.3)
        let first = createMetrics(forwardCreep: 0.5)
        _ = smoother.smooth(first)

        // When: Reset
        smoother.reset()

        // Then: Next sample should behave like first sample
        let afterReset = createMetrics(forwardCreep: 1.0)
        let smoothed = smoother.smooth(afterReset)
        XCTAssertEqual(smoothed.forwardCreep, 1.0,
                      "After reset, first sample should pass through unchanged")
    }

    // MARK: - Helper Functions

    private func createMetrics(
        forwardCreep: Float = 0.0,
        headDrop: Float = 0.0,
        shoulderRounding: Float = 0.0,
        lateralLean: Float = 0.0,
        twist: Float = 0.0,
        movementLevel: Float = 0.0,
        pattern: MovementPattern = .still,
        timestamp: TimeInterval = 0.0
    ) -> RawMetrics {
        return RawMetrics(
            timestamp: timestamp,
            forwardCreep: forwardCreep,
            headDrop: headDrop,
            shoulderRounding: shoulderRounding,
            lateralLean: lateralLean,
            twist: twist,
            movementLevel: movementLevel,
            headMovementPattern: pattern
        )
    }

    /// Calculate variance of an array
    private func variance(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Float(values.count)
    }
}
