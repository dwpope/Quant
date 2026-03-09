import XCTest
import Combine
@testable import PostureLogic

final class PipelineTaskModeTests: XCTestCase {

    // MARK: - Helpers

    /// Creates precomputed samples that produce a "reading" movement pattern:
    /// low overall movement (movementLevel < 0.2) with small head oscillations.
    private func readingSamples(count: Int) -> [PoseSample] {
        let shoulderMid = SIMD3<Float>(0, 0, 0)
        let leftShoulder = SIMD3<Float>(-0.5, 0, 0)
        let rightShoulder = SIMD3<Float>(0.5, 0, 0)

        return (0..<count).map { i in
            // Oscillate head Y by ~0.01 each frame → mean displacement ~0.01
            // This lands in the smallOscillations range (0.005–0.02)
            let oscillation: Float = (i % 2 == 0) ? 0.01 : -0.01
            let headPos = SIMD3<Float>(0, 1.0 + oscillation, 0)

            return PoseSample(
                timestamp: Double(i) * 0.1,
                depthMode: .twoDOnly,
                headPosition: headPos,
                shoulderMidpoint: shoulderMid,
                leftShoulder: leftShoulder,
                rightShoulder: rightShoulder,
                torsoAngle: 5,
                headForwardOffset: 0.01,
                shoulderTwist: 2,
                shoulderWidthRaw: 0.2,
                trackingQuality: .good
            )
        }
    }

    private func emitSamples(
        _ samples: [PoseSample],
        via provider: MockPoseProvider
    ) {
        for sample in samples {
            let frame = InputFrame(
                timestamp: sample.timestamp,
                pixelBuffer: nil,
                depthMap: nil,
                cameraIntrinsics: nil,
                precomputedSample: sample
            )
            provider.emit(frame: frame)
        }
    }

    // MARK: - Tests

    func test_pipeline_infersTaskMode_fromMetricsWindow() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        // Feed 100+ reading-like samples to fill the metrics window
        let samples = readingSamples(count: 120)

        let expectation = XCTestExpectation(description: "taskMode inferred")
        let cancellable = pipeline.$taskMode
            .dropFirst() // skip initial .unknown
            .first { $0 != .unknown }
            .sink { mode in
                XCTAssertEqual(mode, .reading, "Expected .reading from low-movement small-oscillation samples")
                expectation.fulfill()
            }

        emitSamples(samples, via: provider)
        await fulfillment(of: [expectation], timeout: 3.0)
        cancellable.cancel()
    }

    func test_pipeline_passesInferredTaskMode_toPostureEngine() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        // Feed reading-like samples so task mode becomes .reading
        let samples = readingSamples(count: 120)

        let expectation = XCTestExpectation(description: "posture state updated with task mode")
        var postureUpdates: [PostureState] = []
        let cancellable = pipeline.$postureState
            .dropFirst()
            .sink { state in
                postureUpdates.append(state)
                if postureUpdates.count >= 20 {
                    expectation.fulfill()
                }
            }

        emitSamples(samples, via: provider)
        await fulfillment(of: [expectation], timeout: 3.0)
        cancellable.cancel()

        // PostureEngine received inferred taskMode (not .unknown) for each frame.
        // With good-posture reading samples, the state should settle to .good.
        XCTAssertTrue(postureUpdates.contains(.good),
                       "Expected .good in posture history: \(postureUpdates)")
        // Verify task mode was inferred as reading (confirming it was passed through)
        XCTAssertEqual(pipeline.taskMode, .reading)
    }

    func test_pipeline_passesInferredTaskMode_toNudgeEngine() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        // Feed reading-like samples so task mode becomes .reading
        let samples = readingSamples(count: 120)

        let expectation = XCTestExpectation(description: "nudge decision updated with task mode")
        var nudgeUpdates: [NudgeDecision] = []
        let cancellable = pipeline.$nudgeDecision
            .dropFirst()
            .sink { decision in
                nudgeUpdates.append(decision)
                if nudgeUpdates.count >= 20 {
                    expectation.fulfill()
                }
            }

        emitSamples(samples, via: provider)
        await fulfillment(of: [expectation], timeout: 3.0)
        cancellable.cancel()

        // NudgeEngine received inferred taskMode (not .unknown) for each frame.
        // With good-posture samples, no nudge should fire.
        let allNone = nudgeUpdates.allSatisfy {
            if case .none = $0 { return true }
            return false
        }
        XCTAssertTrue(allNone,
                       "Expected all .none nudge decisions with good posture, got: \(nudgeUpdates)")
        // Verify task mode was inferred as reading (confirming it was passed through)
        XCTAssertEqual(pipeline.taskMode, .reading)
    }
}
