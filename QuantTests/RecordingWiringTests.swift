import XCTest
import PostureLogic
import simd
@testable import Quant

/// Jev Step 3a: the recorder, the baseline and manual labelling, wired end to end.
///
/// `AppModel.startRecording()`/`stopRecording()` existed but had no caller anywhere in the app,
/// and `addTag` was called only from tests — so every session the app could produce would have
/// arrived unlabelled and unreplayable. These tests pin the two things that make a recording
/// scientifically useful: it carries the baseline it was recorded against, and it can carry a
/// human label.
@MainActor
final class RecordingWiringTests: XCTestCase {

    private var exported: [URL] = []

    override func tearDownWithError() throws {
        for url in exported { try? FileManager.default.removeItem(at: url) }
        exported = []
    }

    private func makeBaseline() -> Baseline {
        Baseline(
            timestamp: Date(),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
            headPosition: SIMD3<Float>(0.5, 0.8, 0),
            torsoAngle: 4,
            shoulderTwist: 2,
            shoulderWidth: 0.23,
            depthAvailable: false,
            neckHeight: 0.31
        )
    }

    private func decodeSession(at url: URL) throws -> RecordedSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordedSession.self, from: try Data(contentsOf: url))
    }

    func test_startRecording_capturesTheLiveBaselineInSessionMetadata() throws {
        let model = AppModel()
        let baseline = makeBaseline()
        model.baseline = baseline

        model.startRecording()
        let url = try XCTUnwrap(model.stopRecording())
        exported.append(url)

        let session = try decodeSession(at: url)
        XCTAssertEqual(session.metadata.baseline?.shoulderWidth, baseline.shoulderWidth)
        XCTAssertEqual(session.metadata.baseline?.neckHeight, baseline.neckHeight)
    }

    func test_startRecording_withoutABaseline_recordsNoBaseline() throws {
        let model = AppModel()
        model.baseline = nil

        model.startRecording()
        let url = try XCTUnwrap(model.stopRecording())
        exported.append(url)

        XCTAssertNil(try decodeSession(at: url).metadata.baseline)
    }

    func test_tagCurrentSession_addsAManualTagToTheExportedSession() throws {
        let model = AppModel()
        model.baseline = makeBaseline()

        model.startRecording()
        model.tagCurrentSession(.slouching)
        let url = try XCTUnwrap(model.stopRecording())
        exported.append(url)

        let tags = try decodeSession(at: url).tags
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.label, .slouching)
        XCTAssertEqual(tags.first?.source, .manual)
    }

    func test_tagCurrentSession_isIgnoredWhenNotRecording() throws {
        let model = AppModel()

        model.tagCurrentSession(.goodPosture)

        XCTAssertFalse(model.isRecording)
    }
}
