import XCTest
@testable import PostureLogic

final class ReplayServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetadata() -> SessionMetadata {
        SessionMetadata(
            deviceModel: "TestDevice",
            depthAvailable: true,
            thresholds: PostureThresholds()
        )
    }

    private func makeSample(timestamp: TimeInterval = 0) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.8, 0),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            leftShoulder: SIMD3<Float>(0.4, 0.6, 0),
            rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
            torsoAngle: 5.0,
            headForwardOffset: 0.02,
            shoulderTwist: 1.0,
            shoulderWidthRaw: 0.2,
            trackingQuality: .good
        )
    }

    private func makeSession(sampleCount: Int = 3, intervalSeconds: TimeInterval = 0.1) -> RecordedSession {
        let samples = (0..<sampleCount).map { i in
            makeSample(timestamp: Double(i) * intervalSeconds)
        }
        return RecordedSession(
            id: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(Double(sampleCount) * intervalSeconds),
            samples: samples,
            tags: [],
            metadata: makeMetadata()
        )
    }

    // MARK: - Init

    func test_init_notLoadedNotPlaying() {
        let service = ReplayService()
        XCTAssertFalse(service.isLoaded)
        XCTAssertFalse(service.isPlaying)
    }

    func test_init_defaultPlaybackSpeed() {
        let service = ReplayService()
        XCTAssertEqual(service.playbackSpeed, 1.0)
    }

    // MARK: - Load

    func test_load_setsIsLoaded() {
        let service = ReplayService()
        service.load(session: makeSession())
        XCTAssertTrue(service.isLoaded)
    }

    func test_load_replacesSession() {
        let service = ReplayService()
        let session1 = makeSession(sampleCount: 2)
        let session2 = makeSession(sampleCount: 5)

        service.load(session: session1)
        service.load(session: session2)

        XCTAssertTrue(service.isLoaded)
        // Verify by checking debugState
        XCTAssertEqual(service.debugState["sampleCount"] as? Int, 5)
    }

    // MARK: - Play

    func test_play_beforeLoad_returnsNil() {
        let service = ReplayService()
        XCTAssertNil(service.play())
    }

    func test_play_yieldsAllSamples() async {
        let service = ReplayService()
        service.playbackSpeed = 100.0 // Fast for testing
        service.load(session: makeSession(sampleCount: 5))

        guard let stream = service.play() else {
            return XCTFail("play() should return a stream")
        }

        var received: [PoseSample] = []
        for await sample in stream {
            received.append(sample)
        }

        XCTAssertEqual(received.count, 5)
    }

    func test_play_yieldsInOrder() async {
        let service = ReplayService()
        service.playbackSpeed = 100.0
        service.load(session: makeSession(sampleCount: 4, intervalSeconds: 0.1))

        guard let stream = service.play() else {
            return XCTFail("play() should return a stream")
        }

        var timestamps: [TimeInterval] = []
        for await sample in stream {
            timestamps.append(sample.timestamp)
        }

        XCTAssertEqual(timestamps.count, 4)
        for (actual, expected) in zip(timestamps, [0.0, 0.1, 0.2, 0.3]) {
            XCTAssertEqual(actual, expected, accuracy: 1e-9)
        }
    }

    func test_play_emptySession_returnsEmptyStream() async {
        let service = ReplayService()
        service.load(session: makeSession(sampleCount: 0))

        guard let stream = service.play() else {
            return XCTFail("play() should return a stream for empty session")
        }

        var count = 0
        for await _ in stream {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    func test_play_whilePlaying_returnsNil() async {
        let service = ReplayService()
        service.playbackSpeed = 0.01 // Very slow so playback doesn't finish
        service.load(session: makeSession(sampleCount: 100, intervalSeconds: 1.0))

        let stream1 = service.play()
        XCTAssertNotNil(stream1)

        // Read one sample to ensure playback is active
        if let stream1 {
            var iterator = stream1.makeAsyncIterator()
            _ = await iterator.next()
        }

        // Second play while still playing should return nil
        let stream2 = service.play()
        XCTAssertNil(stream2)

        service.stop()
    }

    // MARK: - Stop

    func test_stop_endsPlayback() async {
        let service = ReplayService()
        service.playbackSpeed = 0.001 // Very slow
        service.load(session: makeSession(sampleCount: 100, intervalSeconds: 1.0))

        guard let stream = service.play() else {
            return XCTFail("play() should return a stream")
        }

        // Read one sample
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        XCTAssertTrue(service.isPlaying)

        // Stop should cancel
        service.stop()
        XCTAssertFalse(service.isPlaying)
    }

    func test_stop_whenNotPlaying_isNoop() {
        let service = ReplayService()
        service.stop() // Should not crash
        XCTAssertFalse(service.isPlaying)
    }

    // MARK: - Replay after stop

    func test_replayAfterStop() async {
        let service = ReplayService()
        service.playbackSpeed = 100.0
        let session = makeSession(sampleCount: 3)
        service.load(session: session)

        // First play
        guard let stream1 = service.play() else {
            return XCTFail("First play() should return a stream")
        }

        var count1 = 0
        for await _ in stream1 {
            count1 += 1
        }
        XCTAssertEqual(count1, 3)

        // After stream completes, isPlaying should be false
        // Give a moment for the defer to execute
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        XCTAssertFalse(service.isPlaying)

        // Second play should work
        guard let stream2 = service.play() else {
            return XCTFail("Second play() should return a stream")
        }

        var count2 = 0
        for await _ in stream2 {
            count2 += 1
        }
        XCTAssertEqual(count2, 3)
    }

    // MARK: - Playback speed

    func test_playbackSpeed_canBeChanged() {
        let service = ReplayService()
        service.playbackSpeed = 2.0
        XCTAssertEqual(service.playbackSpeed, 2.0)

        service.playbackSpeed = 10.0
        XCTAssertEqual(service.playbackSpeed, 10.0)
    }

    func test_playback_fasterAtHigherSpeed() async {
        let service = ReplayService()
        // 3 samples with 50ms intervals = 100ms total delay at 1x
        let session = makeSession(sampleCount: 3, intervalSeconds: 0.05)

        // Play at 1x
        service.load(session: session)
        service.playbackSpeed = 1.0
        let start1x = ContinuousClock.now
        if let stream = service.play() {
            for await _ in stream {}
        }
        let elapsed1x = ContinuousClock.now - start1x

        // Give defer time to reset
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Play at 10x
        service.load(session: session)
        service.playbackSpeed = 10.0
        let start10x = ContinuousClock.now
        if let stream = service.play() {
            for await _ in stream {}
        }
        let elapsed10x = ContinuousClock.now - start10x

        // 10x should be noticeably faster (at least 3x faster to account for overhead)
        XCTAssertLessThan(elapsed10x, elapsed1x / 3)
    }

    // MARK: - DebugDumpable

    func test_debugState_reflectsState() {
        let service = ReplayService()

        let idleState = service.debugState
        XCTAssertEqual(idleState["isLoaded"] as? Bool, false)
        XCTAssertEqual(idleState["isPlaying"] as? Bool, false)
        XCTAssertEqual(idleState["playbackSpeed"] as? Double, 1.0)
        XCTAssertNil(idleState["sessionID"])

        let session = makeSession()
        service.load(session: session)

        let loadedState = service.debugState
        XCTAssertEqual(loadedState["isLoaded"] as? Bool, true)
        XCTAssertEqual(loadedState["sampleCount"] as? Int, 3)
        XCTAssertNotNil(loadedState["sessionID"])
    }

    // MARK: - Load stops active playback

    func test_load_stopsActivePlayback() async {
        let service = ReplayService()
        service.playbackSpeed = 0.001 // Very slow
        service.load(session: makeSession(sampleCount: 100, intervalSeconds: 1.0))

        _ = service.play()
        // Give playback a moment to start
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Loading a new session should stop playback
        service.load(session: makeSession(sampleCount: 2))
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.debugState["sampleCount"] as? Int, 2)
    }
}
