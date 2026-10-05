import XCTest
import Combine
@testable import PostureLogic

/// The pipeline times a head held turned, from each frame's head yaw and forward creep, and the
/// nudge engine fires for it with good posture. On the since-boot frame clock, as on a device.
final class PipelineHeadTurnTests: XCTestCase {

    private let bootClockStart: TimeInterval = 670_636

    /// Upright, at the baseline, with the head turned `yaw` degrees.
    private func samples(yaw: Float, from start: TimeInterval, count: Int, step: TimeInterval) -> [PoseSample] {
        (0..<count).map { i in
            PoseSample(
                timestamp: start + Double(i) * step,
                depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0, 1.0, 0),
                shoulderMidpoint: SIMD3<Float>(0, 0, 0),
                leftShoulder: SIMD3<Float>(-0.5, 0, 0),
                rightShoulder: SIMD3<Float>(0.5, 0, 0),
                torsoAngle: 5,
                headForwardOffset: 0.01,
                shoulderTwist: 2,
                shoulderWidthRaw: 0.2,
                trackingQuality: .good,
                headYaw: yaw)
        }
    }

    private func emit(_ samples: [PoseSample], via provider: MockPoseProvider) {
        for sample in samples {
            provider.emit(frame: InputFrame(
                timestamp: sample.timestamp, pixelBuffer: nil, depthMap: nil,
                cameraIntrinsics: nil, precomputedSample: sample))
        }
    }

    private func shortHeadTurn() -> HeadTurnThresholds {
        var h = HeadTurnThresholds()
        h.durationBeforeNudge = 2
        return h
    }

    /// Collects every fire reason until `count` have arrived or the frames run out.
    private func fireReasons(of pipeline: Pipeline, from samples: [PoseSample],
                             via provider: MockPoseProvider) async -> [NudgeReason] {
        var reasons: [NudgeReason] = []
        let lastFrame = XCTestExpectation(description: "every frame processed")
        let lastTime = samples.last?.timestamp ?? 0
        let fires = pipeline.$nudgeDecision.sink { decision in
            if case .fire(let reason) = decision {
                reasons.append(reason)
                pipeline.recordNudgeFired()
            }
        }
        let frames = pipeline.$latestMetrics.sink { metrics in
            if let t = metrics?.timestamp, t >= lastTime { lastFrame.fulfill() }
        }
        emit(samples, via: provider)
        await fulfillment(of: [lastFrame], timeout: 5)
        fires.cancel()
        frames.cancel()
        return reasons
    }

    func test_aHeadHeldTurned_firesAHeadTurnNudge_withGoodPosture() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider, headTurnThresholds: shortHeadTurn())
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        let reasons = await fireReasons(
            of: pipeline, from: samples(yaw: 70, from: bootClockStart, count: 10, step: 0.5), via: provider)

        XCTAssertEqual(reasons, [.headTurned])
        XCTAssertEqual(pipeline.postureState, .good, "it's not a slouch")
    }

    func test_lookingAtTheScreen_firesNothing() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider, headTurnThresholds: shortHeadTurn())
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        let reasons = await fireReasons(
            of: pipeline, from: samples(yaw: 3, from: bootClockStart, count: 10, step: 0.5), via: provider)

        XCTAssertEqual(reasons, [])
    }

    /// Without a calibration there's no forward creep to tell a swivel from a turned neck.
    func test_beforeCalibrating_aHeadTurnIsNotTimed() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider, headTurnThresholds: shortHeadTurn())
        try await provider.start()

        let reasons = await fireReasons(
            of: pipeline, from: samples(yaw: 70, from: bootClockStart, count: 10, step: 0.5), via: provider)

        XCTAssertEqual(reasons, [])
        XCTAssertNil(pipeline.headTurnedSince)
    }

    /// Set after init, as the app would, the limits reach both the tracker and the nudge engine.
    func test_headTurnLimitsSetAfterInit_apply() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)   // default: five minutes
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        pipeline.headTurnThresholds = shortHeadTurn()
        try await provider.start()

        let reasons = await fireReasons(
            of: pipeline, from: samples(yaw: -70, from: bootClockStart, count: 10, step: 0.5), via: provider)

        XCTAssertEqual(reasons, [.headTurned])
    }
}
