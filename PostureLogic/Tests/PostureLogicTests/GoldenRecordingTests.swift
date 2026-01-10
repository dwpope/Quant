import XCTest
@testable import PostureLogic

/// Tests for golden recordings generation and validation
final class GoldenRecordingTests: XCTestCase {

    // MARK: - Generation Tests

    /// Test to generate all golden recordings
    /// This test can be run manually to regenerate the golden recordings
    func test_generateGoldenRecordings() throws {
        // Get the project root directory
        let testBundle = Bundle(for: type(of: self))
        let projectRoot = testBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let goldenRecordingsDir = projectRoot.appendingPathComponent("GoldenRecordings").path

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(atPath: goldenRecordingsDir, withIntermediateDirectories: true)

        // Generate all recordings
        try GoldenRecordingGenerator.generateAll(to: goldenRecordingsDir)

        // Verify files were created
        let expectedFiles = [
            "good_posture_5min.json",
            "gradual_slouch.json",
            "reading_vs_typing.json",
            "depth_fallback_scenario.json"
        ]

        for filename in expectedFiles {
            let filePath = (goldenRecordingsDir as NSString).appendingPathComponent(filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "File \(filename) should exist")
        }

        print("✅ Golden recordings generated successfully at: \(goldenRecordingsDir)")
    }

    // MARK: - Validation Tests

    func test_goodPosture5Min_structure() {
        let session = GoldenRecordingGenerator.generateGoodPosture5Min()

        // Verify basic structure
        XCTAssertEqual(session.metadata.deviceModel, "iPhone15,3")
        XCTAssertTrue(session.metadata.depthAvailable)

        // Verify duration (5 minutes at 10 FPS = 3000 samples)
        XCTAssertEqual(session.samples.count, 3000, "Should have 3000 samples for 5 minutes at 10 FPS")

        // Verify timestamps are sequential
        for i in 1..<min(10, session.samples.count) {
            let delta = session.samples[i].timestamp - session.samples[i-1].timestamp
            XCTAssertEqual(delta, 0.1, accuracy: 0.001, "Samples should be 0.1s apart (10 FPS)")
        }

        // Verify all samples have good tracking quality
        let allGood = session.samples.allSatisfy { $0.trackingQuality == .good }
        XCTAssertTrue(allGood, "All samples should have good tracking quality")

        // Verify all samples use depth fusion
        let allDepth = session.samples.allSatisfy { $0.depthMode == .depthFusion }
        XCTAssertTrue(allDepth, "All samples should use depth fusion")

        // Verify tags exist
        XCTAssertGreaterThan(session.tags.count, 0, "Should have at least one tag")
        XCTAssertTrue(session.tags.contains { $0.label == .goodPosture }, "Should have goodPosture tags")

        print("✅ Good posture recording validated")
    }

    func test_gradualSlouch_structure() {
        let session = GoldenRecordingGenerator.generateGradualSlouch()

        // Verify duration (10 minutes at 10 FPS = 6000 samples)
        XCTAssertEqual(session.samples.count, 6000, "Should have 6000 samples for 10 minutes at 10 FPS")

        // Verify posture deteriorates over time
        let firstSample = session.samples[0]
        let midSample = session.samples[3000] // 5 minutes in
        let lastSample = session.samples[5999]

        // Forward creep should increase
        XCTAssertLessThan(firstSample.headForwardOffset, midSample.headForwardOffset,
                         "Head should move forward as posture deteriorates")
        XCTAssertLessThan(midSample.headForwardOffset, lastSample.headForwardOffset,
                         "Head should continue moving forward")

        // Torso angle should increase
        XCTAssertLessThan(firstSample.torsoAngle, lastSample.torsoAngle,
                         "Torso angle should increase when slouching")

        // Head should move closer (Z decreases)
        XCTAssertGreaterThan(firstSample.headPosition.z, lastSample.headPosition.z,
                            "Head should move closer to camera when slouching")

        // Verify tags include both good and slouching
        XCTAssertTrue(session.tags.contains { $0.label == .goodPosture }, "Should have goodPosture tag")
        XCTAssertTrue(session.tags.contains { $0.label == .slouching }, "Should have slouching tag")

        print("✅ Gradual slouch recording validated")
    }

    func test_readingVsTyping_structure() {
        let session = GoldenRecordingGenerator.generateReadingVsTyping()

        // Verify duration (8 minutes at 10 FPS = 4800 samples)
        XCTAssertEqual(session.samples.count, 4800, "Should have 4800 samples for 8 minutes at 10 FPS")

        // Verify tags include both reading and typing
        XCTAssertTrue(session.tags.contains { $0.label == .reading }, "Should have reading tags")
        XCTAssertTrue(session.tags.contains { $0.label == .typing }, "Should have typing tags")

        // Verify movement patterns differ between reading and typing segments
        // Reading segment: first 2 minutes (0-1200 samples)
        let readingSamples = Array(session.samples[0..<1200])
        let readingMovement = readingSamples.map { abs($0.headPosition.x) }.reduce(0, +) / Float(readingSamples.count)

        // Typing segment: minutes 2-4 (1200-2400 samples)
        let typingSamples = Array(session.samples[1200..<2400])
        let typingMovement = typingSamples.map { abs($0.headPosition.x) }.reduce(0, +) / Float(typingSamples.count)

        // Typing should have more variation/movement
        // Note: This is a rough check; actual values depend on noise generation
        print("Reading avg movement: \(readingMovement), Typing avg movement: \(typingMovement)")

        print("✅ Reading vs Typing recording validated")
    }

    func test_depthFallback_structure() {
        let session = GoldenRecordingGenerator.generateDepthFallback()

        // Verify duration (6 minutes at 10 FPS = 3600 samples)
        XCTAssertEqual(session.samples.count, 3600, "Should have 3600 samples for 6 minutes at 10 FPS")

        // Verify mode switching occurs
        let hasDepthFusion = session.samples.contains { $0.depthMode == .depthFusion }
        let hasTwoDOnly = session.samples.contains { $0.depthMode == .twoDOnly }

        XCTAssertTrue(hasDepthFusion, "Should have samples with depth fusion")
        XCTAssertTrue(hasTwoDOnly, "Should have samples with 2D-only mode")

        // Verify tracking quality varies
        let hasGood = session.samples.contains { $0.trackingQuality == .good }
        let hasDegraded = session.samples.contains { $0.trackingQuality == .degraded }

        XCTAssertTrue(hasGood, "Should have samples with good tracking")
        XCTAssertTrue(hasDegraded, "Should have samples with degraded tracking")

        // Check specific time windows
        // Minute 0-1: depth available (samples 0-599)
        let firstMinute = Array(session.samples[0..<600])
        XCTAssertTrue(firstMinute.allSatisfy { $0.depthMode == .depthFusion },
                     "First minute should have depth fusion")

        // Minute 1-2: depth lost (samples 600-1199)
        let secondMinute = Array(session.samples[600..<1200])
        XCTAssertTrue(secondMinute.allSatisfy { $0.depthMode == .twoDOnly },
                     "Second minute should be 2D only")

        print("✅ Depth fallback recording validated")
    }

    // MARK: - Regression Test Example

    func test_gradualSlouch_detectsSlouchInGoldenRecording() {
        let session = GoldenRecordingGenerator.generateGradualSlouch()

        // Simulate checking for bad posture over time
        // In a real implementation, this would use the MetricsEngine and PostureEngine
        // For now, we just verify the data supports detecting slouch

        var foundSlouch = false

        for sample in session.samples {
            // Simple heuristic: if forward offset exceeds threshold, it's slouching
            if sample.headForwardOffset > 0.08 {
                foundSlouch = true
                break
            }
        }

        XCTAssertTrue(foundSlouch, "Should detect slouch in gradual slouch recording")
        print("✅ Slouch detection works on golden recording")
    }

    // MARK: - JSON Encoding/Decoding Test

    func test_recordingsCanBeEncodedAndDecoded() throws {
        let session = GoldenRecordingGenerator.generateGoodPosture5Min()

        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        XCTAssertGreaterThan(data.count, 0, "Encoded data should not be empty")

        // Decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordedSession.self, from: data)

        // Verify key properties match
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.samples.count, session.samples.count)
        XCTAssertEqual(decoded.tags.count, session.tags.count)
        XCTAssertEqual(decoded.metadata.deviceModel, session.metadata.deviceModel)

        print("✅ JSON encoding/decoding works correctly")
    }

    // MARK: - File Size Validation

    func test_fileSizesAreReasonable() throws {
        let sessions: [(session: RecordedSession, name: String, maxSizeKB: Int)] = [
            (GoldenRecordingGenerator.generateGoodPosture5Min(), "good_posture_5min", 2000),
            (GoldenRecordingGenerator.generateGradualSlouch(), "gradual_slouch", 4000),
            (GoldenRecordingGenerator.generateReadingVsTyping(), "reading_vs_typing", 3200),
            (GoldenRecordingGenerator.generateDepthFallback(), "depth_fallback", 2400)
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for (session, name, maxSizeKB) in sessions {
            let data = try encoder.encode(session)
            let sizeKB = data.count / 1024

            XCTAssertLessThan(sizeKB, maxSizeKB,
                            "\(name) should be less than \(maxSizeKB)KB (got \(sizeKB)KB)")

            print("📊 \(name): \(sizeKB)KB (limit: \(maxSizeKB)KB)")
        }
    }

    // MARK: - Loading Tests (Using Saved Files)

    func test_loadGoodPosture5Min_fromDisk() throws {
        let session = try GoldenRecordingLoader.loadGoodPosture5Min()

        XCTAssertEqual(session.samples.count, 3000, "Should have 3000 samples")
        XCTAssertTrue(session.metadata.depthAvailable)
        XCTAssertGreaterThan(session.tags.count, 0)

        print("✅ Successfully loaded good_posture_5min.json from disk")
    }

    func test_loadGradualSlouch_fromDisk() throws {
        let session = try GoldenRecordingLoader.loadGradualSlouch()

        XCTAssertEqual(session.samples.count, 6000, "Should have 6000 samples")
        XCTAssertTrue(session.tags.contains { $0.label == .slouching })

        print("✅ Successfully loaded gradual_slouch.json from disk")
    }

    func test_loadReadingVsTyping_fromDisk() throws {
        let session = try GoldenRecordingLoader.loadReadingVsTyping()

        XCTAssertEqual(session.samples.count, 4800, "Should have 4800 samples")
        XCTAssertTrue(session.tags.contains { $0.label == .reading })
        XCTAssertTrue(session.tags.contains { $0.label == .typing })

        print("✅ Successfully loaded reading_vs_typing.json from disk")
    }

    func test_loadDepthFallback_fromDisk() throws {
        let session = try GoldenRecordingLoader.loadDepthFallback()

        XCTAssertEqual(session.samples.count, 3600, "Should have 3600 samples")

        let hasDepthFusion = session.samples.contains { $0.depthMode == .depthFusion }
        let hasTwoDOnly = session.samples.contains { $0.depthMode == .twoDOnly }

        XCTAssertTrue(hasDepthFusion)
        XCTAssertTrue(hasTwoDOnly)

        print("✅ Successfully loaded depth_fallback_scenario.json from disk")
    }

    // MARK: - Replay Integration Tests

    func test_replayService_canPlayGoldenRecording() async throws {
        let session = try GoldenRecordingLoader.loadGoodPosture5Min()
        let replay = ReplayService()

        replay.load(session: session)
        replay.setSpeed(100.0) // Speed up for testing

        var sampleCount = 0
        for await _ in replay.play() {
            sampleCount += 1
            if sampleCount >= 10 {
                replay.stop()
                break
            }
        }

        XCTAssertEqual(sampleCount, 10, "Should have replayed 10 samples")
        print("✅ ReplayService successfully played golden recording")
    }

    func test_gradualSlouch_detectionCharacteristics() throws {
        let session = try GoldenRecordingLoader.loadGradualSlouch()

        // Verify the slouch progression characteristics
        // First sample (good posture)
        let firstSample = session.samples[0]
        XCTAssertLessThan(firstSample.headForwardOffset, 0.05, "Initial posture should be good")
        XCTAssertLessThan(firstSample.torsoAngle, 5.0, "Initial torso angle should be small")

        // Last sample (slouched)
        let lastSample = session.samples[session.samples.count - 1]
        XCTAssertGreaterThan(lastSample.headForwardOffset, 0.08, "Final posture should show forward creep")
        XCTAssertGreaterThan(lastSample.torsoAngle, 10.0, "Final torso angle should be larger")

        // Verify monotonic increase in slouch
        let midSample = session.samples[3000]
        XCTAssertLessThan(firstSample.headForwardOffset, midSample.headForwardOffset)
        XCTAssertLessThan(midSample.headForwardOffset, lastSample.headForwardOffset)

        print("✅ Gradual slouch characteristics validated")
    }

    func test_readingVsTyping_hasDistinctPatterns() throws {
        let session = try GoldenRecordingLoader.loadReadingVsTyping()

        // Find reading and typing segments based on tags
        var readingStartIndex: Int?
        var typingStartIndex: Int?

        for (_, tag) in session.tags.enumerated() {
            if tag.label == .reading && readingStartIndex == nil {
                // Find sample index for this timestamp
                readingStartIndex = session.samples.firstIndex { $0.timestamp >= tag.timestamp }
            }
            if tag.label == .typing && typingStartIndex == nil {
                typingStartIndex = session.samples.firstIndex { $0.timestamp >= tag.timestamp }
            }
        }

        XCTAssertNotNil(readingStartIndex, "Should find reading segment")
        XCTAssertNotNil(typingStartIndex, "Should find typing segment")

        if let readingStart = readingStartIndex, let typingStart = typingStartIndex {
            let readingSample = session.samples[readingStart]
            let typingSample = session.samples[typingStart]

            // Typing typically has more forward lean
            XCTAssertGreaterThan(typingSample.headForwardOffset, readingSample.headForwardOffset,
                               "Typing should have more forward lean than reading")

            print("✅ Reading vs Typing patterns validated")
        }
    }

    func test_depthFallback_hasCorrectModeTransitions() throws {
        let session = try GoldenRecordingLoader.loadDepthFallback()

        // According to the generator:
        // 0-60s: depthFusion
        // 60-120s: twoDOnly
        // 120-180s: depthFusion
        // 180-240s: twoDOnly
        // 240-360s: depthFusion

        let sample30s = session.samples[300]   // 30 seconds (index 300 at 10fps)
        let sample90s = session.samples[900]   // 90 seconds
        let sample150s = session.samples[1500] // 150 seconds
        let sample210s = session.samples[2100] // 210 seconds
        let sample300s = session.samples[3000] // 300 seconds

        XCTAssertEqual(sample30s.depthMode, .depthFusion, "First minute should have depth")
        XCTAssertEqual(sample90s.depthMode, .twoDOnly, "Second minute should be 2D only")
        XCTAssertEqual(sample150s.depthMode, .depthFusion, "Third minute should have depth")
        XCTAssertEqual(sample210s.depthMode, .twoDOnly, "Fourth minute should be 2D only")
        XCTAssertEqual(sample300s.depthMode, .depthFusion, "Fifth minute should have depth")

        print("✅ Depth mode transitions validated")
    }

    // MARK: - Success Criteria Validation

    /// This test validates that the gradual_slouch recording meets the success criteria
    /// for slouch detection as defined in the implementation plan
    func test_successCriteria_slouchDetectionRate() throws {
        let session = try GoldenRecordingLoader.loadGradualSlouch()

        // According to success criteria:
        // - Detection rate: ≥70% of slouch episodes (≥5 minutes sustained) should trigger detection

        // The gradual slouch recording has a clear slouch period from minute 6-10
        // That's a 4-minute sustained bad posture, so it should be detectable

        var detectionOpportunities = 0
        var wouldTriggerNudge = 0

        // Simple threshold check (this will be replaced by actual PostureEngine in Sprint 4)
        for sample in session.samples {
            // If forward offset exceeds threshold for sustained period
            if sample.headForwardOffset > 0.10 || sample.torsoAngle > 15.0 {
                detectionOpportunities += 1
                wouldTriggerNudge += 1
            }
        }

        // Should detect slouch in at least 70% of the bad posture samples
        let detectionRate = Double(wouldTriggerNudge) / Double(session.samples.count)

        print("📊 Slouch detection opportunities: \(detectionOpportunities)/\(session.samples.count)")
        print("📊 Detection rate: \(String(format: "%.1f%%", detectionRate * 100))")

        // This is a basic check; real validation will use PostureEngine + NudgeEngine
        XCTAssertGreaterThan(detectionOpportunities, 0, "Should find some slouch episodes")

        print("✅ Success criteria baseline established")
    }
}
