import XCTest
@testable import PostureLogic

/// Leaning to one side has a nudge of its own (2026-11-19).
///
/// It counted as a slouch but had no reason of its own, so its nudge said the general "Sit up —
/// reset your posture". On 11-19 that was 4 of 11 nudges, three of them a minute apart through
/// one lean of 0.144 with nothing else past its line. Dave: side lean should nudge, and "You're
/// leaning to one side" is good.
final class SideLeanNudgeTests: XCTestCase {

    private func metrics(lean: Float, creep: Float = 0, headDrop: Float = 0, sink: Float = 0,
                         at t: TimeInterval = 1) -> RawMetrics {
        RawMetrics(timestamp: t, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                   lateralLean: lean, twist: 0, movementLevel: 0, headMovementPattern: .still,
                   shoulderSink: sink)
    }

    private func signals(_ m: RawMetrics) -> Set<NudgeReason> {
        let engine = PostureEngine(thresholds: PostureThresholds())
        engine.update(metrics: m, taskMode: .unknown, trackingQuality: .good)
        return engine.slouchSignals
    }

    private func fire(_ m: RawMetrics) -> NudgeReason? {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 0
        let decision = NudgeEngine(thresholds: thresholds).evaluate(
            state: .bad(since: 0), trackingQuality: .good, movementLevel: 0, taskMode: .unknown,
            currentTime: 1, metrics: m, slouchSignals: signals(m))
        guard case .fire(let reason) = decision else { return nil }
        return reason
    }

    /// 11-19 14:15:03: the lean alone was past its line.
    private let session11_19 = (lean: Float(0.144), creep: Float(0.037), headDrop: Float(-0.002), sink: Float(-0.034))

    func test_aLean_isASignal() {
        let s = session11_19
        XCTAssertEqual(signals(metrics(lean: s.lean, creep: s.creep, headDrop: s.headDrop, sink: s.sink)), [.sideLean])
    }

    func test_underTheLine_isNot() {
        XCTAssertEqual(signals(metrics(lean: PostureThresholds().sideLeanThreshold * 0.9)), [])
    }

    func test_aLeanAlone_isTheNudgesReason() {
        let s = session11_19
        XCTAssertEqual(fire(metrics(lean: s.lean, creep: s.creep, headDrop: s.headDrop, sink: s.sink)), .sideLean)
        XCTAssertEqual(fire(metrics(lean: 0.082)), .sideLean, "11-19 14:25:08, just past the line")
    }

    /// The reason is the one furthest past its own line: a bigger forward lean still wins.
    func test_aBiggerLeanIn_stillWins() {
        XCTAssertEqual(fire(metrics(lean: 0.09, creep: 0.13)), .forwardCreep)
    }

    func test_itsWords() {
        XCTAssertEqual(NudgeReason.sideLean.rawValue, "sideLean")
        XCTAssertEqual(NudgeReason.sideLean.coachingMessage, "Sit up straight — you're leaning to one side")
    }
}
