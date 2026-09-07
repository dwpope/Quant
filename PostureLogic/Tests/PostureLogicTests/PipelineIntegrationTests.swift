import XCTest
import Combine
@testable import PostureLogic
import simd

// MARK: - End-to-End Pipeline Integration Tests
//
// These tests exercise the full pipeline path using precomputed PoseSamples:
// MockPoseProvider → Pipeline (precomputed path) → MetricsEngine → MetricsSmoother
// → PostureEngine → NudgeEngine → TaskModeEngine
//
// They validate that the engines work together correctly as a system,
// not just individually. This is the gap identified in the May 9 project
// movement report: model-level coverage is thorough, but the full-pipeline
// chain had no tests.

final class PipelineIntegrationTests: XCTestCase {

    // MARK: - Helpers

    /// Baseline representing "good" upright posture.
    static func makeBaseline() -> Baseline {
        Baseline(
            timestamp: Date(),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.4, 0),
            headPosition: SIMD3<Float>(0.5, 0.25, 0),
            torsoAngle: 0,
            shoulderTwist: 0,
            shoulderWidth: 0.3,
            depthAvailable: false,
            neckHeight: 0.25    // calibrated neutral head carriage (ear-based)
        )
    }

    /// A PoseSample that matches the baseline (good posture).
    static func goodSample(at timestamp: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.25, 0),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.4, 0),
            leftShoulder: SIMD3<Float>(0.35, 0.4, 0),
            rightShoulder: SIMD3<Float>(0.65, 0.4, 0),
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0.3,
            trackingQuality: .good,
            neckHeight: 0.25    // matches baseline neutral ⇒ headDrop ≈ 0
        )
    }

    /// A PoseSample with significant forward creep and head drop (bad posture).
    static func badSample(at timestamp: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.35, 0),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.4, 0),
            leftShoulder: SIMD3<Float>(0.32, 0.4, 0),
            rightShoulder: SIMD3<Float>(0.68, 0.4, 0),
            torsoAngle: 12,                               // 12° forward lean
            headForwardOffset: 0.1,
            shoulderTwist: 0,
            shoulderWidthRaw: 0.36,                       // 20% wider = forward creep
            trackingQuality: .good,
            neckHeight: 0.35    // headDrop = 0.25 - 0.35 = -0.10 (see test_metricsValues)
        )
    }

    /// A PoseSample with lost tracking (user absent).
    static func lostSample(at timestamp: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 0, 0),
            shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(0, 0, 0),
            rightShoulder: SIMD3<Float>(0, 0, 0),
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .lost
        )
    }

    /// Emit a precomputed sample through the pipeline and wait for processing.
    func emitAndWait(
        _ mock: MockPoseProvider,
        sample: PoseSample,
        waitNanos: UInt64 = 100_000_000
    ) async throws {
        let frame = InputFrame(
            timestamp: sample.timestamp,
            pixelBuffer: nil,
            depthMap: nil,
            cameraIntrinsics: nil,
            precomputedSample: sample
        )
        mock.emit(frame: frame)
        try await Task.sleep(nanoseconds: waitNanos)
    }

    // MARK: - Tests

    /// Good posture samples produce near-zero metrics and .good state.
    func test_goodPosture_producesGoodState() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        for i in 0..<5 {
            try await emitAndWait(mock, sample: Self.goodSample(at: t + Double(i) * 0.1))
        }

        XCTAssertEqual(pipeline.postureState, .good, "Good posture samples should produce .good state")

        if let metrics = pipeline.latestMetrics {
            XCTAssertEqual(metrics.forwardCreep, 0, accuracy: 0.01, "Forward creep should be ~0 when matching baseline")
            XCTAssertEqual(metrics.headDrop, 0, accuracy: 0.01, "Head drop should be ~0 when matching baseline")
            XCTAssertEqual(metrics.shoulderRounding, 0, accuracy: 0.5, "Shoulder rounding should be ~0 when matching baseline")
            XCTAssertEqual(metrics.lateralLean, 0, accuracy: 0.01, "Lateral lean should be ~0 when matching baseline")
            XCTAssertEqual(metrics.twist, 0, accuracy: 0.5, "Twist should be ~0 when matching baseline")
        } else {
            XCTFail("Pipeline should have produced metrics after processing good posture samples")
        }

        if case .none = pipeline.nudgeDecision {
            // Expected
        } else {
            XCTFail("Nudge decision should be .none for good posture, got \(pipeline.nudgeDecision)")
        }
    }

    /// Bad posture produces non-zero metrics and transitions to .drifting.
    func test_badPosture_transitionsToDrifting() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        try await emitAndWait(mock, sample: Self.badSample(at: t + 0.2))

        if let metrics = pipeline.latestMetrics {
            XCTAssertGreaterThan(metrics.forwardCreep, 0.03, "Bad posture should produce forward creep above threshold")
            XCTAssertNotEqual(metrics.headDrop, 0, accuracy: 0.001, "Bad posture head drop metric should be non-zero")
            XCTAssertGreaterThan(metrics.shoulderRounding, 2, "Bad posture should produce shoulder rounding (EMA smoothed)")
        } else {
            XCTFail("Pipeline should have produced metrics")
        }

        if case .drifting = pipeline.postureState {
            // Expected
        } else {
            XCTFail("Bad posture should transition to .drifting, got \(pipeline.postureState)")
        }
    }

    /// Sustained bad posture transitions from .drifting to .bad after threshold.
    func test_sustainedBadPosture_transitionsToBad() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 2.0
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))

        for i in 1...30 {
            try await emitAndWait(mock, sample: Self.badSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertTrue(pipeline.postureState.isBad, "Sustained bad posture (3s) should transition to .bad with 2s threshold")
    }

    /// Recovery from .bad requires maintaining good posture for the grace period.
    func test_recoveryFromBad_requiresGracePeriod() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 0.5
        thresholds.recoveryGracePeriod = 1.0
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        for i in 1...10 {
            try await emitAndWait(mock, sample: Self.badSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }
        XCTAssertTrue(pipeline.postureState.isBad, "Should be in .bad state before recovery test")

        // One good frame should not recover
        try await emitAndWait(mock, sample: Self.goodSample(at: t + 1.5))
        XCTAssertTrue(pipeline.postureState.isBad, "One good frame should not recover from .bad (grace period not elapsed)")

        // Good frames spanning the full grace period
        for i in 0...15 {
            try await emitAndWait(mock, sample: Self.goodSample(at: t + 1.6 + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertEqual(pipeline.postureState, .good, "Good posture sustained beyond grace period should recover to .good")
    }

    /// Lost tracking triggers .absent state after the absent threshold.
    func test_lostTracking_triggersAbsent() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.absentThreshold = 0.5
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        XCTAssertEqual(pipeline.postureState, .good)

        for i in 1...10 {
            try await emitAndWait(mock, sample: Self.lostSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertEqual(pipeline.postureState, .absent, "Lost tracking beyond absent threshold should produce .absent")
    }

    /// Without a baseline, metrics should all be zero.
    func test_noBaseline_producesZeroMetrics() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        // Intentionally NOT setting pipeline.baseline
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.badSample(at: t))

        if let metrics = pipeline.latestMetrics {
            XCTAssertEqual(metrics.forwardCreep, 0, "Without baseline, forwardCreep should be 0")
            XCTAssertEqual(metrics.headDrop, 0, "Without baseline, headDrop should be 0")
            XCTAssertEqual(metrics.shoulderRounding, 0, "Without baseline, shoulderRounding should be 0")
            XCTAssertEqual(metrics.lateralLean, 0, "Without baseline, lateralLean should be 0")
            XCTAssertEqual(metrics.twist, 0, "Without baseline, twist should be 0")
        } else {
            XCTFail("Pipeline should still produce (zero) metrics without a baseline")
        }
    }

    /// Bad posture produces expected metric values relative to baseline.
    func test_metricsValues_matchBaselineDeviation() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        // First sample passes through MetricsSmoother unsmoothed
        try await emitAndWait(mock, sample: Self.badSample(at: t))

        guard let metrics = pipeline.latestMetrics else {
            XCTFail("Should have metrics")
            return
        }

        // Forward creep = (0.36 - 0.3) / 0.3 = 0.2
        XCTAssertEqual(metrics.forwardCreep, 0.2, accuracy: 0.01, "Forward creep should be ~0.2 (20% wider shoulders)")
        // Head drop = baseline.neckHeight - sample.neckHeight = 0.25 - 0.35 = -0.10
        XCTAssertEqual(metrics.headDrop, -0.10, accuracy: 0.01, "Head drop should be ~-0.10")
        // Shoulder rounding = sample.torsoAngle - baseline.torsoAngle = 12 - 0 = 12
        XCTAssertEqual(metrics.shoulderRounding, 12, accuracy: 0.1, "Shoulder rounding should be ~12 degrees")
    }

    /// Pipeline updates FPS when processing frames.
    func test_pipeline_updatesFPS() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        for i in 0..<10 {
            try await emitAndWait(mock, sample: Self.goodSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertGreaterThan(pipeline.fps, 0, "FPS should be computed after multiple frames")
    }

    /// Nudge decision progresses past .none after sustained bad posture.
    func test_nudgeProgresses_afterSustainedBadPosture() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 0.5
        thresholds.slouchDurationBeforeNudge = 1.0
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        for i in 1...50 {
            try await emitAndWait(mock, sample: Self.badSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertTrue(pipeline.postureState.isBad, "Should be in .bad state")
        let decision = pipeline.nudgeDecision
        switch decision {
        case .none:
            XCTFail("Nudge should not be .none after sustained bad posture")
        case .pending, .fire, .suppressed:
            break  // Any of these is valid progress through the nudge chain
        }
    }

    /// Tracking quality is published for precomputed samples.
    func test_trackingQuality_publishedFromPrecomputedSamples() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        XCTAssertEqual(pipeline.trackingQuality, .good, "Good sample should publish .good tracking")

        try await emitAndWait(mock, sample: Self.lostSample(at: t + 1.0))
        XCTAssertEqual(pipeline.trackingQuality, .lost, "Lost sample should publish .lost tracking")
    }

    /// Pipeline records samples when a recorder is attached.
    func test_recorder_capturesPrecomputedSamples() async throws {
        let mock = MockPoseProvider()
        let pipeline = Pipeline(provider: mock)
        let recorder = MockRecorder()
        pipeline.recorder = recorder
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        try await emitAndWait(mock, sample: Self.goodSample(at: t + 0.1))
        try await emitAndWait(mock, sample: Self.goodSample(at: t + 0.2))

        XCTAssertEqual(recorder.recordedSamples.count, 3, "Recorder should capture all precomputed samples")
    }

    /// Absence segments are tracked when user goes absent.
    func test_absenceSegments_trackedCorrectly() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.absentThreshold = 0.3
        thresholds.returnValidationWindow = 0.2
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        for i in 0..<3 {
            try await emitAndWait(mock, sample: Self.goodSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }
        for i in 0...5 {
            try await emitAndWait(mock, sample: Self.lostSample(at: t + 0.5 + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertFalse(pipeline.absenceSegments.isEmpty, "Should have at least one absence segment after going absent")
    }

    /// Recalibration prompt fires after a long absence.
    func test_longAbsence_triggersRecalibrationPrompt() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.absentThreshold = 0.3
        thresholds.absentResumeThreshold = 2.0
        thresholds.returnValidationWindow = 0.2
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        for i in 1...5 {
            try await emitAndWait(mock, sample: Self.lostSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }
        XCTAssertEqual(pipeline.postureState, .absent)

        // Return after long gap (>2s)
        for i in 0...5 {
            try await emitAndWait(mock, sample: Self.goodSample(at: t + 5.0 + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        XCTAssertTrue(pipeline.showRecalibrationPrompt, "Long absence should trigger recalibration prompt")
    }

    /// dismissRecalibrationPrompt clears the prompt flag.
    func test_dismissRecalibrationPrompt_clearsFlag() async throws {
        let mock = MockPoseProvider()
        var thresholds = PostureThresholds()
        thresholds.absentThreshold = 0.3
        thresholds.absentResumeThreshold = 2.0
        thresholds.returnValidationWindow = 0.2
        let pipeline = Pipeline(provider: mock, thresholds: thresholds)
        pipeline.baseline = Self.makeBaseline()
        try await mock.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        let t = Date().timeIntervalSince1970
        try await emitAndWait(mock, sample: Self.goodSample(at: t))
        for i in 1...5 {
            try await emitAndWait(mock, sample: Self.lostSample(at: t + Double(i) * 0.1), waitNanos: 20_000_000)
        }
        for i in 0...5 {
            try await emitAndWait(mock, sample: Self.goodSample(at: t + 5.0 + Double(i) * 0.1), waitNanos: 20_000_000)
        }

        pipeline.dismissRecalibrationPrompt()
        XCTAssertFalse(pipeline.showRecalibrationPrompt, "Prompt should be cleared after dismiss")
    }
}

// MARK: - Mock Recorder

private final class MockRecorder: RecorderServiceProtocol {
    var recordedSamples: [PoseSample] = []
    var isRecording: Bool = true
    var sampleCount: Int { recordedSamples.count }

    @discardableResult
    func startRecording(metadata: SessionMetadata) -> Bool {
        isRecording = true
        return true
    }

    func record(sample: PoseSample) {
        recordedSamples.append(sample)
    }

    func addTag(_ tag: Tag) {}

    func stopRecording() -> RecordedSession? {
        isRecording = false
        return nil
    }
}
