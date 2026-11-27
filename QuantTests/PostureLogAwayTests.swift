import XCTest
import PostureLogic
@testable import Quant

/// The 10-second metrics line while Dave is away (2026-11-27). Session 15 wrote "bad" every 10 s
/// for the 3½ minutes he was out of the room (09:29:47–09:32:58), each with the same frozen
/// numbers: away frames went into the window carrying the last metrics seen, and with no
/// good, drifting or bad frame the three-way tie went to the worst.
@MainActor
final class PostureLogAwayTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func metrics(headDrop: Float = 0, creep: Float = 0) -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                   lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still)
    }

    /// Feeds one frame a second, then a closing frame at 10 s, and returns the metrics line.
    private func line(_ frames: [(PostureState, RawMetrics)]) -> PostureLogEvent? {
        var recorder = PostureLogRecorder()
        var out: [PostureLogEvent] = []
        for (i, frame) in frames.enumerated() {
            out += recorder.metricsEvents(state: frame.0, metrics: frame.1,
                                          baselineTakenAt: t0.addingTimeInterval(-600),
                                          headDropLine: 0.01875, forwardCreepLine: 0.06,
                                          now: t0.addingTimeInterval(Double(i)))
        }
        out += recorder.metricsEvents(state: .absent, metrics: metrics(),
                                      baselineTakenAt: t0.addingTimeInterval(-600),
                                      headDropLine: 0.01875, forwardCreepLine: 0.06,
                                      now: t0.addingTimeInterval(10))
        return out.first { $0.kind == "metrics" }
    }

    func test_anEmptyRoom_isAbsent_withNoPostureNumbers() throws {
        let stale = metrics(headDrop: -0.00473, creep: 0.09198)
        let line = try XCTUnwrap(line(Array(repeating: (.absent, stale), count: 10)))
        XCTAssertEqual(line.value, "absent")
        XCTAssertEqual(line.frames, 10)
        XCTAssertNil(line.headDropMedian)
        XCTAssertNil(line.forwardCreepMedian)
        XCTAssertNil(line.headDropPast)
        XCTAssertNil(line.movementMedian)
        XCTAssertEqual(line.slouched, 0)
    }

    func test_mostlyAway_isAbsent_evenWithABadFrame() throws {
        let frames: [(PostureState, RawMetrics)] =
            [(.bad(since: 0), metrics(headDrop: -0.03)), (.bad(since: 0), metrics(headDrop: -0.03))]
            + Array(repeating: (.absent, metrics(headDrop: -0.03)), count: 8)
        XCTAssertEqual(try XCTUnwrap(line(frames)).value, "absent")
    }

    func test_partlyAway_takesNumbersOnlyFromTheFramesHeWasThere() throws {
        let frames: [(PostureState, RawMetrics)] =
            Array(repeating: (.good, metrics(headDrop: -0.01, creep: 0.01)), count: 6)
            + Array(repeating: (.absent, metrics(headDrop: -0.05, creep: 0.2)), count: 4)
        let line = try XCTUnwrap(line(frames))
        XCTAssertEqual(line.value, "good")
        XCTAssertEqual(line.frames, 10)
        XCTAssertEqual(try XCTUnwrap(line.headDropLow), -0.01, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.forwardCreepHigh), 0.01, accuracy: 1e-6)
        XCTAssertEqual(line.headDropPast?["0.01875"], 0, "the stale frames were past the line; his weren't")
    }

    func test_aTieBetweenJudgedStates_stillSaysTheWorse() throws {
        let frames: [(PostureState, RawMetrics)] =
            Array(repeating: (.good, metrics()), count: 5) + Array(repeating: (.bad(since: 0), metrics()), count: 5)
        XCTAssertEqual(try XCTUnwrap(line(frames)).value, "bad")
    }
}
