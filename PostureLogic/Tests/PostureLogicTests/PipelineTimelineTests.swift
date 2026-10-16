import XCTest
import Combine
@testable import PostureLogic

/// The pipeline keeps judging when it can't build a pose, and starts afresh on a new timeline
/// (2026-10-11).
final class PipelineTimelineTests: XCTestCase {

    private func sample(at t: TimeInterval, slouched: Bool) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
            shoulderWidthRaw: slouched ? 0.24 : 0.2, trackingQuality: .good, headYaw: 0)
    }

    // MARK: - A pose that can't be built

    /// One shoulder hidden: tracking still has a head and a shoulder, but a pose needs both
    /// shoulders. Until now nothing ran on such a frame, so the state and the nudge decision
    /// froze on their last values. Now it counts as degraded tracking: the slouch clock pauses,
    /// and the decision says why.
    @MainActor
    func test_aPoseThatCantBeBuilt_isDegradedTracking_notAFreeze() {
        let pipeline = Pipeline(provider: MockPoseProvider())
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        let start: TimeInterval = 1_791_640_000
        for i in 0..<200 {
            let t = start + Double(i) * 0.1
            pipeline.ingest(sample(at: t, slouched: true), quality: .good, at: t)
        }
        guard case .pending = pipeline.nudgeDecision else {
            return XCTFail("counting down after 20 s slouched, got \(pipeline.nudgeDecision)")
        }
        for i in 200..<230 {
            pipeline.ingest(nil, quality: .good, at: start + Double(i) * 0.1)
        }
        XCTAssertEqual(pipeline.trackingQuality, .degraded)
        guard case .suppressed(.lowTrackingQuality) = pipeline.nudgeDecision else {
            return XCTFail("says it can't see well enough, got \(pipeline.nudgeDecision)")
        }
    }

    /// The latest frame judged, with or without a pose, and when (2026-10-16). The Watch's times
    /// are converted against it. `latestMetrics` stops at the last frame with a pose, and the
    /// Watch's countdown climbed while a shoulder was hidden: the due time was on the new frame's
    /// clock and converted against the old one's.
    @MainActor
    func test_aFrameWithoutAPose_isTheLatestFrame() throws {
        let pipeline = Pipeline(provider: MockPoseProvider())
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        let judged = Date(timeIntervalSince1970: 1_800_000_000)
        pipeline.now = { judged }
        let start: TimeInterval = 1_791_640_000
        for i in 0..<200 {
            let t = start + Double(i) * 0.1
            pipeline.ingest(sample(at: t, slouched: true), quality: .good, at: t)
        }
        for i in 200..<230 {
            pipeline.ingest(nil, quality: .good, at: start + Double(i) * 0.1)
        }

        let frame = try XCTUnwrap(pipeline.latestFrame)
        XCTAssertEqual(frame.time, start + 22.9, accuracy: 1e-6)
        XCTAssertEqual(frame.judgedAt, judged)
        XCTAssertEqual(try XCTUnwrap(pipeline.latestMetrics?.timestamp), start + 19.9, accuracy: 1e-6,
                       "the metrics stop at the last pose")
        // The slouch clock is paused, so the time left is the same 40 s as at the last pose.
        XCTAssertEqual(try XCTUnwrap(pipeline.nudgeDueAt) - frame.time, 40, accuracy: 0.5)

        pipeline.resetTimeline()
        XCTAssertNil(pipeline.latestFrame, "a new timeline has no frame yet")
    }

    // MARK: - A new timeline

    /// Live frames, then a recording from an hour earlier through the same pipeline. The step
    /// back left every engine behind: the nudge engine took each replay frame for a late one, so
    /// a replay after live frames never nudged.
    func test_aReplayAfterLiveFrames_isNudgedLikeAnyOther() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        let live: TimeInterval = 1_791_640_000
        let replay = live - 3600
        var fires: [TimeInterval] = []
        let lastFrame = XCTestExpectation(description: "every frame processed")
        let watch = pipeline.$nudgeDecision.sink { decision in
            guard let t = pipeline.latestMetrics?.timestamp else { return }
            if case .fire = decision { fires.append(t); pipeline.recordNudgeFired() }
            if t >= replay + 80 && t < live { lastFrame.fulfill() }
        }
        var times = (0..<60).map { live + Double($0) * 0.5 }        // 30 s live, slouched
        times += (0...170).map { replay + Double($0) * 0.5 }         // 85 s of replay, slouched
        for t in times {
            provider.emit(frame: InputFrame(timestamp: t, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil,
                                            precomputedSample: sample(at: t, slouched: true)))
        }
        await fulfillment(of: [lastFrame], timeout: 10)
        watch.cancel()

        let replayFires = fires.filter { $0 < live }
        XCTAssertEqual(replayFires.count, 1, "nudged once in the replay, a minute in")
        XCTAssertEqual(replayFires.first ?? 0, replay + 60, accuracy: 2)
    }
}
