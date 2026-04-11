import CoreGraphics
import XCTest
@testable import PostureLogic

/// Tests for `SipTrainingBuffer` — the 3-second rolling pose window used
/// by the training-mode labeling workflow.
final class SipTrainingBufferTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a `PoseObservation` containing every joint in `Joint.allCases`
    /// so we can verify the keypoint filter actually strips irrelevant ones.
    private func makeObservation(at t: TimeInterval) -> PoseObservation {
        let keypoints = Joint.allCases.map { joint in
            Keypoint(joint: joint, position: .zero, confidence: 1.0)
        }
        return PoseObservation(timestamp: t, keypoints: keypoints, confidence: 1.0)
    }

    // MARK: - Ingest & filter

    func test_process_retainsOnlyRelevantJoints() {
        let buffer = SipTrainingBuffer()
        buffer.process(makeObservation(at: 1.0))

        XCTAssertEqual(buffer.frames.count, 1)
        let retained = Set(buffer.frames[0].keypoints.map(\.joint))
        XCTAssertEqual(retained, SipTrainingBuffer.relevantJoints)

        // And nothing else sneaks in.
        XCTAssertFalse(retained.contains(.leftHip))
        XCTAssertFalse(retained.contains(.leftKnee))
        XCTAssertFalse(retained.contains(.leftAnkle))
        XCTAssertFalse(retained.contains(.leftEar))
    }

    func test_process_preservesTimestamp() {
        let buffer = SipTrainingBuffer()
        buffer.process(makeObservation(at: 42.5))

        XCTAssertEqual(buffer.frames.count, 1)
        XCTAssertEqual(buffer.frames[0].timestamp, 42.5)
    }

    // MARK: - Window trimming

    func test_windowTrimming_dropsFramesOlderThanWindow() {
        let buffer = SipTrainingBuffer(windowSeconds: 3.0)

        // Five frames at t=0..4 seconds.
        for i in 0..<5 {
            buffer.process(makeObservation(at: TimeInterval(i)))
        }

        // Newest frame is t=4, cutoff is 4 - 3 = 1. Frames with t < 1 go.
        // That drops only t=0. (t=1 is at the cutoff and kept.)
        XCTAssertEqual(buffer.frames.count, 4)
        XCTAssertEqual(buffer.frames.first?.timestamp, 1.0)
        XCTAssertEqual(buffer.frames.last?.timestamp, 4.0)
    }

    func test_windowTrimming_withDenseStream_retainsOnlyRecentThreeSeconds() {
        let buffer = SipTrainingBuffer(windowSeconds: 3.0)

        // 60 frames at 500ms spacing = 30 seconds of data.
        // 0.5 is exact in binary Double, so no FP drift at the window
        // boundary and the expected count is deterministic.
        for i in 0..<60 {
            buffer.process(makeObservation(at: TimeInterval(i) * 0.5))
        }

        // Newest timestamp = 29.5, cutoff = 26.5. Frames with t >= 26.5
        // are kept: 26.5, 27.0, 27.5, 28.0, 28.5, 29.0, 29.5 = 7 frames.
        XCTAssertEqual(buffer.frames.count, 7)
        XCTAssertEqual(buffer.frames.first?.timestamp, 26.5)
        XCTAssertEqual(buffer.frames.last?.timestamp, 29.5)
    }

    func test_windowTrimming_withWideWindow_retainsEverything() {
        let buffer = SipTrainingBuffer(windowSeconds: 10.0)

        for i in 0..<5 {
            buffer.process(makeObservation(at: TimeInterval(i)))
        }

        XCTAssertEqual(buffer.frames.count, 5)
    }

    // MARK: - snapshot() detachment

    func test_snapshot_returnsDetachedCopy() {
        let buffer = SipTrainingBuffer()
        buffer.process(makeObservation(at: 1.0))
        buffer.process(makeObservation(at: 2.0))

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.count, 2)

        // Add more frames after snapshotting — snapshot must not change.
        buffer.process(makeObservation(at: 3.0))
        buffer.process(makeObservation(at: 4.0))

        XCTAssertEqual(snapshot.count, 2,
                       "snapshot should be a detached value copy")
        XCTAssertEqual(snapshot.map(\.timestamp), [1.0, 2.0])
    }

    // MARK: - reset()

    func test_reset_clearsBuffer() {
        let buffer = SipTrainingBuffer()
        for i in 0..<3 {
            buffer.process(makeObservation(at: TimeInterval(i)))
        }
        XCTAssertEqual(buffer.frames.count, 3)

        buffer.reset()

        XCTAssertTrue(buffer.frames.isEmpty)
    }

    func test_reset_allowsSubsequentProcessingToWorkNormally() {
        let buffer = SipTrainingBuffer()
        buffer.process(makeObservation(at: 1.0))
        buffer.reset()
        buffer.process(makeObservation(at: 100.0))

        XCTAssertEqual(buffer.frames.count, 1)
        XCTAssertEqual(buffer.frames.first?.timestamp, 100.0)
    }

    // MARK: - relevantJoints (public constant)

    func test_relevantJoints_matchesExpectedNineJoints() {
        XCTAssertEqual(SipTrainingBuffer.relevantJoints.count, 9)
        XCTAssertTrue(SipTrainingBuffer.relevantJoints.contains(.nose))
        XCTAssertTrue(SipTrainingBuffer.relevantJoints.contains(.leftWrist))
        XCTAssertTrue(SipTrainingBuffer.relevantJoints.contains(.rightWrist))
        XCTAssertTrue(SipTrainingBuffer.relevantJoints.contains(.leftShoulder))
        XCTAssertTrue(SipTrainingBuffer.relevantJoints.contains(.rightShoulder))
    }

    // MARK: - SipDetector.scoresSnapshot accessor smoke test
    //
    // Verifies the additive accessor is callable and returns a `Scores`
    // value with the expected zero-initialised shape before any frames
    // have been processed. Doesn't exercise detection logic (covered by
    // existing SipDetectorTests).

    func test_sipDetector_scoresSnapshot_initialValues() {
        let detector = SipDetector()
        let snapshot = detector.scoresSnapshot

        XCTAssertEqual(snapshot.proximity, 0)
        XCTAssertEqual(snapshot.velocity, 0)
        XCTAssertEqual(snapshot.duration, 0)
        XCTAssertNil(snapshot.activeWrist, "no active wrist when idle")
    }
}
