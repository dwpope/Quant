import XCTest
import simd
@testable import PostureLogic

/// Replay-based regression tests using synthetic golden recordings.
///
/// Each test loads a golden recording, feeds samples through
/// MetricsEngine → PostureEngine, and asserts expected state transitions.
final class GoldenRecordingTests: XCTestCase {

    // MARK: - Helpers

    /// Feeds all samples through the metrics + posture engines and returns
    /// the posture state after each sample.
    private func replaySession(
        _ session: RecordedSession,
        baseline: Baseline,
        thresholds: PostureThresholds = PostureThresholds(),
        taskMode: TaskMode = .unknown
    ) -> [PostureState] {
        var metricsEngine = MetricsEngine()
        let postureEngine = PostureEngine(thresholds: thresholds)
        var states: [PostureState] = []

        for sample in session.samples {
            let metrics = metricsEngine.compute(from: sample, baseline: baseline)
            let state = postureEngine.update(
                metrics: metrics,
                taskMode: taskMode,
                trackingQuality: sample.trackingQuality
            )
            states.append(state)
        }

        return states
    }

    /// Feeds samples with per-sample task modes through the engines.
    private func replaySessionWithModes(
        _ session: RecordedSession,
        baseline: Baseline,
        thresholds: PostureThresholds = PostureThresholds(),
        taskModes: [TaskMode]
    ) -> [PostureState] {
        var metricsEngine = MetricsEngine()
        let postureEngine = PostureEngine(thresholds: thresholds)
        var states: [PostureState] = []

        for (i, sample) in session.samples.enumerated() {
            let mode = i < taskModes.count ? taskModes[i] : .unknown
            let metrics = metricsEngine.compute(from: sample, baseline: baseline)
            let state = postureEngine.update(
                metrics: metrics,
                taskMode: mode,
                trackingQuality: sample.trackingQuality
            )
            states.append(state)
        }

        return states
    }

    // MARK: - 1. Good Posture

    func test_goodPosture_staysGoodThroughout() {
        let session = GoldenRecordings.goodPosture()
        let baseline = GoldenRecordings.baselineForGoodPosture()
        let states = replaySession(session, baseline: baseline)

        // First frame transitions from absent → good, then stays good
        XCTAssertEqual(states.count, 30)
        for (i, state) in states.enumerated() {
            XCTAssertEqual(state, .good, "Sample \(i) should be .good")
        }
    }

    // MARK: - 2. Gradual Slouch

    func test_gradualSlouch_transitionsToGoodThenDriftingThenBad() {
        let session = GoldenRecordings.gradualSlouch()
        let baseline = GoldenRecordings.baselineForGoodPosture()

        // Use short drifting threshold so the 50-sample session can reach .bad
        // At 0.1s intervals, 50 samples = 5s total. Set threshold to 1.5s.
        var thresholds = PostureThresholds()
        thresholds.driftingToBadThreshold = 1.5

        let states = replaySession(session, baseline: baseline, thresholds: thresholds)

        XCTAssertEqual(states.count, 50)

        // Phase 1 (samples 0-14): good posture — all should be .good
        for i in 0..<15 {
            XCTAssertEqual(states[i], .good, "Sample \(i) (good phase) should be .good")
        }

        // Phase 2 (samples 15-34): gradual degradation
        // At some point during this phase, metrics should cross thresholds → drifting
        let firstDrifting = states.firstIndex { state in
            if case .drifting = state { return true }
            return false
        }
        XCTAssertNotNil(firstDrifting, "Should enter .drifting at some point during degradation")
        if let idx = firstDrifting {
            XCTAssertGreaterThanOrEqual(idx, 15, "Drifting should not start during good phase")
        }

        // Phase 3 (samples 35-49): sustained bad posture
        // With driftingToBadThreshold=1.5s and 0.1s intervals, after 15+ samples
        // of bad metrics the engine should reach .bad
        let lastState = states.last!
        XCTAssertTrue(lastState.isBad, "Final state should be .bad after sustained slouch")

        // Verify we saw the full progression: good → drifting → bad
        let sawGood = states.contains(.good)
        let sawDrifting = states.contains { state in
            if case .drifting = state { return true }
            return false
        }
        let sawBad = states.contains { state in state.isBad }
        XCTAssertTrue(sawGood, "Should have seen .good state")
        XCTAssertTrue(sawDrifting, "Should have seen .drifting state")
        XCTAssertTrue(sawBad, "Should have seen .bad state")
    }

    // MARK: - 3. Reading vs Typing

    func test_readingVsTyping_staysGoodWithAppropriateTaskModes() {
        let session = GoldenRecordings.readingVsTyping()
        let baseline = GoldenRecordings.baselineForGoodPosture()

        // Build per-sample task modes matching the recording's alternating blocks
        let taskModes: [TaskMode] = (0..<40).map { i in
            let phase = i / 10
            return phase % 2 == 0 ? .reading : .typing
        }

        let states = replaySessionWithModes(
            session,
            baseline: baseline,
            taskModes: taskModes
        )

        XCTAssertEqual(states.count, 40)

        // All samples should remain .good because:
        // - Reading blocks: slight forward lean is within reading-mode relaxed thresholds
        // - Typing blocks: slight twist is well within thresholds
        for (i, state) in states.enumerated() {
            XCTAssertEqual(state, .good,
                "Sample \(i) should be .good (mode: \(taskModes[i]))")
        }
    }

    func test_readingVsTyping_hasTags() {
        let session = GoldenRecordings.readingVsTyping()

        XCTAssertEqual(session.tags.count, 4)
        XCTAssertEqual(session.tags[0].label, .reading)
        XCTAssertEqual(session.tags[1].label, .typing)
        XCTAssertEqual(session.tags[2].label, .reading)
        XCTAssertEqual(session.tags[3].label, .typing)
    }

    // MARK: - 4. Depth Fallback

    func test_depthFallback_staysGoodDespiteModeSwitch() {
        let session = GoldenRecordings.depthFallback()
        let baseline = GoldenRecordings.baselineForGoodPosture()
        let states = replaySession(session, baseline: baseline)

        XCTAssertEqual(states.count, 40)

        // Verify the recording has both depth modes
        let depthFusionSamples = session.samples.filter { $0.depthMode == .depthFusion }
        let twoDOnlySamples = session.samples.filter { $0.depthMode == .twoDOnly }
        XCTAssertEqual(depthFusionSamples.count, 20)
        XCTAssertEqual(twoDOnlySamples.count, 20)

        // All samples should stay .good — mode switch shouldn't cause false degradation
        for (i, state) in states.enumerated() {
            XCTAssertEqual(state, .good,
                "Sample \(i) should be .good (mode switch should not cause false bad posture)")
        }
    }

    func test_depthFallback_metadataIndicatesDepthAvailable() {
        let session = GoldenRecordings.depthFallback()
        XCTAssertTrue(session.metadata.depthAvailable)
    }

    // MARK: - ReplayService Integration

    func test_replayService_canLoadAndPlayGoldenRecording() async {
        let session = GoldenRecordings.goodPosture()
        let service = ReplayService()
        service.load(session: session)

        XCTAssertTrue(service.isLoaded)

        service.playbackSpeed = 100.0  // Fast playback for testing
        guard let stream = service.play() else {
            XCTFail("play() should return a stream after load")
            return
        }

        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
        }

        XCTAssertEqual(receivedCount, session.samples.count,
            "Should receive all samples from the recording")
    }

    // MARK: - Recording Structure Validation

    func test_allRecordings_haveSamplesAtExpectedIntervals() {
        let sessions = [
            ("goodPosture", GoldenRecordings.goodPosture()),
            ("gradualSlouch", GoldenRecordings.gradualSlouch()),
            ("readingVsTyping", GoldenRecordings.readingVsTyping()),
            ("depthFallback", GoldenRecordings.depthFallback()),
        ]

        for (name, session) in sessions {
            XCTAssertGreaterThanOrEqual(session.samples.count, 20,
                "\(name) should have at least 20 samples")

            // Verify timestamps are monotonically increasing
            for i in 1..<session.samples.count {
                let prev = session.samples[i - 1].timestamp
                let curr = session.samples[i].timestamp
                XCTAssertGreaterThan(curr, prev,
                    "\(name) sample \(i) timestamp should be > sample \(i-1)")
            }

            // Verify ~0.1s interval (allow some tolerance)
            if session.samples.count >= 2 {
                let firstInterval = session.samples[1].timestamp - session.samples[0].timestamp
                XCTAssertEqual(firstInterval, 0.1, accuracy: 0.01,
                    "\(name) should have ~0.1s sample interval")
            }
        }
    }
}
