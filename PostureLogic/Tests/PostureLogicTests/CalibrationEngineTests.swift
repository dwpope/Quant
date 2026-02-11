import XCTest
import simd
@testable import PostureLogic

final class CalibrationEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeSample(
        timestamp: TimeInterval = 1.0,
        headPosition: SIMD3<Float> = SIMD3(0, 1.0, 0),
        shoulderMidpoint: SIMD3<Float> = SIMD3(0, 0, 0),
        torsoAngle: Float = 5,
        shoulderWidthRaw: Float = 0.2,
        trackingQuality: TrackingQuality = .good
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: headPosition,
            shoulderMidpoint: shoulderMidpoint,
            leftShoulder: SIMD3(-0.5, 0, 0),
            rightShoulder: SIMD3(0.5, 0, 0),
            torsoAngle: torsoAngle,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: shoulderWidthRaw,
            trackingQuality: trackingQuality
        )
    }

    private func feedStableSamples(
        to engine: CalibrationEngine,
        count: Int = 35,
        duration: TimeInterval = 6.0
    ) {
        let interval = duration / Double(count)
        for i in 0..<count {
            let t = Double(i) * interval
            _ = engine.addSample(makeSample(timestamp: t))
        }
    }

    // MARK: - Basic Lifecycle

    func test_initialStatus_isWaiting() {
        let engine = CalibrationEngine()
        XCTAssertEqual(engine.status, .waiting)
        XCTAssertNil(engine.resultBaseline)
    }

    func test_firstGoodSample_transitionsToSampling() {
        let engine = CalibrationEngine()
        let status = engine.addSample(makeSample(timestamp: 0))
        XCTAssertEqual(status, .sampling)
    }

    func test_waitingIgnoresPoorTracking() {
        let engine = CalibrationEngine()
        let status = engine.addSample(makeSample(trackingQuality: .degraded))
        XCTAssertEqual(status, .waiting)
    }

    // MARK: - Successful Calibration

    func test_successfulCalibration_withStableSamples() {
        let engine = CalibrationEngine()
        feedStableSamples(to: engine)

        XCTAssertEqual(engine.status, .success)
        XCTAssertNotNil(engine.resultBaseline)
    }

    func test_baselineValues_areAveragedFromSamples() {
        let config = CalibrationConfig(requiredSamples: 3, samplingDuration: 1.0)
        let engine = CalibrationEngine(config: config)

        _ = engine.addSample(makeSample(timestamp: 0, shoulderWidthRaw: 0.20))
        _ = engine.addSample(makeSample(timestamp: 0.5, shoulderWidthRaw: 0.22))
        _ = engine.addSample(makeSample(timestamp: 1.0, shoulderWidthRaw: 0.24))

        guard let baseline = engine.resultBaseline else {
            XCTFail("Expected baseline")
            return
        }

        XCTAssertEqual(baseline.shoulderWidth, 0.22, accuracy: 0.001)
    }

    func test_progressReachesOne_atEnd() {
        let engine = CalibrationEngine()
        feedStableSamples(to: engine)
        XCTAssertEqual(engine.progress, 1.0, accuracy: 0.01)
    }

    // MARK: - Failure: Too Much Movement

    func test_failsWhenPositionVariesTooMuch() {
        let config = CalibrationConfig(
            requiredSamples: 5,
            samplingDuration: 2.0,
            maxPositionVariance: 0.01
        )
        let engine = CalibrationEngine(config: config)

        // Feed samples with varying head positions
        for i in 0..<6 {
            let t = Double(i) * 0.5
            let headY: Float = 1.0 + Float(i) * 0.05  // Moves significantly
            _ = engine.addSample(makeSample(
                timestamp: t,
                headPosition: SIMD3(0, headY, 0)
            ))
        }

        if case .failed(let reason) = engine.status {
            XCTAssertTrue(reason.contains("movement"), "Expected movement-related failure, got: \(reason)")
        } else {
            XCTFail("Expected failure status, got: \(engine.status)")
        }
    }

    func test_failsWhenTorsoAngleVariesTooMuch() {
        let config = CalibrationConfig(
            requiredSamples: 5,
            samplingDuration: 2.0,
            maxAngleVariance: 1.0
        )
        let engine = CalibrationEngine(config: config)

        for i in 0..<6 {
            let t = Double(i) * 0.5
            let angle: Float = Float(i) * 5.0  // Varies from 0 to 25 degrees
            _ = engine.addSample(makeSample(timestamp: t, torsoAngle: angle))
        }

        if case .failed(let reason) = engine.status {
            XCTAssertTrue(reason.contains("angle") || reason.contains("Torso"),
                          "Expected angle-related failure, got: \(reason)")
        } else {
            XCTFail("Expected failure status, got: \(engine.status)")
        }
    }

    // MARK: - Failure: Tracking Quality Drops

    func test_failsWhenTrackingQualityDropsDuringSampling() {
        let config = CalibrationConfig(requiredSamples: 5, samplingDuration: 2.0)
        let engine = CalibrationEngine(config: config)

        // Start with good tracking
        _ = engine.addSample(makeSample(timestamp: 0))
        _ = engine.addSample(makeSample(timestamp: 0.5))

        // Tracking drops
        let status = engine.addSample(makeSample(timestamp: 1.0, trackingQuality: .degraded))

        if case .failed(let reason) = status {
            XCTAssertTrue(reason.contains("Tracking"), "Expected tracking-related failure, got: \(reason)")
        } else {
            XCTFail("Expected failure status, got: \(status)")
        }
    }

    // MARK: - Reset

    func test_resetClearsState() {
        let engine = CalibrationEngine()
        feedStableSamples(to: engine)
        XCTAssertEqual(engine.status, .success)

        engine.reset()

        XCTAssertEqual(engine.status, .waiting)
        XCTAssertNil(engine.resultBaseline)
        XCTAssertEqual(engine.progress, 0)
    }

    func test_canRecalibrateAfterReset() {
        let engine = CalibrationEngine()
        feedStableSamples(to: engine)
        XCTAssertEqual(engine.status, .success)

        engine.reset()
        feedStableSamples(to: engine)
        XCTAssertEqual(engine.status, .success)
        XCTAssertNotNil(engine.resultBaseline)
    }

    // MARK: - Edge Cases

    func test_samplesAfterSuccess_areIgnored() {
        let engine = CalibrationEngine()
        feedStableSamples(to: engine)
        XCTAssertEqual(engine.status, .success)

        let firstBaseline = engine.resultBaseline

        // More samples shouldn't change anything
        _ = engine.addSample(makeSample(timestamp: 100, headPosition: SIMD3(99, 99, 99)))
        XCTAssertEqual(engine.status, .success)
        XCTAssertEqual(engine.resultBaseline?.shoulderWidth, firstBaseline?.shoulderWidth)
    }

    func test_samplesAfterFailure_areIgnored() {
        let config = CalibrationConfig(requiredSamples: 3, samplingDuration: 1.0)
        let engine = CalibrationEngine(config: config)

        _ = engine.addSample(makeSample(timestamp: 0))
        _ = engine.addSample(makeSample(timestamp: 0.5, trackingQuality: .degraded))

        XCTAssertEqual(engine.status, .failed("Tracking quality dropped during calibration"))

        let status = engine.addSample(makeSample(timestamp: 1.5))
        if case .failed = status {
            // Expected - still failed
        } else {
            XCTFail("Expected status to remain failed")
        }
    }

    func test_depthAvailable_whenDepthFusionSamplesPresent() {
        let config = CalibrationConfig(requiredSamples: 3, samplingDuration: 1.0)
        let engine = CalibrationEngine(config: config)

        for i in 0..<4 {
            _ = engine.addSample(PoseSample(
                timestamp: Double(i) * 0.4,
                depthMode: .depthFusion,
                headPosition: SIMD3(0, 1, 0),
                shoulderMidpoint: SIMD3(0, 0, 0),
                leftShoulder: SIMD3(-0.5, 0, 0),
                rightShoulder: SIMD3(0.5, 0, 0),
                torsoAngle: 5,
                headForwardOffset: 0,
                shoulderTwist: 0,
                shoulderWidthRaw: 0.2,
                trackingQuality: .good
            ))
        }

        XCTAssertEqual(engine.resultBaseline?.depthAvailable, true)
    }
}
