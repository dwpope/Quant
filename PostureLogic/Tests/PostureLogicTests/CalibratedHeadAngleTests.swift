import XCTest
import Combine
@testable import PostureLogic

/// Head turns are measured from where you looked when calibrating (2026-10-05).
///
/// Head yaw is camera-absolute. In session 6 the phone sat about 50° to one side of where Dave
/// looks, so sitting normally read +50°, past the head-turn rule's 45°: the head-turn nudge would
/// have fired during ordinary work. Calibration now records the head angle, the app warns when
/// it's well off centre, and head turns (and turned chairs) are measured from it.
final class CalibratedHeadAngleTests: XCTestCase {

    private func sample(yaw: Float, at t: TimeInterval, shoulderWidth: Float = 0.2) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
            shoulderWidthRaw: shoulderWidth, trackingQuality: .good, headYaw: yaw)
    }

    // MARK: - Calibration records it

    func test_calibration_recordsTheMeanHeadAngle() throws {
        let engine = CalibrationEngine(config: CalibrationConfig(requiredSamples: 3, samplingDuration: 1.0))
        _ = engine.addSample(sample(yaw: 48, at: 0))
        _ = engine.addSample(sample(yaw: 50, at: 0.5))
        _ = engine.addSample(sample(yaw: 52, at: 1.0))
        XCTAssertEqual(try XCTUnwrap(engine.resultBaseline).headYaw, 50, accuracy: 0.001)
    }

    func test_aBaselineSavedBeforeThis_readsAsLookingStraightAtThePhone() throws {
        let old = """
        {"timestamp":0,"shoulderMidpoint":[0,0,0],"headPosition":[0,1,0],"torsoAngle":5,
         "shoulderWidth":0.2,"depthAvailable":false}
        """
        let baseline = try JSONDecoder().decode(Baseline.self, from: Data(old.utf8))
        XCTAssertEqual(baseline.headYaw, 0)
    }

    func test_theHeadAngle_isSaved() throws {
        let baseline = Baseline(timestamp: Date(), shoulderMidpoint: .zero, headPosition: .zero,
                                torsoAngle: 0, shoulderWidth: 0.2, depthAvailable: false, headYaw: 50)
        let copy = try JSONDecoder().decode(Baseline.self, from: JSONEncoder().encode(baseline))
        XCTAssertEqual(copy.headYaw, 50)
    }

    // MARK: - Head turns measured from it

    private func fires(baselineYaw: Float, frameYaw: Float) async throws -> (reasons: [NudgeReason], turned: Bool) {
        let provider = MockPoseProvider()
        var h = HeadTurnThresholds()
        h.durationBeforeNudge = 2
        let pipeline = Pipeline(provider: provider, headTurnThresholds: h)
        pipeline.baseline = Baseline(timestamp: Date(), shoulderMidpoint: .zero,
                                     headPosition: SIMD3<Float>(0, 1.0, 0), torsoAngle: 5,
                                     shoulderTwist: 2, shoulderWidth: 0.2, depthAvailable: false,
                                     headYaw: baselineYaw)
        try await provider.start()
        var reasons: [NudgeReason] = []
        var everTurned = false
        let samples = (0..<10).map { sample(yaw: frameYaw, at: 670_636 + Double($0) * 0.5) }
        let done = XCTestExpectation(description: "every frame processed")
        let fires = pipeline.$nudgeDecision.sink { d in
            if case .fire(let r) = d { reasons.append(r); pipeline.recordNudgeFired() }
        }
        let turned = pipeline.$headTurnedSince.sink { if $0 != nil { everTurned = true } }
        let frames = pipeline.$latestMetrics.sink { m in
            if let t = m?.timestamp, t >= samples.last!.timestamp { done.fulfill() }
        }
        for s in samples {
            provider.emit(frame: InputFrame(timestamp: s.timestamp, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: s))
        }
        await fulfillment(of: [done], timeout: 5)
        fires.cancel(); turned.cancel(); frames.cancel()
        return (reasons, everTurned)
    }

    /// Session 6: calibrated at +50° with the phone to one side. Sitting the same way is not a turn.
    func test_lookingWhereYouCalibrated_isNotATurn_evenWithThePhoneToOneSide() async throws {
        let result = try await fires(baselineYaw: 50, frameYaw: 50)
        XCTAssertFalse(result.turned)
        XCTAssertEqual(result.reasons, [])
    }

    /// 60° from where you calibrated is a turn, whichever way the camera reads it.
    func test_turning60DegreesFromWhereYouCalibrated_isATurn() async throws {
        let result = try await fires(baselineYaw: 50, frameYaw: -10)
        XCTAssertTrue(result.turned)
        XCTAssertEqual(result.reasons, [.headTurned])
    }
}
