import XCTest
import Combine
@testable import PostureLogic

/// With nobody in view, the app says so (2026-10-08).
///
/// When Vision finds no person, a frame has no pose, and until now such frames never reached the
/// posture engine: only a pose with too few joints counted as lost. So walking away froze the
/// panel on its last words. In Dave's second real-use hour it said "suppressed" from about 16:17,
/// when he left his desk, until he stopped at 17:00. Now a frame with nobody in it counts as lost
/// tracking, and after `absentThreshold` the state is `.absent`.
final class NobodyInViewTests: XCTestCase {

    private let bootClockStart: TimeInterval = 670_636

    // MARK: - The posture engine

    private func goodMetrics(at t: TimeInterval) -> RawMetrics {
        RawMetrics(timestamp: t, forwardCreep: 0.0, headDrop: 0, shoulderRounding: 0, lateralLean: 0,
                   twist: 0, movementLevel: 0, headMovementPattern: .still)
    }

    func test_nobodyInView_forASecond_isAbsent() {
        let engine = PostureEngine()
        engine.update(metrics: goodMetrics(at: 0), taskMode: .unknown, trackingQuality: .good)
        XCTAssertEqual(engine.updateNobodyInView(at: 0.5), .good, "a moment isn't away")
        XCTAssertEqual(engine.updateNobodyInView(at: 1.6), .absent)
    }

    func test_comingBack_afterAWhile_isGoodAgain() {
        let engine = PostureEngine()
        engine.update(metrics: goodMetrics(at: 0), taskMode: .unknown, trackingQuality: .good)
        engine.updateNobodyInView(at: 1)
        engine.updateNobodyInView(at: 100)
        var state = PostureState.absent
        for t in stride(from: 100.0, through: 104.0, by: 0.5) {
            state = engine.update(metrics: goodMetrics(at: t), taskMode: .unknown, trackingQuality: .good)
        }
        XCTAssertEqual(state, .good)
    }

    // MARK: - The pipeline, end to end

    /// Upright, at the baseline.
    private func uprightSample(at t: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2, shoulderWidthRaw: 0.2,
            trackingQuality: .good, headYaw: 0)
    }

    /// Someone at the desk, then frames with nobody in them: no pixels to find a person in, as
    /// when Vision finds none.
    func test_framesWithNobodyInThem_makeThePipelineSayAbsent() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        var sawSomeone = false
        let away = XCTestExpectation(description: "absent after someone was there")
        let watch = pipeline.$postureState.sink { state in
            if state == .good { sawSomeone = true }
            if sawSomeone, state == .absent { away.fulfill() }
        }

        for i in 0..<10 {
            let t = bootClockStart + Double(i) * 0.2
            provider.emit(frame: InputFrame(timestamp: t, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: uprightSample(at: t)))
        }
        for i in 10..<30 {
            let t = bootClockStart + Double(i) * 0.2
            provider.emit(frame: InputFrame(timestamp: t, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: nil))
            try await Task.sleep(nanoseconds: 20_000_000)   // let each frame's pose task land in order
        }

        await fulfillment(of: [away], timeout: 5)
        watch.cancel()
        guard case .none = pipeline.nudgeDecision else {
            return XCTFail("nothing to nudge for while away, got \(pipeline.nudgeDecision)")
        }
    }
}
