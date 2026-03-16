import XCTest
import Combine
import simd
@testable import PostureLogic

final class LongRunStabilityTests: XCTestCase {

    // MARK: - Constants

    /// 90 minutes at 10 FPS = 54,000 frames
    private let totalFrames = 54_000
    private let frameInterval: TimeInterval = 0.1

    // MARK: - Sample Generation

    /// Generates varied pose samples that cycle through different posture phases:
    /// good posture → gradual slouch → recovery → stretching → good
    /// This exercises all engines (posture, nudge, task mode, staleness).
    private func generateSamples(count: Int) -> [PoseSample] {
        let goodShoulderMid = SIMD3<Float>(0, 0, 0)
        let goodLeft = SIMD3<Float>(-0.5, 0, 0)
        let goodRight = SIMD3<Float>(0.5, 0, 0)

        // Phase cycle: 500 frames each (~50 seconds per phase)
        // 0: good posture (reading-like, small oscillations)
        // 1: gradual slouch
        // 2: sustained bad posture
        // 3: recovery back to good
        // 4: stretching (high movement)
        let phaseLength = 500

        return (0..<count).map { i in
            let ts = Double(i) * frameInterval
            let phase = (i / phaseLength) % 5
            let phaseProgress = Float(i % phaseLength) / Float(phaseLength)

            switch phase {
            case 0:
                // Good posture with reading-like small oscillations
                let osc: Float = (i % 2 == 0) ? 0.008 : -0.008
                return PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(0, 1.0 + osc, 0),
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeft,
                    rightShoulder: goodRight,
                    torsoAngle: 5,
                    headForwardOffset: 0.01,
                    shoulderTwist: 2,
                    shoulderWidthRaw: 0.2,
                    trackingQuality: .good
                )

            case 1:
                // Gradual slouch: linearly interpolate from good to bad
                let t = phaseProgress
                return PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(0, 1.0 + (0.85 - 1.0) * t, 0),
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeft,
                    rightShoulder: goodRight,
                    torsoAngle: 5 + (20 - 5) * t,
                    headForwardOffset: 0.01 + 0.07 * t,
                    shoulderTwist: 2 + (20 - 2) * t,
                    shoulderWidthRaw: 0.2 + (0.24 - 0.2) * t,
                    trackingQuality: .good
                )

            case 2:
                // Sustained bad posture
                return PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(0, 0.85, 0),
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeft,
                    rightShoulder: goodRight,
                    torsoAngle: 20,
                    headForwardOffset: 0.08,
                    shoulderTwist: 20,
                    shoulderWidthRaw: 0.24,
                    trackingQuality: .good
                )

            case 3:
                // Recovery: interpolate from bad back to good
                let t = phaseProgress
                return PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(0, 0.85 + (1.0 - 0.85) * t, 0),
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeft,
                    rightShoulder: goodRight,
                    torsoAngle: 20 + (5 - 20) * t,
                    headForwardOffset: 0.08 + (0.01 - 0.08) * t,
                    shoulderTwist: 20 + (2 - 20) * t,
                    shoulderWidthRaw: 0.24 + (0.2 - 0.24) * t,
                    trackingQuality: .good
                )

            case 4:
                // Stretching: high movement, varied positions
                let swing: Float = sin(Float(i) * 0.3) * 0.15
                return PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(swing, 1.0 + swing * 0.5, 0),
                    shoulderMidpoint: SIMD3<Float>(swing * 0.3, 0, 0),
                    leftShoulder: SIMD3<Float>(-0.5 + swing * 0.2, swing * 0.1, 0),
                    rightShoulder: SIMD3<Float>(0.5 + swing * 0.2, swing * 0.1, 0),
                    torsoAngle: 5 + abs(swing) * 40,
                    headForwardOffset: 0.01 + abs(swing) * 0.3,
                    shoulderTwist: 2 + abs(swing) * 50,
                    shoulderWidthRaw: 0.2 + swing * 0.05,
                    trackingQuality: .good
                )

            default:
                return PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(0, 1.0, 0),
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeft,
                    rightShoulder: goodRight,
                    torsoAngle: 5,
                    headForwardOffset: 0.01,
                    shoulderTwist: 2,
                    shoulderWidthRaw: 0.2,
                    trackingQuality: .good
                )
            }
        }
    }

    /// Returns current memory usage in bytes using mach_task_basic_info.
    private func currentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    private func emitFrames(
        samples: [PoseSample],
        range: Range<Int>,
        via provider: MockPoseProvider
    ) {
        for i in range {
            let sample = samples[i]
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

    @MainActor
    func test_90MinuteSession_noMemoryLeak() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        let samples = generateSamples(count: totalFrames)
        let startMemory = currentMemoryBytes()

        // Process all frames in chunks, yielding between chunks
        // so MainActor-dispatched work can execute
        let chunkSize = 1000
        for chunkStart in stride(from: 0, to: totalFrames, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, totalFrames)
            emitFrames(samples: samples, range: chunkStart..<chunkEnd, via: provider)

            // Yield to let MainActor tasks drain
            await Task.yield()
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }

        // Give final frames time to process
        try await Task.sleep(nanoseconds: 200_000_000)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let endMemory = currentMemoryBytes()
        let memoryDelta = Int64(bitPattern: endMemory) - Int64(bitPattern: startMemory)
        let memoryDeltaMB = Double(memoryDelta) / (1024 * 1024)

        // Memory delta must be < 100MB
        XCTAssertLessThan(memoryDeltaMB, 100.0,
            "Memory grew by \(String(format: "%.1f", memoryDeltaMB))MB — exceeds 100MB limit")

        // Pipeline should still be functional
        XCTAssertNotEqual(pipeline.postureState, .absent,
            "Pipeline should have a non-absent posture state after processing \(totalFrames) frames")
        XCTAssertNotNil(pipeline.latestMetrics,
            "Pipeline should have metrics after processing")
    }

    @MainActor
    func test_allEnginesExercised_duringLongRun() async throws {
        let provider = MockPoseProvider()
        let pipeline = Pipeline(provider: provider)
        pipeline.baseline = GoldenRecordings.baselineForGoodPosture()
        try await provider.start()

        // Use 5000 frames (~8.3 min) to cycle through all 5 phases twice
        let frameCount = 5000
        let samples = generateSamples(count: frameCount)

        var sawGood = false
        var sawBad = false
        var sawDrifting = false
        var taskModes = [TaskMode]()
        var nudgeDecisionTypes = [String]()

        let cancellables = [
            pipeline.$postureState
                .sink { state in
                    switch state {
                    case .good: sawGood = true
                    case .bad: sawBad = true
                    case .drifting: sawDrifting = true
                    default: break
                    }
                },
            pipeline.$taskMode
                .removeDuplicates()
                .sink { taskModes.append($0) },
            pipeline.$nudgeDecision
                .sink { decision in
                    let label: String
                    switch decision {
                    case .none: label = "none"
                    case .pending: label = "pending"
                    case .fire: label = "fire"
                    case .suppressed: label = "suppressed"
                    }
                    if !nudgeDecisionTypes.contains(label) {
                        nudgeDecisionTypes.append(label)
                    }
                },
        ]

        // Process in chunks
        let chunkSize = 500
        for chunkStart in stride(from: 0, to: frameCount, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, frameCount)
            emitFrames(samples: samples, range: chunkStart..<chunkEnd, via: provider)
            await Task.yield()
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }

        // Let final frames drain
        try await Task.sleep(nanoseconds: 200_000_000)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        // Verify multiple posture states were observed
        XCTAssertTrue(sawGood, "Expected .good posture state during run")
        XCTAssertTrue(sawBad || sawDrifting,
            "Expected at least .drifting or .bad posture state during run")

        // Verify task mode changed from initial .unknown
        let uniqueModes = Set(taskModes)
        XCTAssertTrue(uniqueModes.count >= 2,
            "Expected at least 2 different task modes. Observed: \(uniqueModes)")

        // Verify nudge engine was exercised
        XCTAssertTrue(nudgeDecisionTypes.count >= 1,
            "Expected nudge decisions to be exercised. Observed: \(nudgeDecisionTypes)")

        _ = cancellables // keep alive
    }
}
