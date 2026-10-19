import XCTest
import Combine
@testable import PostureLogic

final class ReplayPoseProviderTests: XCTestCase {

    func test_start_emitsPrecomputedFrames() async throws {
        let session = GoldenRecordings.goodPosture()
        let replayService = ReplayService()
        replayService.playbackSpeed = 100.0  // Fast playback for tests
        replayService.load(session: session)

        let provider = ReplayPoseProvider(replayService: replayService)

        var receivedFrames: [InputFrame] = []
        let expectation = XCTestExpectation(description: "frames received")

        let cancellable = provider.framePublisher
            .sink { frame in
                receivedFrames.append(frame)
                if receivedFrames.count == session.samples.count {
                    expectation.fulfill()
                }
            }

        try await provider.start()
        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()

        XCTAssertEqual(receivedFrames.count, session.samples.count)

        // Every frame should have a precomputedSample and no pixelBuffer
        for (i, frame) in receivedFrames.enumerated() {
            XCTAssertNotNil(frame.precomputedSample, "Frame \(i) missing precomputedSample")
            XCTAssertNil(frame.pixelBuffer, "Frame \(i) should have nil pixelBuffer")
            XCTAssertEqual(frame.precomputedSample?.timestamp, session.samples[i].timestamp)
        }
    }

    func test_stop_cancelsPlayback() async throws {
        let session = GoldenRecordings.goodPosture()
        let replayService = ReplayService()
        replayService.playbackSpeed = 0.1  // Very slow so we can stop mid-stream
        replayService.load(session: session)

        let provider = ReplayPoseProvider(replayService: replayService)

        var receivedCount = 0
        let firstFrameExpectation = XCTestExpectation(description: "first frame received")

        let cancellable = provider.framePublisher
            .sink { _ in
                receivedCount += 1
                if receivedCount == 1 {
                    firstFrameExpectation.fulfill()
                }
            }

        try await provider.start()
        await fulfillment(of: [firstFrameExpectation], timeout: 5.0)

        provider.stop()
        let countAfterStop = receivedCount

        // Wait a bit to confirm no more frames arrive
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        XCTAssertEqual(receivedCount, countAfterStop, "No frames should arrive after stop()")
        XCTAssertLessThan(receivedCount, session.samples.count, "Should not have received all frames")
        cancellable.cancel()
    }

    /// `start()` returns once playback begins; `finished()` once it has ended (2026-10-19). The
    /// app took `start()` returning for the end of the replay.
    func test_finished_returnsOnceEveryFrameIsSent() async throws {
        let session = GoldenRecordings.goodPosture()
        let replayService = ReplayService()
        replayService.playbackSpeed = 100.0
        replayService.load(session: session)
        let provider = ReplayPoseProvider(replayService: replayService)
        var received = 0
        let cancellable = provider.framePublisher.sink { _ in received += 1 }

        try await provider.start()
        XCTAssertLessThan(received, session.samples.count, "playing, not played")
        await provider.finished()
        cancellable.cancel()
        XCTAssertEqual(received, session.samples.count)
    }

    func test_finished_returnsWhenStopped() async throws {
        let session = GoldenRecordings.goodPosture()
        let replayService = ReplayService()
        replayService.playbackSpeed = 0.1
        replayService.load(session: session)
        let provider = ReplayPoseProvider(replayService: replayService)

        try await provider.start()
        provider.stop()
        await provider.finished()
    }

    func test_framePublisher_isAnyPublisher() {
        let replayService = ReplayService()
        let provider = ReplayPoseProvider(replayService: replayService)
        // Verify it conforms to PoseProvider
        let _: AnyPublisher<InputFrame, Never> = provider.framePublisher
    }
}
