import XCTest
import simd
@testable import PostureLogic

/// Jev Step 3a: a manual `Tag` is only useful if its timestamp can be compared against the
/// sample stream it annotates. Samples carry the camera frame clock (`PoseSample.timestamp`
/// comes from `frame.timestamp`), which is not wall-clock, so a tag stamped with
/// `Date()` would not align with anything. Tagging against the most recent recorded sample
/// makes alignment correct by construction, whatever clock the frames use.
final class RecorderTagAlignmentTests: XCTestCase {

    private func makeMetadata() -> SessionMetadata {
        SessionMetadata(deviceModel: "TestDevice", depthAvailable: true, thresholds: PostureThresholds())
    }

    private func makeSample(timestamp: TimeInterval) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.5, 0.8, 0),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            leftShoulder: SIMD3<Float>(0.4, 0.6, 0),
            rightShoulder: SIMD3<Float>(0.6, 0.6, 0),
            torsoAngle: 5,
            headForwardOffset: 0.02,
            shoulderTwist: 1,
            shoulderWidthRaw: 0.2,
            trackingQuality: .good
        )
    }

    func test_lastSampleTimestamp_isNilBeforeAnySampleIsRecorded() {
        let recorder = RecorderService()
        recorder.startRecording(metadata: makeMetadata())

        XCTAssertNil(recorder.lastSampleTimestamp)
    }

    func test_lastSampleTimestamp_tracksTheMostRecentlyRecordedSample() {
        let recorder = RecorderService()
        recorder.startRecording(metadata: makeMetadata())

        recorder.record(sample: makeSample(timestamp: 10))
        recorder.record(sample: makeSample(timestamp: 20.5))

        XCTAssertEqual(recorder.lastSampleTimestamp, 20.5)
    }

    func test_lastSampleTimestamp_resetsWhenRecordingStops() {
        let recorder = RecorderService()
        recorder.startRecording(metadata: makeMetadata())
        recorder.record(sample: makeSample(timestamp: 10))

        _ = recorder.stopRecording()

        XCTAssertNil(recorder.lastSampleTimestamp)
    }
}

/// The debug-HUD tagging control offers every posture label, so the enum must enumerate
/// itself — a new case should reach the UI without anyone remembering to add a button.
final class TagLabelCasesTests: XCTestCase {

    func test_tagLabel_enumeratesEveryCase() {
        XCTAssertEqual(
            Set(TagLabel.allCases),
            Set([.goodPosture, .slouching, .reading, .typing, .stretching, .absent])
        )
    }
}
