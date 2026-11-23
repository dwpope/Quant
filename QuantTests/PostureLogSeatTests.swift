import XCTest
import PostureLogic
@testable import Quant

/// The posture log says where the seat question would ask, and how each question closed, plus
/// the side lean and shoulder sink medians the metrics line was missing.
@MainActor
final class PostureLogSeatTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func metrics(lean: Float = 0, sink: Float = 0) -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                   lateralLean: abs(lean), twist: 0, movementLevel: 0, headMovementPattern: .still,
                   lateralLeanSigned: lean, shoulderSink: sink)
    }

    func test_nearMissSuggestion_inLogOnly_writesWouldAsk() throws {
        let suggestion = SeatChangeSuggestion(trigger: .nearMisses(reason: .headDrop, count: 5), at: 1_800_000_123)
        let line = PostureLogEvent.seatEvent(suggestion, mode: .logOnly)
        XCTAssertEqual(line.kind, "seat")
        XCTAssertEqual(line.value, "would-ask")
        XCTAssertEqual(line.trigger, "nearMisses")
        XCTAssertEqual(line.reason, "headDrop")
        XCTAssertEqual(line.count, 5)
        XCTAssertEqual(line.t, 1_800_000_123)
    }

    func test_askMode_writesAsked() {
        let suggestion = SeatChangeSuggestion(trigger: .nearMisses(reason: .sideLean, count: 5), at: 1)
        XCTAssertEqual(PostureLogEvent.seatEvent(suggestion, mode: .ask).value, "asked")
    }

    func test_onReturnSuggestion_listsReasonsSorted() {
        let suggestion = SeatChangeSuggestion(trigger: .onReturn(reasons: [.sink, .headDrop]), at: 2)
        let line = PostureLogEvent.seatEvent(suggestion, mode: .logOnly)
        XCTAssertEqual(line.trigger, "onReturn")
        XCTAssertEqual(line.reason, "headDrop,sink")
        XCTAssertNil(line.count)
    }

    func test_askedLine_recordsVia() {
        let suggestion = SeatChangeSuggestion(trigger: .nearMisses(reason: .sideLean, count: 5), at: 1)
        XCTAssertEqual(PostureLogEvent.seatEvent(suggestion, mode: .ask, via: "queued").via, "queued")
        XCTAssertNil(PostureLogEvent.seatEvent(suggestion, mode: .logOnly).via)
    }

    func test_evidence_isWrittenRoundedToFiveDecimals() throws {
        let suggestion = SeatChangeSuggestion(
            trigger: .onReturn(reasons: [.headDrop]), at: 3,
            evidence: ["headDrop": [0.0123456789, 0.02]])
        let line = PostureLogEvent.seatEvent(suggestion, mode: .logOnly)
        XCTAssertEqual(try XCTUnwrap(line.evidence?["headDrop"]), [0.01235, 0.02])
        let json = String(data: try JSONEncoder().encode(line), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"evidence\""))
        let bare = PostureLogEvent.seatEvent(SeatChangeSuggestion(trigger: .onReturn(reasons: [.sink]), at: 4), mode: .ask)
        XCTAssertNil(bare.evidence, "no evidence, no field")
    }

    func test_closedLine() {
        let line = PostureLogEvent.seatEvent(closed: .timeout, at: 1_800_000_500)
        XCTAssertEqual(line.kind, "seat")
        XCTAssertEqual(line.value, "closed:timeout")
        XCTAssertEqual(line.t, 1_800_000_500)
    }

    func test_metricsLine_hasSideLeanAndSinkMedians() throws {
        var recorder = PostureLogRecorder()
        var out: [PostureLogEvent] = []
        for (i, lean) in [Float(0.01), 0.02, 0.03].enumerated() {
            out += recorder.metricsEvents(state: .good, metrics: metrics(lean: lean, sink: lean * 2),
                                          baselineTakenAt: t0.addingTimeInterval(-600),
                                          headDropLine: 0.01875, forwardCreepLine: 0.06,
                                          now: t0.addingTimeInterval(Double(i)))
        }
        out += recorder.metricsEvents(state: .good, metrics: metrics(), baselineTakenAt: t0.addingTimeInterval(-600),
                                      headDropLine: 0.01875, forwardCreepLine: 0.06,
                                      now: t0.addingTimeInterval(10))
        let line = try XCTUnwrap(out.first { $0.kind == "metrics" })
        XCTAssertEqual(try XCTUnwrap(line.sideLeanMedian), 0.02, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.shoulderSinkMedian), 0.04, accuracy: 1e-6)
    }
}
