import XCTest
import Combine
@testable import PostureLogic

/// Nudges have to keep coming after the first one.
///
/// On a device, frame timestamps count seconds since the phone booted: 670,636 in the first
/// device session. The app recorded a fired nudge with the calendar clock, about 1.79 billion, so
/// the engine's `currentTime - lastNudgeTime` was hugely negative, always under the cooldown, and
/// the cooldown never ended. Nothing reset it either, so the app nudged once per launch.
///
/// `NudgeEngineTests` couldn't see this: they pass one clock throughout. This test runs the
/// pipeline on a since-boot clock and records each fire the way the app does, from the
/// `nudgeDecision` subscription.
final class PipelineNudgeClockTests: XCTestCase {

    /// When the first device session's frames started, in seconds since boot.
    private let bootClockStart: TimeInterval = 670_636

    private func slouchSamples(from start: TimeInterval, count: Int, step: TimeInterval) -> [PoseSample] {
        (0..<count).map { i in
            PoseSample(
                timestamp: start + Double(i) * step,
                depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0, 0.85, 0),
                shoulderMidpoint: SIMD3<Float>(0, 0, 0),
                leftShoulder: SIMD3<Float>(-0.5, 0, 0),
                rightShoulder: SIMD3<Float>(0.5, 0, 0),
                torsoAngle: 20,
                headForwardOffset: 0.08,
                shoulderTwist: 20,
                shoulderWidthRaw: 0.24,
                trackingQuality: .good)
        }
    }

    private func emit(_ samples: [PoseSample], via provider: MockPoseProvider) {
        for sample in samples {
            provider.emit(frame: InputFrame(
                timestamp: sample.timestamp, pixelBuffer: nil, depthMap: nil,
                cameraIntrinsics: nil, precomputedSample: sample))
        }
    }

    /// Short timings so a few seconds of frames cover it: bad after 1 s, a nudge after 2 s of
    /// bad posture, then a 5 s cooldown. The clock is what's under test, not these values.
    ///
    /// Passed to `init` because the nudge engine takes its limits there: setting
    /// `pipeline.thresholds` afterwards reaches only the posture engine.
    private func pipelineWithShortTimings(provider: MockPoseProvider) -> Pipeline {
        var t = PostureThresholds()
        t.driftingToBadThreshold = 1
        t.slouchDurationBeforeNudge = 2
        t.nudgeCooldown = 5
        t.maxNudgesPerHour = 10
        let pipeline = Pipeline(provider: provider, thresholds: t)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        return pipeline
    }

    func test_aSecondNudgeFires_afterTheCooldown_onADeviceClock() async throws {
        let provider = MockPoseProvider()
        let pipeline = pipelineWithShortTimings(provider: provider)
        try await provider.start()

        var fireTimes: [TimeInterval] = []
        let secondFire = XCTestExpectation(description: "a second nudge after the cooldown")
        let subscription = pipeline.$nudgeDecision.sink { decision in
            guard case .fire = decision else { return }
            fireTimes.append(pipeline.latestMetrics?.timestamp ?? .nan)
            pipeline.recordNudgeFired()   // what AppModel does when a nudge fires
            if fireTimes.count == 2 { secondFire.fulfill() }
        }

        // 30 s of steady slouching, a frame every 0.5 s, on the since-boot clock.
        emit(slouchSamples(from: bootClockStart, count: 60, step: 0.5), via: provider)
        await fulfillment(of: [secondFire], timeout: 5)
        subscription.cancel()

        try XCTSkipIf(fireTimes.count < 2)  // already reported by the expectation above
        let gap = fireTimes[1] - fireTimes[0]
        XCTAssertGreaterThan(gap, 5, "the second nudge waits out the cooldown")
        XCTAssertLessThan(gap, 7, "and comes as soon as the cooldown ends, not never")
    }

    /// The fire is recorded on the frame clock the engine measures with, whatever the caller's
    /// own clock says.
    func test_aFiredNudge_isRecordedAtTheFrameTime() async throws {
        let provider = MockPoseProvider()
        let pipeline = pipelineWithShortTimings(provider: provider)
        try await provider.start()

        let fired = XCTestExpectation(description: "first nudge")
        var recordedAt: TimeInterval?
        let subscription = pipeline.$nudgeDecision.sink { decision in
            guard case .fire = decision, recordedAt == nil else { return }
            pipeline.recordNudgeFired()
            recordedAt = pipeline.latestMetrics?.timestamp
            fired.fulfill()
        }

        emit(slouchSamples(from: bootClockStart, count: 20, step: 0.5), via: provider)
        await fulfillment(of: [fired], timeout: 5)
        subscription.cancel()

        let lastNudgeTime = try XCTUnwrap(pipeline.nudgeDebugState["lastNudgeTime"] as? TimeInterval)
        XCTAssertEqual(lastNudgeTime, try XCTUnwrap(recordedAt), accuracy: 0.001)
        XCTAssertLessThan(lastNudgeTime, bootClockStart + 3_600, "a since-boot time, not a calendar one")
    }
}
