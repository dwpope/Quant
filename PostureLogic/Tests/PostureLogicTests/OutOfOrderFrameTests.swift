import XCTest
import Combine
@testable import PostureLogic

/// A frame that arrives out of order changes nothing (2026-10-10).
///
/// Frames are processed concurrently, so now and then one finishes after a newer one: Dave's
/// session-4 recording has four in seven minutes, each 0.1 s back. The nudge engine read the
/// backwards step as a break and wiped the slouched time and the good streak. At 14:26:12 that
/// cut a 24.9 s good streak short of the 30 s that ends a slouch, so the cooldown stayed on and a
/// 60 s lean at 14:26:44 went unnudged. Now the pipeline drops a frame older than the last it
/// took, and the nudge engine ignores one.
final class OutOfOrderFrameTests: XCTestCase {

    private func engine() -> NudgeEngine {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 60
        thresholds.nudgeCooldown = 600
        return NudgeEngine(thresholds: thresholds)
    }

    @discardableResult
    private func frame(_ e: NudgeEngine, at t: TimeInterval, _ state: PostureState,
                       fires: inout [TimeInterval]) -> NudgeDecision {
        let d = e.evaluate(state: state, trackingQuality: .good, movementLevel: 0, taskMode: .unknown,
                           currentTime: t, metrics: nil, headTurnedSince: nil, silenced: false)
        if case .fire = d { fires.append(t); e.recordNudgeFired(at: t) }
        return d
    }

    // MARK: - The nudge engine

    func test_aLateFrame_doesntWipeTheSlouchedTime() {
        let e = engine(); var fires: [TimeInterval] = []
        for t in stride(from: 0.0, to: 50, by: 1) { frame(e, at: t, .bad(since: 0), fires: &fires) }
        frame(e, at: 48.9, .bad(since: 0), fires: &fires)   // finished after the frame at 49
        for t in stride(from: 50.0, to: 70, by: 1) { frame(e, at: t, .bad(since: 0), fires: &fires) }
        XCTAssertEqual(fires.first ?? -1, 60, accuracy: 1.5, "a minute of slouching, not a minute after the late frame")
    }

    /// Session 4 at 14:26: sat well after a nudge, one late frame, then leaned again.
    func test_aLateFrame_doesntCutTheGoodStreakShort() {
        let e = engine(); var fires: [TimeInterval] = []
        for t in stride(from: 0.0, to: 61, by: 1) { frame(e, at: t, .bad(since: 0), fires: &fires) }
        XCTAssertEqual(fires, [60])
        for t in stride(from: 61.0, to: 86, by: 1) { frame(e, at: t, .good, fires: &fires) }
        frame(e, at: 84.9, .good, fires: &fires)
        for t in stride(from: 86.0, to: 96, by: 1) { frame(e, at: t, .good, fires: &fires) }
        for t in stride(from: 96.0, to: 160, by: 1) { frame(e, at: t, .bad(since: 96), fires: &fires) }
        XCTAssertEqual(fires.count, 2, "35 s of sitting well ended the slouch, and the cooldown with it")
        XCTAssertEqual(fires.last ?? 0, 156, accuracy: 1.5)
    }

    // MARK: - The pipeline

    private func upright(at t: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2, shoulderWidthRaw: 0.2,
            trackingQuality: .good, headYaw: 0)
    }

    func test_thePipeline_dropsAFrameOlderThanTheLast() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        let start: TimeInterval = 670_636
        var times: [TimeInterval] = []
        let lastFrame = XCTestExpectation(description: "every frame processed")
        let watch = pipeline.$latestMetrics.sink { m in
            guard let m else { return }
            times.append(m.timestamp)
            if m.timestamp >= start + 2.0 { lastFrame.fulfill() }
        }
        var order = (0...20).map { start + Double($0) * 0.1 }
        order.insert(start + 1.0, at: 13)   // 1.0 again, after 1.2
        for t in order {
            provider.emit(frame: InputFrame(timestamp: t, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: upright(at: t)))
        }
        await fulfillment(of: [lastFrame], timeout: 5)
        watch.cancel()

        XCTAssertEqual(times, times.sorted(), "never a step back")
        XCTAssertEqual(Set(times).count, times.count, "the late frame wasn't taken")
    }
}
