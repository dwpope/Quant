import XCTest
import Foundation
@testable import PostureLogic

final class RecorderServiceTests: XCTestCase {

    // MARK: - Basic Recording Tests

    func test_initialState_isNotRecording() {
        let recorder = RecorderService()

        XCTAssertFalse(recorder.isRecording)
    }

    func test_startRecording_setsIsRecording() {
        var recorder = RecorderService()

        recorder.startRecording()

        XCTAssertTrue(recorder.isRecording)
    }

    func test_stopRecording_clearsIsRecording() {
        var recorder = RecorderService()

        recorder.startRecording()
        _ = recorder.stopRecording()

        XCTAssertFalse(recorder.isRecording)
    }

    func test_stopRecording_returnsSession() {
        var recorder = RecorderService()

        recorder.startRecording()
        let session = recorder.stopRecording()

        XCTAssertNotNil(session)
        XCTAssertEqual(session.samples.count, 0)
        XCTAssertEqual(session.tags.count, 0)
    }

    // MARK: - Sample Recording Tests

    func test_recordSample_whileRecording_addsSample() {
        var recorder = RecorderService()
        recorder.startRecording()

        let sample = createMockSample(timestamp: 1.0)
        recorder.record(sample: sample)

        let session = recorder.stopRecording()
        XCTAssertEqual(session.samples.count, 1)
        XCTAssertEqual(session.samples[0].timestamp, 1.0)
    }

    func test_recordSample_whileNotRecording_doesNotAddSample() {
        var recorder = RecorderService()
        // Not recording

        let sample = createMockSample(timestamp: 1.0)
        recorder.record(sample: sample)

        recorder.startRecording()
        let session = recorder.stopRecording()

        XCTAssertEqual(session.samples.count, 0)
    }

    func test_recordMultipleSamples_preservesOrder() {
        var recorder = RecorderService()
        recorder.startRecording()

        for i in 0..<10 {
            let sample = createMockSample(timestamp: TimeInterval(i))
            recorder.record(sample: sample)
        }

        let session = recorder.stopRecording()
        XCTAssertEqual(session.samples.count, 10)

        for i in 0..<10 {
            XCTAssertEqual(session.samples[i].timestamp, TimeInterval(i))
        }
    }

    // MARK: - Tag Tests

    func test_addTag_whileRecording_addsTag() {
        var recorder = RecorderService()
        recorder.startRecording()

        let tag = Tag(timestamp: 1.0, label: .goodPosture, source: .manual)
        recorder.addTag(tag)

        let session = recorder.stopRecording()
        XCTAssertEqual(session.tags.count, 1)
        XCTAssertEqual(session.tags[0].label, .goodPosture)
    }

    func test_addTag_whileNotRecording_doesNotAddTag() {
        var recorder = RecorderService()
        // Not recording

        let tag = Tag(timestamp: 1.0, label: .goodPosture, source: .manual)
        recorder.addTag(tag)

        recorder.startRecording()
        let session = recorder.stopRecording()

        XCTAssertEqual(session.tags.count, 0)
    }

    func test_addMultipleTags_preservesAll() {
        var recorder = RecorderService()
        recorder.startRecording()

        let tags = [
            Tag(timestamp: 1.0, label: .goodPosture, source: .manual),
            Tag(timestamp: 2.0, label: .slouching, source: .automatic),
            Tag(timestamp: 3.0, label: .reading, source: .voice)
        ]

        for tag in tags {
            recorder.addTag(tag)
        }

        let session = recorder.stopRecording()
        XCTAssertEqual(session.tags.count, 3)
        XCTAssertEqual(session.tags[0].label, .goodPosture)
        XCTAssertEqual(session.tags[1].label, .slouching)
        XCTAssertEqual(session.tags[2].label, .reading)
    }

    // MARK: - Session Metadata Tests

    func test_session_includesMetadata() {
        var recorder = RecorderService()
        recorder.startRecording()

        let session = recorder.stopRecording()

        XCTAssertNotNil(session.metadata)
        XCTAssertNotNil(session.metadata.deviceModel)
        XCTAssertNotNil(session.metadata.thresholds)
    }

    func test_session_hasUniqueId() {
        var recorder = RecorderService()

        recorder.startRecording()
        let session1 = recorder.stopRecording()

        recorder.startRecording()
        let session2 = recorder.stopRecording()

        XCTAssertNotEqual(session1.id, session2.id)
    }

    func test_session_capturesStartAndEndTime() {
        var recorder = RecorderService()

        let beforeStart = Date()
        recorder.startRecording()
        let afterStart = Date()

        // Record some samples
        for i in 0..<5 {
            recorder.record(sample: createMockSample(timestamp: TimeInterval(i)))
        }

        let beforeEnd = Date()
        let session = recorder.stopRecording()
        let afterEnd = Date()

        // Start time should be between beforeStart and afterStart
        XCTAssertGreaterThanOrEqual(session.startTime, beforeStart)
        XCTAssertLessThanOrEqual(session.startTime, afterStart)

        // End time should be between beforeEnd and afterEnd
        XCTAssertGreaterThanOrEqual(session.endTime, beforeEnd)
        XCTAssertLessThanOrEqual(session.endTime, afterEnd)

        // End time should be after start time
        XCTAssertGreaterThan(session.endTime, session.startTime)
    }

    func test_session_detectsDepthAvailability() {
        var recorder = RecorderService()
        recorder.startRecording()

        // Record sample with depth fusion mode
        let sampleWithDepth = createMockSample(timestamp: 1.0, depthMode: .depthFusion)
        recorder.record(sample: sampleWithDepth)

        let session = recorder.stopRecording()

        XCTAssertTrue(session.metadata.depthAvailable)
    }

    func test_session_noDepthWhenOnly2D() {
        var recorder = RecorderService()
        recorder.startRecording()

        // Record sample with 2D only mode
        let sample2D = createMockSample(timestamp: 1.0, depthMode: .twoDOnly)
        recorder.record(sample: sample2D)

        let session = recorder.stopRecording()

        XCTAssertFalse(session.metadata.depthAvailable)
    }

    // MARK: - State Reset Tests

    func test_stopRecording_clearsSamples() {
        var recorder = RecorderService()

        recorder.startRecording()
        recorder.record(sample: createMockSample(timestamp: 1.0))
        _ = recorder.stopRecording()

        recorder.startRecording()
        let session = recorder.stopRecording()

        XCTAssertEqual(session.samples.count, 0, "New session should have no samples from previous recording")
    }

    func test_stopRecording_clearsTags() {
        var recorder = RecorderService()

        recorder.startRecording()
        recorder.addTag(Tag(timestamp: 1.0, label: .goodPosture, source: .manual))
        _ = recorder.stopRecording()

        recorder.startRecording()
        let session = recorder.stopRecording()

        XCTAssertEqual(session.tags.count, 0, "New session should have no tags from previous recording")
    }

    // MARK: - Debug State Tests

    func test_debugState_tracksSampleCount() {
        var recorder = RecorderService()
        recorder.startRecording()

        recorder.record(sample: createMockSample(timestamp: 1.0))
        recorder.record(sample: createMockSample(timestamp: 2.0))

        let debugState = recorder.debugState
        XCTAssertEqual(debugState["sampleCount"] as? Int, 2)
    }

    func test_debugState_tracksTagCount() {
        var recorder = RecorderService()
        recorder.startRecording()

        recorder.addTag(Tag(timestamp: 1.0, label: .goodPosture, source: .manual))

        let debugState = recorder.debugState
        XCTAssertEqual(debugState["tagCount"] as? Int, 1)
    }

    func test_debugState_tracksRecordingState() {
        var recorder = RecorderService()

        var debugState = recorder.debugState
        XCTAssertEqual(debugState["isRecording"] as? Bool, false)

        recorder.startRecording()
        debugState = recorder.debugState
        XCTAssertEqual(debugState["isRecording"] as? Bool, true)
    }

    // MARK: - JSON Export Tests

    func test_exportJSON_producesValidData() throws {
        var recorder = RecorderService()
        recorder.startRecording()

        recorder.record(sample: createMockSample(timestamp: 1.0))
        recorder.addTag(Tag(timestamp: 1.0, label: .goodPosture, source: .manual))

        let session = recorder.stopRecording()
        let jsonData = try session.exportJSON()

        XCTAssertGreaterThan(jsonData.count, 0)

        // Verify it's valid JSON by decoding it back
        let decoded = try RecordedSession.loadJSON(from: jsonData)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.samples.count, 1)
        XCTAssertEqual(decoded.tags.count, 1)
    }

    func test_exportAndLoad_preservesData() throws {
        var recorder = RecorderService()
        recorder.startRecording()

        // Add samples
        for i in 0..<5 {
            recorder.record(sample: createMockSample(timestamp: TimeInterval(i)))
        }

        // Add tags
        recorder.addTag(Tag(timestamp: 1.0, label: .goodPosture, source: .manual))
        recorder.addTag(Tag(timestamp: 3.0, label: .slouching, source: .automatic))

        let session = recorder.stopRecording()

        // Export and reload
        let jsonData = try session.exportJSON()
        let reloaded = try RecordedSession.loadJSON(from: jsonData)

        // Verify all data preserved
        XCTAssertEqual(reloaded.id, session.id)
        XCTAssertEqual(reloaded.samples.count, 5)
        XCTAssertEqual(reloaded.tags.count, 2)
        XCTAssertEqual(reloaded.samples[0].timestamp, 0.0)
        XCTAssertEqual(reloaded.samples[4].timestamp, 4.0)
        XCTAssertEqual(reloaded.tags[0].label, .goodPosture)
        XCTAssertEqual(reloaded.tags[1].label, .slouching)
    }

    // MARK: - File Size Tests

    func test_5MinuteRecording_estimatedSize() throws {
        var recorder = RecorderService()
        recorder.startRecording()

        // Simulate 5 minutes at 10 FPS
        let samplesFor5Minutes = 5 * 60 * 10  // 3000 samples
        for i in 0..<samplesFor5Minutes {
            let timestamp = TimeInterval(i) / 10.0
            recorder.record(sample: createMockSample(timestamp: timestamp))
        }

        // Add some tags
        for i in 0..<20 {
            let timestamp = TimeInterval(i * 15)  // Tag every 15 seconds
            recorder.addTag(Tag(timestamp: timestamp, label: .goodPosture, source: .manual))
        }

        let session = recorder.stopRecording()
        let jsonData = try session.exportJSON()
        let sizeMB = Double(jsonData.count) / 1_048_576.0

        print("📊 5-minute recording: \(samplesFor5Minutes) samples, \(session.tags.count) tags")
        print("📊 JSON size: \(String(format: "%.2f", sizeMB)) MB")
        print("📊 Bytes: \(jsonData.count)")

        // Acceptance criteria: < 5MB for 5 minutes
        XCTAssertLessThan(sizeMB, 5.0, "5-minute recording should be under 5MB")
    }

    // MARK: - Helper Functions

    private func createMockSample(timestamp: TimeInterval, depthMode: DepthMode = .twoDOnly) -> PoseSample {
        return PoseSample(
            timestamp: timestamp,
            depthMode: depthMode,
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
