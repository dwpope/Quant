import XCTest
@testable import PostureLogic

/// Tests for TaskModeEngine activity classification.
///
/// The engine infers what the user is doing (reading, typing, meeting, stretching)
/// from a rolling window of movement metrics. Each test fills the window with
/// metrics matching a specific activity signature and verifies the classification.
///
/// Tests cover:
/// - Basic classification for each activity type (6 original tests)
/// - Majority-vote behavior with mixed-signal windows
/// - Tie-breaking by declaration order (stretching > reading > typing > meeting)
/// - Boundary values at classification thresholds
/// - Edge cases: empty input, exact minimum sample count
/// - Debug state tracking across classifications
/// - Consecutive classifications adapting to changing data
final class TaskModeEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetrics(
        movementLevel: Float,
        headMovementPattern: MovementPattern,
        count: Int = 20
    ) -> [RawMetrics] {
        (0 ..< count).map { i in
            RawMetrics(
                timestamp: TimeInterval(i) * 0.1,
                forwardCreep: 0,
                headDrop: 0,
                shoulderRounding: 0,
                lateralLean: 0,
                twist: 0,
                movementLevel: movementLevel,
                headMovementPattern: headMovementPattern
            )
        }
    }

    /// Builds a mixed window with specified counts of each activity type.
    /// Total count must be >= 10 for classification to engage.
    private func makeMixedMetrics(
        reading: Int = 0,
        typing: Int = 0,
        meeting: Int = 0,
        stretching: Int = 0,
        unmatched: Int = 0
    ) -> [RawMetrics] {
        var result: [RawMetrics] = []
        var t: TimeInterval = 0

        for _ in 0 ..< reading {
            result.append(RawMetrics(timestamp: t, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                     lateralLean: 0, twist: 0, movementLevel: 0.1, headMovementPattern: .smallOscillations))
            t += 0.1
        }
        for _ in 0 ..< typing {
            result.append(RawMetrics(timestamp: t, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                     lateralLean: 0, twist: 0, movementLevel: 0.35, headMovementPattern: .largeMovements))
            t += 0.1
        }
        for _ in 0 ..< meeting {
            result.append(RawMetrics(timestamp: t, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                     lateralLean: 0, twist: 0, movementLevel: 0.25, headMovementPattern: .still))
            t += 0.1
        }
        for _ in 0 ..< stretching {
            result.append(RawMetrics(timestamp: t, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                     lateralLean: 0, twist: 0, movementLevel: 0.8, headMovementPattern: .erratic))
            t += 0.1
        }
        // Unmatched: movement 0.6 + erratic doesn't match any pattern
        for _ in 0 ..< unmatched {
            result.append(RawMetrics(timestamp: t, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                     lateralLean: 0, twist: 0, movementLevel: 0.6, headMovementPattern: .erratic))
            t += 0.1
        }
        return result
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Basic Classification (original tests)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_classifiesReading_withLowMovementSmallOscillations() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations)
        XCTAssertEqual(engine.infer(from: metrics), .reading)
    }

    func test_classifiesTyping_withModerateMovementLargeMovements() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.35, headMovementPattern: .largeMovements)
        XCTAssertEqual(engine.infer(from: metrics), .typing)
    }

    func test_classifiesStretching_withHighMovement() {
        let engine = TaskModeEngine()
        // Stretching doesn't care about head pattern — any pattern should work
        let metrics = makeMetrics(movementLevel: 0.8, headMovementPattern: .erratic)
        XCTAssertEqual(engine.infer(from: metrics), .stretching)
    }

    func test_classifiesMeeting_withLowMovementStill() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.25, headMovementPattern: .still)
        XCTAssertEqual(engine.infer(from: metrics), .meeting)
    }

    func test_returnsUnknown_withInsufficientSamples() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations, count: 5)
        XCTAssertEqual(engine.infer(from: metrics), .unknown)
    }

    func test_returnsUnknown_whenNoPatternMatches() {
        let engine = TaskModeEngine()
        // movementLevel 0.5–0.7 with .erratic doesn't match any pattern
        let metrics = makeMetrics(movementLevel: 0.6, headMovementPattern: .erratic)
        XCTAssertEqual(engine.infer(from: metrics), .unknown)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Edge Cases: Empty and Minimum Samples
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_returnsUnknown_withEmptyArray() {
        let engine = TaskModeEngine()
        XCTAssertEqual(engine.infer(from: []), .unknown)
    }

    func test_returnsUnknown_withNineSamples() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations, count: 9)
        XCTAssertEqual(engine.infer(from: metrics), .unknown,
                       "9 samples is below the 10-sample minimum")
    }

    func test_classifiesCorrectly_withExactlyTenSamples() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations, count: 10)
        XCTAssertEqual(engine.infer(from: metrics), .reading,
                       "Exactly 10 samples should be enough to classify")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Majority Voting with Mixed Windows
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_majorityVoting_readingWins() {
        let engine = TaskModeEngine()
        // 8 reading + 3 typing + 3 meeting = 14 total
        let metrics = makeMixedMetrics(reading: 8, typing: 3, meeting: 3)
        XCTAssertEqual(engine.infer(from: metrics), .reading,
                       "Reading has the most votes and should win")
    }

    func test_majorityVoting_typingWins() {
        let engine = TaskModeEngine()
        let metrics = makeMixedMetrics(reading: 2, typing: 8, meeting: 2)
        XCTAssertEqual(engine.infer(from: metrics), .typing,
                       "Typing has the most votes and should win")
    }

    func test_majorityVoting_meetingWins() {
        let engine = TaskModeEngine()
        let metrics = makeMixedMetrics(reading: 2, typing: 2, meeting: 8)
        XCTAssertEqual(engine.infer(from: metrics), .meeting,
                       "Meeting has the most votes and should win")
    }

    func test_majorityVoting_stretchingWins() {
        let engine = TaskModeEngine()
        let metrics = makeMixedMetrics(reading: 2, typing: 2, stretching: 8)
        XCTAssertEqual(engine.infer(from: metrics), .stretching,
                       "Stretching has the most votes and should win")
    }

    func test_majorityVoting_singleVoteWins_whenRestUnmatched() {
        let engine = TaskModeEngine()
        // 1 reading vote + 9 unmatched = only reading has votes
        let metrics = makeMixedMetrics(reading: 1, unmatched: 9)
        XCTAssertEqual(engine.infer(from: metrics), .reading,
                       "A single vote should win when all other samples are unmatched")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Tie-Breaking
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_tieBreaking_stretchingBeatsReading() {
        let engine = TaskModeEngine()
        // Equal votes: stretching and reading tied at 5 each
        let metrics = makeMixedMetrics(reading: 5, stretching: 5)
        XCTAssertEqual(engine.infer(from: metrics), .stretching,
                       "Stretching is declared first in candidates and should win ties")
    }

    func test_tieBreaking_readingBeatsTyping() {
        let engine = TaskModeEngine()
        let metrics = makeMixedMetrics(reading: 5, typing: 5)
        XCTAssertEqual(engine.infer(from: metrics), .reading,
                       "Reading is declared before typing and should win ties")
    }

    func test_tieBreaking_typingBeatsMeeting() {
        let engine = TaskModeEngine()
        let metrics = makeMixedMetrics(typing: 5, meeting: 5)
        XCTAssertEqual(engine.infer(from: metrics), .typing,
                       "Typing is declared before meeting and should win ties")
    }

    func test_tieBreaking_threewayTie() {
        let engine = TaskModeEngine()
        // reading=4, typing=4, meeting=4 => stretching(0) < reading(4) wins by order
        let metrics = makeMixedMetrics(reading: 4, typing: 4, meeting: 4)
        XCTAssertEqual(engine.infer(from: metrics), .reading,
                       "In a three-way tie, reading wins (declared before typing and meeting)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Boundary Values
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_reading_upperBoundary_movementAtExactly0point2_doesNotMatchReading() {
        let engine = TaskModeEngine()
        // Reading requires < 0.2; at exactly 0.2, it should NOT match reading
        let metrics = makeMetrics(movementLevel: 0.2, headMovementPattern: .smallOscillations)
        XCTAssertNotEqual(engine.infer(from: metrics), .reading,
                          "movementLevel == 0.2 is not < 0.2, so reading should not match")
    }

    func test_typing_lowerBoundary_movementAtExactly0point2_matchesTyping() {
        let engine = TaskModeEngine()
        // Typing requires 0.2 ..< 0.5; at exactly 0.2, it matches
        let metrics = makeMetrics(movementLevel: 0.2, headMovementPattern: .largeMovements)
        XCTAssertEqual(engine.infer(from: metrics), .typing,
                       "movementLevel == 0.2 is in 0.2..<0.5 range for typing")
    }

    func test_typing_upperBoundary_movementAtExactly0point5_doesNotMatchTyping() {
        let engine = TaskModeEngine()
        // Typing requires 0.2 ..< 0.5; at exactly 0.5, it should NOT match
        let metrics = makeMetrics(movementLevel: 0.5, headMovementPattern: .largeMovements)
        XCTAssertNotEqual(engine.infer(from: metrics), .typing,
                          "movementLevel == 0.5 is not in 0.2..<0.5 range")
    }

    func test_stretching_lowerBoundary_movementAtExactly0point7_doesNotMatchStretching() {
        let engine = TaskModeEngine()
        // Stretching requires > 0.7; at exactly 0.7, it should NOT match
        let metrics = makeMetrics(movementLevel: 0.7, headMovementPattern: .erratic)
        XCTAssertNotEqual(engine.infer(from: metrics), .stretching,
                          "movementLevel == 0.7 is not > 0.7, so stretching should not match")
    }

    func test_stretching_justAboveBoundary() {
        let engine = TaskModeEngine()
        let metrics = makeMetrics(movementLevel: 0.71, headMovementPattern: .erratic)
        XCTAssertEqual(engine.infer(from: metrics), .stretching,
                       "movementLevel 0.71 > 0.7 should classify as stretching")
    }

    func test_meeting_lowerBoundary_movementAtExactly0point15_matchesMeeting() {
        let engine = TaskModeEngine()
        // Meeting requires 0.15 ..< 0.4; at exactly 0.15, it matches
        let metrics = makeMetrics(movementLevel: 0.15, headMovementPattern: .still)
        XCTAssertEqual(engine.infer(from: metrics), .meeting,
                       "movementLevel == 0.15 is in 0.15..<0.4 range for meeting")
    }

    func test_meeting_upperBoundary_movementAtExactly0point4_doesNotMatchMeeting() {
        let engine = TaskModeEngine()
        // Meeting requires 0.15 ..< 0.4; at exactly 0.4, it should NOT match
        let metrics = makeMetrics(movementLevel: 0.4, headMovementPattern: .still)
        XCTAssertNotEqual(engine.infer(from: metrics), .meeting,
                          "movementLevel == 0.4 is not in 0.15..<0.4 range")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Head Pattern Mismatch
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_readingRange_wrongHeadPattern_doesNotClassifyAsReading() {
        let engine = TaskModeEngine()
        // movementLevel in reading range but head pattern is .still (not .smallOscillations)
        let metrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .still)
        // Should match meeting (0.15..< 0.4 still) — but 0.1 < 0.15, so no meeting either
        XCTAssertNotEqual(engine.infer(from: metrics), .reading,
                          "Reading requires .smallOscillations head pattern")
    }

    func test_typingRange_wrongHeadPattern_doesNotClassifyAsTyping() {
        let engine = TaskModeEngine()
        // movementLevel in typing range but head pattern is .still (not .largeMovements)
        // 0.35 with .still => matches meeting (0.15..<0.4 + .still)
        let metrics = makeMetrics(movementLevel: 0.35, headMovementPattern: .still)
        XCTAssertNotEqual(engine.infer(from: metrics), .typing,
                          "Typing requires .largeMovements head pattern")
        XCTAssertEqual(engine.infer(from: metrics), .meeting,
                       "0.35 + .still falls in meeting range")
    }

    func test_meetingRange_wrongHeadPattern_doesNotClassifyAsMeeting() {
        let engine = TaskModeEngine()
        // movementLevel in meeting range but head pattern is .erratic (not .still)
        let metrics = makeMetrics(movementLevel: 0.25, headMovementPattern: .erratic)
        XCTAssertNotEqual(engine.infer(from: metrics), .meeting,
                          "Meeting requires .still head pattern")
    }

    func test_stretching_anyHeadPattern_classifiesAsStretching() {
        let engine = TaskModeEngine()
        // Stretching only checks movement > 0.7, head pattern is irrelevant
        for pattern: MovementPattern in [.still, .smallOscillations, .largeMovements, .erratic] {
            let metrics = makeMetrics(movementLevel: 0.8, headMovementPattern: pattern)
            XCTAssertEqual(engine.infer(from: metrics), .stretching,
                           "Stretching should classify regardless of head pattern \(pattern.rawValue)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Consecutive Classifications
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_consecutiveClassifications_adaptsToNewData() {
        let engine = TaskModeEngine()
        // First: reading
        let readingMetrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations)
        XCTAssertEqual(engine.infer(from: readingMetrics), .reading)
        // Second: typing (engine should adapt)
        let typingMetrics = makeMetrics(movementLevel: 0.35, headMovementPattern: .largeMovements)
        XCTAssertEqual(engine.infer(from: typingMetrics), .typing)
        // Third: stretching
        let stretchingMetrics = makeMetrics(movementLevel: 0.8, headMovementPattern: .erratic)
        XCTAssertEqual(engine.infer(from: stretchingMetrics), .stretching)
    }

    func test_transitionFromUnknown_toClassified() {
        let engine = TaskModeEngine()
        // Start with insufficient samples
        let fewSamples = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations, count: 5)
        XCTAssertEqual(engine.infer(from: fewSamples), .unknown)
        // Then provide enough
        let enoughSamples = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations, count: 20)
        XCTAssertEqual(engine.infer(from: enoughSamples), .reading)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Debug State
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_debugState_reflectsLastClassification() {
        let engine = TaskModeEngine()
        // Before any classification
        XCTAssertEqual(engine.debugState["lastResult"] as? String, "unknown")

        // After reading classification
        let readingMetrics = makeMetrics(movementLevel: 0.1, headMovementPattern: .smallOscillations)
        _ = engine.infer(from: readingMetrics)
        XCTAssertEqual(engine.debugState["lastResult"] as? String, "reading")

        // After stretching classification
        let stretchingMetrics = makeMetrics(movementLevel: 0.8, headMovementPattern: .erratic)
        _ = engine.infer(from: stretchingMetrics)
        XCTAssertEqual(engine.debugState["lastResult"] as? String, "stretching")
    }

    func test_debugState_containsMinimumSamples() {
        let engine = TaskModeEngine()
        XCTAssertEqual(engine.debugState["minimumSamples"] as? Int, 10)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Overlap Zones
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_readingMeetingOverlap_movementAt0point18() {
        let engine = TaskModeEngine()
        // movementLevel 0.18: qualifies for reading (< 0.2) AND meeting (0.15 ..< 0.4)
        // With .smallOscillations => matches reading but not meeting (.still required)
        let metrics = makeMetrics(movementLevel: 0.18, headMovementPattern: .smallOscillations)
        XCTAssertEqual(engine.infer(from: metrics), .reading)
    }

    func test_readingMeetingOverlap_movementAt0point18_stillPattern() {
        let engine = TaskModeEngine()
        // movementLevel 0.18: qualifies for reading (< 0.2) AND meeting (0.15 ..< 0.4)
        // With .still => matches meeting but not reading (.smallOscillations required)
        let metrics = makeMetrics(movementLevel: 0.18, headMovementPattern: .still)
        XCTAssertEqual(engine.infer(from: metrics), .meeting)
    }

    func test_typingMeetingOverlap_movementAt0point3() {
        let engine = TaskModeEngine()
        // movementLevel 0.3: qualifies for typing (0.2 ..< 0.5) AND meeting (0.15 ..< 0.4)
        // With .largeMovements => matches typing but not meeting
        let metrics = makeMetrics(movementLevel: 0.3, headMovementPattern: .largeMovements)
        XCTAssertEqual(engine.infer(from: metrics), .typing)
    }

    func test_typingMeetingOverlap_movementAt0point3_stillPattern() {
        let engine = TaskModeEngine()
        // movementLevel 0.3: qualifies for typing (0.2 ..< 0.5) AND meeting (0.15 ..< 0.4)
        // With .still => matches meeting but not typing
        let metrics = makeMetrics(movementLevel: 0.3, headMovementPattern: .still)
        XCTAssertEqual(engine.infer(from: metrics), .meeting)
    }
}
