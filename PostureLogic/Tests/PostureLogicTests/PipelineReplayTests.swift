import XCTest
import Combine
@testable import PostureLogic

final class PipelineReplayTests: XCTestCase {

    // MARK: - Precomputed Sample Path

    func test_precomputedSample_setsLatestSample() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        try await provider.start()

        let sample = GoldenRecordings.goodPosture().samples[0]
        let frame = InputFrame(
            timestamp: sample.timestamp,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil,
            precomputedSample: sample
        )

        let expectation = XCTestExpectation(description: "latestSample published")
        let cancellable = pipeline.$latestSample
            .dropFirst() // skip initial nil
            .first()
            .sink { received in
                XCTAssertNotNil(received)
                XCTAssertEqual(received?.timestamp, sample.timestamp)
                XCTAssertEqual(received?.trackingQuality, .good)
                expectation.fulfill()
            }

        provider.emit(frame: frame)
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    func test_precomputedSample_computesMetrics() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        let sample = GoldenRecordings.goodPosture().samples[0]
        let frame = InputFrame(
            timestamp: sample.timestamp,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil,
            precomputedSample: sample
        )

        let expectation = XCTestExpectation(description: "metrics published")
        let cancellable = pipeline.$latestMetrics
            .dropFirst()
            .first()
            .sink { metrics in
                XCTAssertNotNil(metrics)
                expectation.fulfill()
            }

        provider.emit(frame: frame)
        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()
    }

    func test_precomputedSample_updatesPostureState() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        // Feed good samples — should get .good state
        let samples = GoldenRecordings.goodPosture().samples
        let expectation = XCTestExpectation(description: "posture state updated")
        var stateHistory: [PostureState] = []

        let cancellable = pipeline.$postureState
            .dropFirst()
            .sink { state in
                stateHistory.append(state)
                if stateHistory.count >= 3 {
                    expectation.fulfill()
                }
            }

        for sample in samples.prefix(5) {
            let frame = InputFrame(
                timestamp: sample.timestamp,
                pixelBuffer: nil,
                depthMap: nil,
                cameraIntrinsics: nil,
                precomputedSample: sample
            )
            provider.emit(frame: frame)
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(stateHistory.contains(.good), "Expected .good in state history: \(stateHistory)")
        cancellable.cancel()
    }

    // MARK: - Recorder Integration

    func test_recorder_capturesSamples() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        let recorder = RecorderService()
        let metadata = SessionMetadata(
            deviceModel: "TestDevice",
            depthAvailable: false,
            thresholds: PostureThresholds()
        )
        recorder.startRecording(metadata: metadata)
        pipeline.recorder = recorder
        try await provider.start()

        let samples = GoldenRecordings.goodPosture().samples

        let expectation = XCTestExpectation(description: "samples recorded")
        let cancellable = pipeline.$latestSample
            .dropFirst()
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        let frame = InputFrame(
            timestamp: samples[0].timestamp,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil,
            precomputedSample: samples[0]
        )
        provider.emit(frame: frame)

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()

        XCTAssertGreaterThanOrEqual(recorder.sampleCount, 1)
    }

    func test_recorder_nilByDefault() {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        XCTAssertNil(pipeline.recorder)
    }
}
