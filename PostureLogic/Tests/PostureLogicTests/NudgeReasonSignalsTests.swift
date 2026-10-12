import XCTest
@testable import PostureLogic

/// A nudge's reason is what made it a slouch (2026-10-11).
///
/// The reason was picked by comparing each metric with its plain line, without the exceptions
/// the posture engine applies: a sink that doesn't count while reclined, a head drop that
/// doesn't count with the chair turned, the higher forward line while reading. So a nudge could
/// give advice for something that wasn't counted. The posture engine now says which slouch
/// signals tripped, and only those can be the reason.
final class NudgeReasonSignalsTests: XCTestCase {

    private func fire(_ metrics: RawMetrics, signals: Set<NudgeReason>?) -> NudgeReason? {
        var thresholds = PostureThresholds()
        thresholds.slouchDurationBeforeNudge = 1
        let e = NudgeEngine(thresholds: thresholds)
        var reason: NudgeReason?
        for t in stride(from: 0.0, through: 3, by: 1) {
            let d = e.evaluate(state: .bad(since: 0), trackingQuality: .good, movementLevel: 0,
                               taskMode: .unknown, currentTime: t, metrics: metrics,
                               slouchSignals: signals)
            if case .fire(let r) = d { reason = r; break }
        }
        return reason
    }

    private let reclinedSinkAndCreep = RawMetrics(
        timestamp: 0, forwardCreep: 0.07, headDrop: 0, shoulderRounding: 0, lateralLean: 0, twist: 0,
        movementLevel: 0, headMovementPattern: .still, shoulderSink: 0.08)

    /// The sink is the biggest number, but it isn't counted while reclined: leaning in is.
    func test_onlyASignalThatTripped_canBeTheReason() {
        XCTAssertEqual(fire(reclinedSinkAndCreep, signals: [.forwardCreep]), .forwardCreep)
    }

    /// A slouch counted by something with no advice of its own (rounding, twist, lean).
    func test_noSlouchSignal_isTheGeneralReason() {
        XCTAssertEqual(fire(reclinedSinkAndCreep, signals: []), .sustainedSlouch)
    }

    /// Callers that don't say keep the old comparison.
    func test_withoutSignals_theBiggestOverItsLineWins() {
        XCTAssertEqual(fire(reclinedSinkAndCreep, signals: nil), .sink)
    }

    func test_thePostureEngine_saysWhichSignalsTripped() {
        let engine = PostureEngine(thresholds: PostureThresholds())
        engine.update(metrics: reclinedSinkAndCreep, taskMode: .unknown, trackingQuality: .good, reclined: true)
        XCTAssertEqual(engine.slouchSignals, [.forwardCreep], "the sink doesn't count while reclined")
        let reading = RawMetrics(timestamp: 1, forwardCreep: 0.07, headDrop: 0, shoulderRounding: 0,
                                 lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still)
        engine.update(metrics: reading, taskMode: .reading, trackingQuality: .good)
        XCTAssertEqual(engine.slouchSignals, [], "0.07 is under the reading line, 0.078")
    }
}
