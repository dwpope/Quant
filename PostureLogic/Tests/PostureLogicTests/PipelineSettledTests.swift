import XCTest
@testable import PostureLogic

/// Waiting for the pipeline to finish what it was given, instead of sleeping (2026-10-12).
///
/// About 25 pipeline tests slept a fixed 10–100 ms per frame and hoped the work had landed:
/// a slow machine made them fail, and a fast one wasted most of the suite's 12 s. Now a test
/// awaits `settled()`, which returns once every frame handed in so far has been processed.
final class PipelineSettledTests: XCTestCase {

    private func sample(at t: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
            shoulderWidthRaw: 0.2, trackingQuality: .good, headYaw: 0)
    }

    func test_settled_returnsOnceEveryFrameIsProcessed() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        try await provider.start()
        let start: TimeInterval = 1_791_640_000
        for i in 0..<200 {
            let t = start + Double(i) * 0.1
            provider.emit(frame: InputFrame(timestamp: t, pixelBuffer: nil, depthMap: nil,
                                            cameraIntrinsics: nil, precomputedSample: sample(at: t)))
        }
        await pipeline.settled()
        let last = await MainActor.run { pipeline.latestSample?.timestamp }
        XCTAssertEqual(last, start + 19.9)
    }

    /// With nothing handed in, there's nothing to wait for.
    func test_settled_withNothingInFlight_returnsAtOnce() async {
        let pipeline = Pipeline(provider: MockPoseProvider())
        await pipeline.settled()
    }

    /// A live frame (no precomputed pose) is waited for too, though it yields no pose here.
    func test_settled_waitsForALiveFrame() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        try await provider.start()
        provider.emit(frame: InputFrame(timestamp: 1_791_640_000, pixelBuffer: nil, depthMap: nil,
                                        cameraIntrinsics: nil))
        await pipeline.settled()
        let quality = await MainActor.run { pipeline.trackingQuality }
        XCTAssertEqual(quality, .lost, "processed: no pixel buffer is lost tracking")
    }
}
