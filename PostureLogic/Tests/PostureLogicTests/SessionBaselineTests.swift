import XCTest
import simd
@testable import PostureLogic

/// Jev Step 3a: a recorded session is only replayable against the threshold engine if it
/// carries the `Baseline` that was live when it was captured.
///
/// Every `RawMetrics` field is a baseline-relative delta, so "what would the thresholds have
/// said about this sample?" is unanswerable without the baseline. And the baseline cannot be
/// recovered after the fact: it lives in a single UserDefaults key, is wiped on recalibration,
/// and goes stale after an hour. A session recorded without it is permanently un-evaluable,
/// which is why this is captured at record time rather than added later.
final class SessionBaselineTests: XCTestCase {

    private func makeBaseline() -> Baseline {
        Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            headPosition: SIMD3<Float>(0.5, 0.8, 0),
            torsoAngle: 3,
            shoulderTwist: 1,
            shoulderWidth: 0.2,
            depthAvailable: true,
            neckHeight: 0.35
        )
    }

    func test_sessionMetadata_carriesTheBaselineItWasRecordedAgainst() {
        let baseline = makeBaseline()

        let metadata = SessionMetadata(
            deviceModel: "TestDevice",
            depthAvailable: true,
            thresholds: PostureThresholds(),
            baseline: baseline
        )

        XCTAssertEqual(metadata.baseline?.shoulderWidth, baseline.shoulderWidth)
        XCTAssertEqual(metadata.baseline?.neckHeight, baseline.neckHeight)
    }

    func test_sessionMetadata_baselineRoundTripsThroughCodable() throws {
        let metadata = SessionMetadata(
            deviceModel: "TestDevice",
            depthAvailable: false,
            thresholds: PostureThresholds(),
            baseline: makeBaseline()
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(SessionMetadata.self, from: data)

        XCTAssertEqual(decoded.baseline?.torsoAngle, 3)
        XCTAssertEqual(decoded.baseline?.neckHeight, 0.35)
        XCTAssertEqual(decoded.baseline?.shoulderWidth, 0.2)
    }

    /// Additive-field convention, as with `Baseline.shoulderTwist` and `neckHeight`: a
    /// session persisted before this field existed must still decode, and a session with no
    /// baseline must not write the key, so old and new files share one shape.
    func test_sessionMetadata_withoutBaseline_omitsTheKeyAndStillDecodes() throws {
        let metadata = SessionMetadata(
            deviceModel: "OldDevice",
            depthAvailable: true,
            thresholds: PostureThresholds()
        )

        let data = try JSONEncoder().encode(metadata)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("baseline"), "a nil baseline must not be encoded")

        let decoded = try JSONDecoder().decode(SessionMetadata.self, from: data)
        XCTAssertNil(decoded.baseline)
    }

    func test_recorder_carriesTheBaselineIntoTheStoppedSession() {
        let recorder = RecorderService()
        let baseline = makeBaseline()

        recorder.startRecording(metadata: SessionMetadata(
            deviceModel: "TestDevice",
            depthAvailable: true,
            thresholds: PostureThresholds(),
            baseline: baseline
        ))
        let session = recorder.stopRecording()

        XCTAssertEqual(session?.metadata.baseline?.shoulderWidth, baseline.shoulderWidth)
    }
}
