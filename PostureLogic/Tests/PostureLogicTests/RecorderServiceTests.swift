import XCTest
@testable import PostureLogic

final class RecorderServiceTests: XCTestCase {

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

    // MARK: - Lifecycle

    func test_init_notRecording() {
        let service = RecorderService()
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.sampleCount, 0)
    }

    func test_startRecording_setsIsRecording() {
        let service = RecorderService()
        let started = service.startRecording(metadata: makeMetadata())
        XCTAssertTrue(started)
        XCTAssertTrue(service.isRecording)
    }

    func test_startRecording_whileRecording_returnsFalse() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())
        let startedAgain = service.startRecording(metadata: makeMetadata())
        XCTAssertFalse(startedAgain)
        XCTAssertTrue(service.isRecording)
    }

    func test_stopRecording_returnsSession() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample(timestamp: 0.0))
        service.record(sample: makeSample(timestamp: 0.1))

        let session = service.stopRecording()
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.samples.count, 2)
        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.sampleCount, 0)
    }

    func test_stopRecording_whenNotRecording_returnsNil() {
        let service = RecorderService()
        XCTAssertNil(service.stopRecording())
    }

    func test_stopRecording_resetsState() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample())
        _ = service.stopRecording()

        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(service.sampleCount, 0)
    }

    // MARK: - Recording samples

    func test_record_appendsSamples() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())

        for i in 0..<5 {
            service.record(sample: makeSample(timestamp: Double(i) * 0.1))
        }

        XCTAssertEqual(service.sampleCount, 5)
    }

    func test_record_whenNotRecording_isNoop() {
        let service = RecorderService()
        service.record(sample: makeSample())
        XCTAssertEqual(service.sampleCount, 0)
    }

    // MARK: - Session correctness

    func test_session_containsCorrectMetadata() {
        let service = RecorderService()
        let metadata = makeMetadata()
        service.startRecording(metadata: metadata)
        service.record(sample: makeSample())

        let session = service.stopRecording()!
        XCTAssertEqual(session.metadata.deviceModel, "TestDevice")
        XCTAssertTrue(session.metadata.depthAvailable)
    }

    func test_session_hasValidTimestamps() {
        let service = RecorderService()
        let beforeStart = Date()
        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample())
        let session = service.stopRecording()!
        let afterStop = Date()

        XCTAssertGreaterThanOrEqual(session.startTime, beforeStart)
        XCTAssertLessThanOrEqual(session.endTime, afterStop)
        XCTAssertLessThanOrEqual(session.startTime, session.endTime)
    }

    func test_session_hasUniqueID() {
        let service = RecorderService()

        service.startRecording(metadata: makeMetadata())
        let session1 = service.stopRecording()!

        service.startRecording(metadata: makeMetadata())
        let session2 = service.stopRecording()!

        XCTAssertNotEqual(session1.id, session2.id)
    }

    func test_session_tagsAreEmptyWithoutTagging() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample())
        let session = service.stopRecording()!
        XCTAssertTrue(session.tags.isEmpty)
    }

    // MARK: - Tagging

    func test_addTag_whileRecording_appendsTag() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())
        service.addTag(Tag(timestamp: 1.0, label: .goodPosture, source: .manual))

        let session = service.stopRecording()!
        XCTAssertEqual(session.tags.count, 1)
        XCTAssertEqual(session.tags[0].label, .goodPosture)
        XCTAssertEqual(session.tags[0].source, .manual)
        XCTAssertEqual(session.tags[0].timestamp, 1.0)
    }

    func test_addTag_whenNotRecording_isNoop() {
        let service = RecorderService()
        service.addTag(Tag(timestamp: 0.0, label: .slouching, source: .automatic))

        // Start a fresh session and verify no stale tags leak in
        service.startRecording(metadata: makeMetadata())
        let session = service.stopRecording()!
        XCTAssertTrue(session.tags.isEmpty)
    }

    func test_addTag_multipleTags_allIncludedInSession() {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())

        service.addTag(Tag(timestamp: 1.0, label: .goodPosture, source: .manual))
        service.addTag(Tag(timestamp: 2.5, label: .slouching, source: .automatic))
        service.addTag(Tag(timestamp: 4.0, label: .typing, source: .voice))

        let session = service.stopRecording()!
        XCTAssertEqual(session.tags.count, 3)
        XCTAssertEqual(session.tags[0].label, .goodPosture)
        XCTAssertEqual(session.tags[1].label, .slouching)
        XCTAssertEqual(session.tags[2].label, .typing)
        XCTAssertEqual(session.tags[0].source, .manual)
        XCTAssertEqual(session.tags[1].source, .automatic)
        XCTAssertEqual(session.tags[2].source, .voice)
    }

    // MARK: - Re-record after stop

    func test_canStartNewRecordingAfterStop() {
        let service = RecorderService()

        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample(timestamp: 1.0))
        let session1 = service.stopRecording()!
        XCTAssertEqual(session1.samples.count, 1)

        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample(timestamp: 2.0))
        service.record(sample: makeSample(timestamp: 2.1))
        let session2 = service.stopRecording()!
        XCTAssertEqual(session2.samples.count, 2)
    }

    // MARK: - JSON size budget

    func test_jsonSize_under5MB_for3000Samples() throws {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())

        // Simulate 5 minutes at 10 FPS = 3000 samples
        for i in 0..<3000 {
            service.record(sample: makeSample(timestamp: Double(i) * 0.1))
        }

        let session = service.stopRecording()!
        let data = try JSONEncoder().encode(session)
        let sizeInMB = Double(data.count) / (1024 * 1024)

        XCTAssertLessThan(sizeInMB, 5.0, "JSON export should be under 5 MB, was \(String(format: "%.2f", sizeInMB)) MB")
    }

    // MARK: - Codable roundtrip

    func test_session_codableRoundtrip() throws {
        let service = RecorderService()
        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample(timestamp: 0.0))
        service.record(sample: makeSample(timestamp: 0.1))
        let session = service.stopRecording()!

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(RecordedSession.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.samples.count, 2)
        XCTAssertEqual(decoded.metadata.deviceModel, "TestDevice")
    }

    // MARK: - DebugDumpable

    func test_debugState_reflectsRecordingStatus() {
        let service = RecorderService()

        let idleDump = service.debugState
        XCTAssertEqual(idleDump["isRecording"] as? Bool, false)
        XCTAssertEqual(idleDump["sampleCount"] as? Int, 0)

        service.startRecording(metadata: makeMetadata())
        service.record(sample: makeSample())

        let activeDump = service.debugState
        XCTAssertEqual(activeDump["isRecording"] as? Bool, true)
        XCTAssertEqual(activeDump["sampleCount"] as? Int, 1)
        XCTAssertNotNil(activeDump["sessionID"])
    }
}
