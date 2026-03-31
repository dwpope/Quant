import XCTest
@testable import PostureLogic

/// Tests for `SipCalibrationCapture` — the engine that records raw sip data
/// and derives personalised `SipThresholds`.
final class SipCalibrationCaptureTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a `PoseObservation` at the given timestamp with the wrist
    /// positioned at the specified normalised offset from the nose.
    ///
    /// Shoulder width = 0.3 units (rightShoulder.x − leftShoulder.x).
    private func makeObservation(
        wristOffset: CGPoint = CGPoint(x: 0.1, y: 0.1),  // close to face
        timestamp: TimeInterval
    ) -> PoseObservation {
        let ls  = Keypoint(joint: .leftShoulder,  position: CGPoint(x: 0.35, y: 0.5), confidence: 0.99)
        let rs  = Keypoint(joint: .rightShoulder, position: CGPoint(x: 0.65, y: 0.5), confidence: 0.99)
        let nose = Keypoint(joint: .nose,         position: CGPoint(x: 0.5,  y: 0.3), confidence: 0.99)
        let lw  = Keypoint(joint: .leftWrist,
                           position: CGPoint(x: nose.position.x + wristOffset.x * 0.3,
                                             y: nose.position.y + wristOffset.y * 0.3),
                           confidence: 0.99)
        return PoseObservation(
            timestamp: timestamp,
            keypoints: [nose, ls, rs, lw],
            confidence: 0.99
        )
    }

    /// Simulates a complete 10-second sip capture recording.
    private func recordOneSip(into capture: SipCalibrationCapture, startTime: TimeInterval) {
        capture.beginCapture(at: startTime)
        // Feed observations for 10+ seconds to trigger auto-end
        for i in 0...105 {
            let t = startTime + Double(i) * 0.1
            capture.process(makeObservation(timestamp: t))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 1: Zero sips → not ready
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_zeroSips_notReady() {
        let capture = SipCalibrationCapture()

        XCTAssertFalse(capture.isReady, "Capture should not be ready with zero sips")
        XCTAssertNil(capture.derivedThresholds, "Derived thresholds should be nil when not ready")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 2: One sip → ready
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_oneSip_isReady() {
        let capture = SipCalibrationCapture()

        recordOneSip(into: capture, startTime: 0)

        XCTAssertTrue(capture.isReady, "Capture should be ready after 1 sip")
        XCTAssertNotNil(capture.derivedThresholds, "Derived thresholds should be non-nil when ready")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 3: Derived thresholds include margin
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_derivedProximityThreshold_includesMargin() {
        let capture = SipCalibrationCapture()
        for i in 0..<5 {
            recordOneSip(into: capture, startTime: Double(i) * 15)
        }

        guard let thresholds = capture.derivedThresholds else {
            XCTFail("Expected derived thresholds")
            return
        }

        // The proximity threshold should be > 0 (some margin was added)
        XCTAssertGreaterThan(thresholds.proximityThreshold, 0,
                             "Derived proximity threshold should be positive")

        // The threshold should be less than the default 0.35 (was personalised)
        // — sips recorded with wrist very close to face → lower threshold
        XCTAssertLessThanOrEqual(thresholds.proximityThreshold, SipThresholds().proximityThreshold,
                                 "Derived proximity threshold should not exceed the default when wrist was close")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 4: reset() clears all data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_reset_clearsRecordedSips() {
        let capture = SipCalibrationCapture()
        for i in 0..<5 {
            recordOneSip(into: capture, startTime: Double(i) * 15)
        }
        XCTAssertTrue(capture.isReady)

        capture.reset()

        XCTAssertEqual(capture.recordedSipCount, 0)
        XCTAssertFalse(capture.isReady)
        XCTAssertNil(capture.derivedThresholds)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 5: beginCapture / endCapture increments count
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_manualEndCapture_incrementsCount() {
        let capture = SipCalibrationCapture()

        capture.beginCapture(at: 0)
        capture.process(makeObservation(timestamp: 1.0))
        capture.endCapture(at: 5.0)

        XCTAssertEqual(capture.recordedSipCount, 1,
                       "Manual endCapture should increment the recorded sip count")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 6: removeLastSip removes the most recent sip
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_removeLastSip_decrementsCount() {
        let capture = SipCalibrationCapture()
        recordOneSip(into: capture, startTime: 0)
        recordOneSip(into: capture, startTime: 15)
        XCTAssertEqual(capture.recordedSipCount, 2)

        let removed = capture.removeLastSip()

        XCTAssertTrue(removed)
        XCTAssertEqual(capture.recordedSipCount, 1)
        XCTAssertTrue(capture.isReady, "Should still be ready with 1 sip remaining")
    }

    func test_removeLastSip_onEmpty_returnsFalse() {
        let capture = SipCalibrationCapture()

        let removed = capture.removeLastSip()

        XCTAssertFalse(removed)
        XCTAssertEqual(capture.recordedSipCount, 0)
    }

    func test_removeLastSip_removingAll_makesNotReady() {
        let capture = SipCalibrationCapture()
        recordOneSip(into: capture, startTime: 0)
        XCTAssertTrue(capture.isReady)

        capture.removeLastSip()

        XCTAssertFalse(capture.isReady)
        XCTAssertNil(capture.derivedThresholds)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 7: Velocity threshold is positive
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_derivedVelocityThreshold_isPositive() {
        let capture = SipCalibrationCapture()
        for i in 0..<5 {
            recordOneSip(into: capture, startTime: Double(i) * 15)
        }

        guard let thresholds = capture.derivedThresholds else {
            XCTFail("Expected derived thresholds"); return
        }

        XCTAssertGreaterThan(thresholds.velocityThreshold, 0,
                             "Derived velocity threshold should be positive (floored above zero)")
    }
}
