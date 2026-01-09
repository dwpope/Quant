import XCTest
import Foundation
@testable import PostureLogic

final class ReplayServiceTests: XCTestCase {

    // MARK: - Initial State Tests

    func test_initialState_isNotPlaying() {
        let replay = ReplayService()

        XCTAssertFalse(replay.isPlaying)
        XCTAssertEqual(replay.progress, 0.0)
    }

    // MARK: - Load Tests

    func test_load_storesSession() {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 5)

        replay.load(session: session)

        let debugState = replay.debugState
        XCTAssertEqual(debugState["samplesLoaded"] as? Int, 5)
    }

    func test_load_resetsProgress() {
        var replay = ReplayService()

        let session = createMockSession(sampleCount: 5)
        replay.load(session: session)

        XCTAssertEqual(replay.progress, 0.0)
    }

    // MARK: - Playback Tests

    func test_play_emitsAllSamples() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 5)
        replay.load(session: session)

        var receivedSamples: [PoseSample] = []

        for await sample in replay.play() {
            receivedSamples.append(sample)
        }

        XCTAssertEqual(receivedSamples.count, 5)
    }

    func test_play_emitsSamplesInOrder() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 10)
        replay.load(session: session)

        var receivedSamples: [PoseSample] = []

        for await sample in replay.play() {
            receivedSamples.append(sample)
        }

        for i in 0..<10 {
            XCTAssertEqual(receivedSamples[i].timestamp, TimeInterval(i))
        }
    }

    func test_play_respectsTimestampDelays() async {
        var replay = ReplayService()

        // Create samples with 0.1 second spacing
        var samples: [PoseSample] = []
        for i in 0..<3 {
            samples.append(createMockSample(timestamp: TimeInterval(i) * 0.1))
        }

        let session = createMockSessionWithSamples(samples)
        replay.load(session: session)

        let startTime = Date()
        var receivedCount = 0

        for await _ in replay.play() {
            receivedCount += 1
        }

        let duration = Date().timeIntervalSince(startTime)

        // Should take ~0.2 seconds (3 samples with 0.1s spacing)
        // Allow some tolerance for timing variations
        XCTAssertGreaterThan(duration, 0.15, "Playback should respect timestamp delays")
        XCTAssertLessThan(duration, 0.35, "Playback should not be too slow")
        XCTAssertEqual(receivedCount, 3)
    }

    func test_play_withEmptySession_finishesImmediately() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 0)
        replay.load(session: session)

        var receivedSamples: [PoseSample] = []

        for await sample in replay.play() {
            receivedSamples.append(sample)
        }

        XCTAssertEqual(receivedSamples.count, 0)
    }

    // MARK: - Speed Control Tests

    func test_setSpeed_changesPlaybackSpeed() async {
        var replay = ReplayService()
        replay.setSpeed(10.0)  // 10x speed

        // Create samples with 0.1 second spacing
        var samples: [PoseSample] = []
        for i in 0..<3 {
            samples.append(createMockSample(timestamp: TimeInterval(i) * 0.1))
        }

        let session = createMockSessionWithSamples(samples)
        replay.load(session: session)

        let startTime = Date()
        var receivedCount = 0

        for await _ in replay.play() {
            receivedCount += 1
        }

        let duration = Date().timeIntervalSince(startTime)

        // At 10x speed, should take ~0.02 seconds
        XCTAssertLessThan(duration, 0.1, "10x speed should be significantly faster")
        XCTAssertEqual(receivedCount, 3)
    }

    func test_setSpeed_clampsToReasonableRange() {
        var replay = ReplayService()

        replay.setSpeed(-1.0)
        let debugState1 = replay.debugState
        XCTAssertGreaterThanOrEqual(debugState1["playbackSpeed"] as? Float ?? 0, 0.1)

        replay.setSpeed(1000.0)
        let debugState2 = replay.debugState
        XCTAssertLessThanOrEqual(debugState2["playbackSpeed"] as? Float ?? 0, 100.0)
    }

    // MARK: - Stop Tests

    func test_stop_haltsPlayback() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 100)
        replay.load(session: session)

        var receivedCount = 0

        let playTask = Task {
            for await _ in replay.play() {
                receivedCount += 1
                if receivedCount == 5 {
                    replay.stop()
                }
            }
        }

        await playTask.value

        XCTAssertLessThan(receivedCount, 100, "Should stop before all samples")
        XCTAssertFalse(replay.isPlaying)
    }

    // MARK: - Progress Tests

    func test_progress_updatesduringPlayback() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 10)
        replay.load(session: session)

        var progressValues: [Float] = []

        for await _ in replay.play() {
            progressValues.append(replay.progress)
        }

        // Progress should increase
        XCTAssertGreaterThan(progressValues.count, 0)
        XCTAssertLessThanOrEqual(progressValues.first ?? 0, 0.2)  // Early progress
        XCTAssertGreaterThanOrEqual(progressValues.last ?? 0, 0.9)  // Late progress
        XCTAssertEqual(replay.progress, 1.0, accuracy: 0.01)  // Should be 1.0 at end
    }

    // MARK: - State Tests

    func test_isPlaying_trueWhilePlaying() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 5)
        replay.load(session: session)

        XCTAssertFalse(replay.isPlaying)

        let playTask = Task {
            var wasPlaying = false
            for await _ in replay.play() {
                if replay.isPlaying {
                    wasPlaying = true
                }
            }
            return wasPlaying
        }

        let wasPlaying = await playTask.value
        XCTAssertTrue(wasPlaying)
        XCTAssertFalse(replay.isPlaying)  // Should be false after completion
    }

    // MARK: - Debug State Tests

    func test_debugState_tracksPlaybackInfo() {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 10)
        replay.load(session: session)
        replay.setSpeed(2.0)

        let debugState = replay.debugState

        XCTAssertEqual(debugState["samplesLoaded"] as? Int, 10)
        XCTAssertEqual(debugState["playbackSpeed"] as? Float, 2.0)
        XCTAssertEqual(debugState["isPlaying"] as? Bool, false)
    }

    // MARK: - Duration Estimation Tests

    func test_estimatedDuration_calculatesCorrectly() {
        var replay = ReplayService()

        // Create session with samples from 0 to 10 seconds
        var samples: [PoseSample] = []
        samples.append(createMockSample(timestamp: 0.0))
        samples.append(createMockSample(timestamp: 10.0))

        let session = createMockSessionWithSamples(samples)
        replay.load(session: session)

        // At 1x speed, should be 10 seconds
        replay.setSpeed(1.0)
        XCTAssertNotNil(replay.estimatedDuration)
        XCTAssertEqual(replay.estimatedDuration!, 10.0, accuracy: 0.01)

        // At 2x speed, should be 5 seconds
        replay.setSpeed(2.0)
        XCTAssertEqual(replay.estimatedDuration!, 5.0, accuracy: 0.01)

        // At 10x speed, should be 1 second
        replay.setSpeed(10.0)
        XCTAssertEqual(replay.estimatedDuration!, 1.0, accuracy: 0.01)
    }

    // MARK: - Multiple Playback Tests

    func test_multiplePlaybacks_workIndependently() async {
        var replay = ReplayService()
        let session = createMockSession(sampleCount: 3)
        replay.load(session: session)

        // First playback
        var firstCount = 0
        for await _ in replay.play() {
            firstCount += 1
        }

        // Second playback
        var secondCount = 0
        for await _ in replay.play() {
            secondCount += 1
        }

        XCTAssertEqual(firstCount, 3)
        XCTAssertEqual(secondCount, 3)
    }

    // MARK: - No Session Tests

    func test_playWithoutLoadedSession_returnsEmptyStream() async {
        let replay = ReplayService()  // No session loaded

        var receivedCount = 0
        for await _ in replay.play() {
            receivedCount += 1
        }

        XCTAssertEqual(receivedCount, 0)
    }

    // MARK: - Helper Functions

    private func createMockSession(sampleCount: Int) -> RecordedSession {
        var samples: [PoseSample] = []
        for i in 0..<sampleCount {
            samples.append(createMockSample(timestamp: TimeInterval(i)))
        }

        return RecordedSession(
            id: UUID(),
            startTime: Date(),
            endTime: Date(),
            samples: samples,
            tags: [],
            metadata: SessionMetadata(
                deviceModel: "Test",
                depthAvailable: false,
                thresholds: PostureThresholds()
            )
        )
    }

    private func createMockSessionWithSamples(_ samples: [PoseSample]) -> RecordedSession {
        return RecordedSession(
            id: UUID(),
            startTime: Date(),
            endTime: Date(),
            samples: samples,
            tags: [],
            metadata: SessionMetadata(
                deviceModel: "Test",
                depthAvailable: false,
                thresholds: PostureThresholds()
            )
        )
    }

    private func createMockSample(timestamp: TimeInterval) -> PoseSample {
        return PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.3, 0.9),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.4, 1.0),
            leftShoulder: SIMD3<Float>(0.3, 0.4, 1.0),
            rightShoulder: SIMD3<Float>(0.7, 0.4, 1.0),
            torsoAngle: 5.0,
            headForwardOffset: 0.05,
            shoulderTwist: 2.0,
            trackingQuality: .good
        )
    }
}
