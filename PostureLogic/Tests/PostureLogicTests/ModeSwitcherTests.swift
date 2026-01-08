import XCTest
@testable import PostureLogic

final class ModeSwitcherTests: XCTestCase {
    var switcher: ModeSwitcher!
    var thresholds: PostureThresholds!

    override func setUp() {
        super.setUp()
        thresholds = PostureThresholds()
        switcher = ModeSwitcher(thresholds: thresholds)
    }

    override func tearDown() {
        switcher = nil
        thresholds = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func test_initialMode_isDepthFusion() {
        XCTAssertEqual(switcher.currentMode, .depthFusion)
    }

    // MARK: - DepthFusion → TwoDOnly Transition Tests

    func test_switchesToTwoDOnly_whenConfidenceDrops() {
        // Given: Starting in DepthFusion mode with high confidence
        let timestamp: TimeInterval = 1.0
        _ = switcher.update(confidence: .high, timestamp: timestamp)
        XCTAssertEqual(switcher.currentMode, .depthFusion)

        // When: Confidence drops below medium
        let mode = switcher.update(confidence: .low, timestamp: timestamp + 0.1)

        // Then: Should switch to TwoDOnly immediately
        XCTAssertEqual(mode, .twoDOnly)
        XCTAssertEqual(switcher.currentMode, .twoDOnly)
    }

    func test_switchesToTwoDOnly_whenConfidenceIsUnavailable() {
        // Given: Starting in DepthFusion mode
        let timestamp: TimeInterval = 1.0

        // When: Confidence is unavailable
        let mode = switcher.update(confidence: .unavailable, timestamp: timestamp)

        // Then: Should switch to TwoDOnly
        XCTAssertEqual(mode, .twoDOnly)
    }

    func test_remainsInDepthFusion_whenConfidenceIsGood() {
        // Given: Starting in DepthFusion mode
        let timestamp: TimeInterval = 1.0

        // When: Confidence is high
        _ = switcher.update(confidence: .high, timestamp: timestamp)

        // Then: Should remain in DepthFusion
        XCTAssertEqual(switcher.currentMode, .depthFusion)

        // When: Confidence is medium (still acceptable)
        let mode = switcher.update(confidence: .medium, timestamp: timestamp + 1.0)

        // Then: Should remain in DepthFusion
        XCTAssertEqual(mode, .depthFusion)
    }

    // MARK: - TwoDOnly → DepthFusion Transition Tests

    func test_switchesToDepthFusion_afterRecoveryDelay() {
        // Given: In TwoDOnly mode
        let startTime: TimeInterval = 1.0
        _ = switcher.update(confidence: .low, timestamp: startTime)
        XCTAssertEqual(switcher.currentMode, .twoDOnly)

        // When: Good confidence returns
        _ = switcher.update(confidence: .high, timestamp: startTime + 1.0)

        // Then: Should still be in TwoDOnly (waiting for recovery delay)
        XCTAssertEqual(switcher.currentMode, .twoDOnly)

        // When: Recovery delay passes (default 2.0 seconds)
        let mode = switcher.update(
            confidence: .high,
            timestamp: startTime + 1.0 + thresholds.depthRecoveryDelay
        )

        // Then: Should switch to DepthFusion
        XCTAssertEqual(mode, .depthFusion)
        XCTAssertEqual(switcher.currentMode, .depthFusion)
    }

    func test_doesNotSwitchToDepthFusion_beforeRecoveryDelay() {
        // Given: In TwoDOnly mode
        let startTime: TimeInterval = 1.0
        _ = switcher.update(confidence: .low, timestamp: startTime)

        // When: Good confidence returns but not for long enough
        _ = switcher.update(confidence: .high, timestamp: startTime + 1.0)
        let mode = switcher.update(
            confidence: .high,
            timestamp: startTime + 1.0 + (thresholds.depthRecoveryDelay - 0.1)
        )

        // Then: Should remain in TwoDOnly
        XCTAssertEqual(mode, .twoDOnly)
    }

    func test_resetsRecoveryTimer_ifConfidenceDropsDuringRecovery() {
        // Given: In TwoDOnly mode with recovery in progress
        let startTime: TimeInterval = 1.0
        _ = switcher.update(confidence: .low, timestamp: startTime)
        _ = switcher.update(confidence: .high, timestamp: startTime + 1.0)

        // When: Confidence drops again during recovery period
        _ = switcher.update(confidence: .low, timestamp: startTime + 2.0)

        // Then: Should remain in TwoDOnly
        XCTAssertEqual(switcher.currentMode, .twoDOnly)

        // When: Confidence returns and full recovery delay passes
        _ = switcher.update(confidence: .high, timestamp: startTime + 3.0)
        let mode = switcher.update(
            confidence: .high,
            timestamp: startTime + 3.0 + thresholds.depthRecoveryDelay
        )

        // Then: Should now switch to DepthFusion
        XCTAssertEqual(mode, .depthFusion)
    }

    func test_requiresSustainedGoodDepth_forRecovery() {
        // Given: In TwoDOnly mode
        let startTime: TimeInterval = 1.0
        _ = switcher.update(confidence: .low, timestamp: startTime)

        // When: Confidence fluctuates
        _ = switcher.update(confidence: .medium, timestamp: startTime + 1.0)
        _ = switcher.update(confidence: .low, timestamp: startTime + 1.5)
        _ = switcher.update(confidence: .medium, timestamp: startTime + 2.0)

        // Then: Should not have switched (timer keeps resetting)
        XCTAssertEqual(switcher.currentMode, .twoDOnly)

        // When: Finally sustained good depth for full delay
        let mode = switcher.update(
            confidence: .high,
            timestamp: startTime + 2.0 + thresholds.depthRecoveryDelay
        )

        // Then: Should switch to DepthFusion
        XCTAssertEqual(mode, .depthFusion)
    }

    // MARK: - Reset Tests

    func test_reset_restoresToDepthFusion() {
        // Given: In TwoDOnly mode
        _ = switcher.update(confidence: .low, timestamp: 1.0)
        XCTAssertEqual(switcher.currentMode, .twoDOnly)

        // When: Reset is called
        switcher.reset()

        // Then: Should be back to DepthFusion
        XCTAssertEqual(switcher.currentMode, .depthFusion)
    }

    func test_reset_clearsRecoveryTimer() {
        // Given: In recovery state
        _ = switcher.update(confidence: .low, timestamp: 1.0)
        _ = switcher.update(confidence: .high, timestamp: 2.0)

        // When: Reset is called
        switcher.reset()

        // Then: Recovery timer should be cleared
        // Switching to TwoDOnly and back should require full delay again
        _ = switcher.update(confidence: .low, timestamp: 3.0)
        _ = switcher.update(confidence: .high, timestamp: 4.0)
        let mode = switcher.update(confidence: .high, timestamp: 4.5)

        XCTAssertEqual(mode, .twoDOnly) // Still in 2D, delay hasn't passed
    }

    // MARK: - Custom Threshold Tests

    func test_respectsCustomRecoveryDelay() {
        // Given: Custom threshold with 5 second recovery delay
        var customThresholds = PostureThresholds()
        customThresholds.depthRecoveryDelay = 5.0
        let customSwitcher = ModeSwitcher(thresholds: customThresholds)

        // Switch to TwoDOnly
        _ = customSwitcher.update(confidence: .low, timestamp: 1.0)

        // Good confidence returns
        _ = customSwitcher.update(confidence: .high, timestamp: 2.0)

        // After 4.9 seconds (just before delay)
        _ = customSwitcher.update(confidence: .high, timestamp: 6.9)
        XCTAssertEqual(customSwitcher.currentMode, .twoDOnly)

        // After 5.0 seconds (at delay threshold)
        let mode = customSwitcher.update(confidence: .high, timestamp: 7.0)
        XCTAssertEqual(mode, .depthFusion)
    }

    // MARK: - Edge Case Tests

    func test_handlesZeroRecoveryDelay() {
        // Given: Zero recovery delay (immediate switch back)
        var customThresholds = PostureThresholds()
        customThresholds.depthRecoveryDelay = 0.0
        let customSwitcher = ModeSwitcher(thresholds: customThresholds)

        // Switch to TwoDOnly
        _ = customSwitcher.update(confidence: .low, timestamp: 1.0)

        // When good confidence returns with zero delay
        let mode = customSwitcher.update(confidence: .high, timestamp: 1.1)

        // Then: Should switch immediately
        XCTAssertEqual(mode, .depthFusion)
    }

    func test_handlesRapidConfidenceChanges() {
        // Simulate rapid flickering depth confidence
        var timestamp: TimeInterval = 1.0

        for i in 0..<100 {
            let confidence: DepthConfidence = i % 2 == 0 ? .low : .high
            _ = switcher.update(confidence: confidence, timestamp: timestamp)
            timestamp += 0.01
        }

        // Should handle without crashing and be in stable state
        XCTAssertNotNil(switcher.currentMode)
    }

    func test_multipleRecoveryCycles() {
        var timestamp: TimeInterval = 1.0

        // First cycle: TwoDOnly → DepthFusion
        _ = switcher.update(confidence: .low, timestamp: timestamp)
        timestamp += 1.0
        _ = switcher.update(confidence: .high, timestamp: timestamp)
        timestamp += thresholds.depthRecoveryDelay
        _ = switcher.update(confidence: .high, timestamp: timestamp)
        XCTAssertEqual(switcher.currentMode, .depthFusion)

        // Second cycle: DepthFusion → TwoDOnly → DepthFusion
        timestamp += 1.0
        _ = switcher.update(confidence: .low, timestamp: timestamp)
        XCTAssertEqual(switcher.currentMode, .twoDOnly)

        timestamp += 1.0
        _ = switcher.update(confidence: .high, timestamp: timestamp)
        timestamp += thresholds.depthRecoveryDelay
        let mode = switcher.update(confidence: .high, timestamp: timestamp)

        XCTAssertEqual(mode, .depthFusion)
    }
}
