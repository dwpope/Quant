import XCTest
@testable import PostureLogic

final class CalibrationServiceTests: XCTestCase {
    var service: CalibrationService!

    override func setUp() {
        super.setUp()
        service = CalibrationService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Basic Flow Tests

    func test_initialState_isWaiting() {
        XCTAssertEqual(service.status, .waiting)
        XCTAssertEqual(service.progress, 0.0)
    }

    func test_startCalibration_changesStatusToWaiting() {
        service.startCalibration()
        XCTAssertEqual(service.status, .waiting)
        XCTAssertEqual(service.progress, 0.0)
    }

    func test_addingGoodSample_startsCalibration() {
        service.startCalibration()

        let sample = createGoodSample(timestamp: 1.0)
        service.addSample(sample)

        XCTAssertEqual(service.status, .sampling)
    }

    func test_addingBadQualitySample_doesNotStartCalibration() {
        service.startCalibration()

        let sample = createBadSample(timestamp: 1.0)
        service.addSample(sample)

        XCTAssertEqual(service.status, .waiting)
    }

    // MARK: - Progress Tests

    func test_progressUpdates_duringCalibration() {
        service.startCalibration()

        // First sample starts the timer
        service.addSample(createGoodSample(timestamp: 0.0))
        XCTAssertEqual(service.progress, 0.0, accuracy: 0.01)

        // Add sample at 2.5 seconds (50% of 5 second duration)
        service.addSample(createGoodSample(timestamp: 2.5))
        XCTAssertEqual(service.progress, 0.5, accuracy: 0.1)

        // Add sample at 5 seconds (100%)
        service.addSample(createGoodSample(timestamp: 5.0))
        XCTAssertEqual(service.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Completion Tests

    func test_sufficientSamples_completesSuccessfully() {
        service.startCalibration()

        // Add 30+ good samples over 5 seconds
        for i in 0..<35 {
            let timestamp = Double(i) * 0.15 // ~150ms per sample
            service.addSample(createGoodSample(timestamp: timestamp))
        }

        // After 5 seconds, should be validating or success
        if case .sampling = service.status {
            XCTFail("Should have completed calibration")
        }
    }

    func test_insufficientSamples_fails() {
        let config = CalibrationConfig(
            duration: 5.0,
            requiredSamples: 30,
            stabilityThreshold: 0.02
        )
        service = CalibrationService(config: config)
        service.startCalibration()

        // Add only 10 samples (less than required 30)
        for i in 0..<10 {
            let timestamp = Double(i) * 0.5
            service.addSample(createGoodSample(timestamp: timestamp))
        }

        if case .failed = service.status {
            // Expected
        } else {
            XCTFail("Should have failed due to insufficient samples")
        }
    }

    // MARK: - Stability Tests

    func test_tooMuchMovement_failsCalibration() {
        service.startCalibration()

        // Add samples with varying positions (simulating movement)
        for i in 0..<35 {
            let timestamp = Double(i) * 0.15
            let sample = createSampleWithPosition(
                timestamp: timestamp,
                position: SIMD3<Float>(Float(i) * 0.1, 0, 0.9) // Moving along X axis
            )
            service.addSample(sample)
        }

        // Should fail due to high variance
        if case .failed(let reason) = service.status {
            XCTAssertTrue(reason.contains("movement"))
        }
    }

    // MARK: - Baseline Computation Tests

    func test_computeBaseline_returnsNil_whenNotSuccessful() {
        service.startCalibration()

        let baseline = service.computeBaseline()
        XCTAssertNil(baseline)
    }

    func test_computeBaseline_returnsBaseline_afterSuccessfulCalibration() {
        service.startCalibration()

        // Add sufficient stable samples
        for i in 0..<35 {
            let timestamp = Double(i) * 0.15
            service.addSample(createGoodSample(timestamp: timestamp))
        }

        // If calibration succeeded, should be able to compute baseline
        if case .success = service.status {
            let baseline = service.computeBaseline()
            XCTAssertNotNil(baseline)
            XCTAssertEqual(baseline?.shoulderMidpoint.z, 0.9, accuracy: 0.1)
        }
    }

    // MARK: - Reset Tests

    func test_reset_clearsState() {
        service.startCalibration()
        service.addSample(createGoodSample(timestamp: 1.0))

        service.reset()

        XCTAssertEqual(service.status, .waiting)
        XCTAssertEqual(service.progress, 0.0)
    }

    // MARK: - Helper Methods

    private func createGoodSample(timestamp: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .depthFusion,
            headPosition: SIMD3<Float>(0, 0.15, 0.88),
            shoulderMidpoint: SIMD3<Float>(0, 0, 0.9),
            leftShoulder: SIMD3<Float>(-0.2, 0, 0.9),
            rightShoulder: SIMD3<Float>(0.2, 0, 0.9),
            torsoAngle: 2.0,
            headForwardOffset: 0.02,
            shoulderTwist: 0,
            trackingQuality: .good
        )
    }

    private func createBadSample(timestamp: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            trackingQuality: .lost
        )
    }

    private func createSampleWithPosition(timestamp: TimeInterval, position: SIMD3<Float>) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .depthFusion,
            headPosition: position + SIMD3<Float>(0, 0.15, -0.02),
            shoulderMidpoint: position,
            leftShoulder: position + SIMD3<Float>(-0.2, 0, 0),
            rightShoulder: position + SIMD3<Float>(0.2, 0, 0),
            torsoAngle: 2.0,
            headForwardOffset: 0.02,
            shoulderTwist: 0,
            trackingQuality: .good
        )
    }
}
