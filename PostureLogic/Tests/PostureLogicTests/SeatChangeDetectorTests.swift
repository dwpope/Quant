import XCTest
@testable import PostureLogic

/// The seat-change check: near-miss slouches counted, and the sitting judged after a return.
final class SeatChangeDetectorTests: XCTestCase {

    private let thresholds = PostureThresholds()

    private func frame(_ state: PostureState, signals: Set<NudgeReason> = [],
                       headDrop: Float = 0, creep: Float = 0, sink: Float = 0, lean: Float = 0,
                       t: TimeInterval, detector: inout SeatChangeDetector,
                       thresholds customThresholds: PostureThresholds? = nil) -> SeatChangeSuggestion? {
        let metrics = RawMetrics(timestamp: t, forwardCreep: creep, headDrop: headDrop,
                                 shoulderRounding: 0, lateralLean: lean, twist: 0, movementLevel: 0.1,
                                 headMovementPattern: .still, shoulderSink: sink)
        return detector.observe(state: state, signals: signals, metrics: metrics,
                                thresholds: customThresholds ?? thresholds, at: t)
    }

    /// One drift episode that ends in good; returns the suggestion from the closing frame.
    @discardableResult
    private func nearMiss(_ detector: inout SeatChangeDetector, at t: TimeInterval,
                          reason: NudgeReason = .headDrop, headDrop: Float = -0.02,
                          goesBad: Bool = false) -> SeatChangeSuggestion? {
        var result: SeatChangeSuggestion?
        let signals: Set<NudgeReason> = [reason]
        let creep: Float = reason == .forwardCreep ? 0.07 : 0
        let hd: Float = reason == .headDrop ? headDrop : 0
        result = frame(.drifting(since: t), signals: signals, headDrop: hd, creep: creep, t: t, detector: &detector) ?? result
        if goesBad {
            result = frame(.bad(since: t + 1), signals: signals, headDrop: hd, creep: creep, t: t + 1, detector: &detector) ?? result
        }
        result = frame(.good, t: t + 2, detector: &detector) ?? result
        return result
    }

    /// An absence of `length` seconds, then `.good` frames at 10 fps for 25 s with `offset`
    /// applied to the head drop between `from` and `to` seconds after the return. Returns the
    /// last suggestion seen and the time it came at.
    private func absenceAndReturn(_ detector: inout SeatChangeDetector, absentFor length: TimeInterval = 31,
                                  start: TimeInterval = 1000, headDrop offset: Float,
                                  from: TimeInterval = 0, to: TimeInterval = 25,
                                  creep: Float = 0,
                                  thresholds custom: PostureThresholds? = nil) -> (SeatChangeSuggestion?, TimeInterval?) {
        var found: SeatChangeSuggestion?
        var s = start
        while s <= start + length {
            _ = frame(.absent, t: s, detector: &detector)
            s += 1
        }
        let returnAt = start + length + 1
        var k = 0
        while Double(k) / 10 <= 25 {
            let rel = Double(k) / 10
            let hd: Float = (rel >= from && rel <= to) ? offset : 0
            if let r = frame(.good, headDrop: hd, creep: creep, t: returnAt + rel, detector: &detector,
                             thresholds: custom) { found = r }
            k += 1
        }
        return (found, found?.at)
    }

    func test_fiveHeadDropNearMisses_inFiveMinutes_suggest() {
        var d = SeatChangeDetector()
        var results: [SeatChangeSuggestion?] = []
        for i in 0..<5 { results.append(nearMiss(&d, at: 100 + Double(i) * 40)) }
        XCTAssertEqual(results.last??.trigger, .nearMisses(reason: .headDrop, count: 5))
        XCTAssertTrue(results.dropLast().allSatisfy { $0 == nil })
    }

    func test_fourNearMisses_doNotSuggest() {
        var d = SeatChangeDetector()
        for i in 0..<4 { XCTAssertNil(nearMiss(&d, at: 100 + Double(i) * 40)) }
    }

    func test_nearMissesSpreadOver301s_doNotSuggest() {
        var d = SeatChangeDetector()
        // Closing frames land at 102, 177, 252, 327, 403: first to fifth is 301 s.
        for t in [100.0, 175, 250, 325, 401] { XCTAssertNil(nearMiss(&d, at: t)) }
    }

    func test_deepPeak_isNotANearMiss() {
        var d = SeatChangeDetector()
        for i in 0..<5 { XCTAssertNil(nearMiss(&d, at: 100 + Double(i) * 40, headDrop: -0.03)) }
    }

    func test_slouchThatTurnsBad_isNotANearMiss() {
        var d = SeatChangeDetector()
        for i in 0..<5 { XCTAssertNil(nearMiss(&d, at: 100 + Double(i) * 40, goesBad: true)) }
    }

    func test_mixedReasons_countSeparately() {
        var d = SeatChangeDetector()
        for i in 0..<3 { XCTAssertNil(nearMiss(&d, at: 100 + Double(i) * 40)) }
        for i in 0..<2 { XCTAssertNil(nearMiss(&d, at: 300 + Double(i) * 40, reason: .forwardCreep)) }
    }

    func test_suggestsOnce_thenQuietUntilNextReturn() {
        var d = SeatChangeDetector()
        var last: SeatChangeSuggestion?
        for i in 0..<5 { last = nearMiss(&d, at: 100 + Double(i) * 40) }
        XCTAssertNotNil(last)
        for i in 0..<5 { XCTAssertNil(nearMiss(&d, at: 400 + Double(i) * 40)) }

        d.quietUntilNextReturn()
        for i in 0..<5 { XCTAssertNil(nearMiss(&d, at: 700 + Double(i) * 40)) }

        // A return from a long absence ends the quiet; the head sits where it should.
        let (back, _) = absenceAndReturn(&d, start: 1000, headDrop: 0)
        XCTAssertNil(back)
        var again: SeatChangeSuggestion?
        for i in 0..<5 { again = nearMiss(&d, at: 1200 + Double(i) * 40) }
        XCTAssertEqual(again?.trigger, .nearMisses(reason: .headDrop, count: 5))
    }

    func test_forgetNearMisses_startsCountAgain() {
        var d = SeatChangeDetector()
        var last: SeatChangeSuggestion?
        for i in 0..<5 { last = nearMiss(&d, at: 100 + Double(i) * 40) }
        XCTAssertEqual(last?.trigger, .nearMisses(reason: .headDrop, count: 5))

        d.forgetNearMisses()
        for i in 0..<4 { XCTAssertNil(nearMiss(&d, at: 400 + Double(i) * 40)) }
        let fifth = nearMiss(&d, at: 400 + 4 * 40)
        XCTAssertEqual(fifth?.trigger, .nearMisses(reason: .headDrop, count: 5))
    }

    /// The pipeline may forget mid-drift (it closes a question on a frame that is drifting): the
    /// deep peak of that drift must not follow into the next episode and stop it being a near-miss.
    func test_forgetMidDrift_doesNotLeakPeak() {
        var d = SeatChangeDetector()
        _ = frame(.drifting(since: 90), signals: [.headDrop], headDrop: -0.06, t: 90, detector: &d)
        d.forgetNearMisses()
        var last: SeatChangeSuggestion?
        for i in 0..<5 { last = nearMiss(&d, at: 100 + Double(i) * 40) }
        XCTAssertEqual(last?.trigger, .nearMisses(reason: .headDrop, count: 5))

        var q = SeatChangeDetector()
        _ = frame(.drifting(since: 90), signals: [.headDrop], headDrop: -0.06, t: 90, detector: &q)
        q.quietUntilNextReturn()
        q.forgetNearMisses()
        var lastQ: SeatChangeSuggestion?
        for i in 0..<5 { lastQ = nearMiss(&q, at: 100 + Double(i) * 40) }
        XCTAssertEqual(lastQ?.trigger, .nearMisses(reason: .headDrop, count: 5))
    }

    /// A drift in which no frame had metrics can't be shown to have stayed within 1.5 lines.
    func test_driftWithoutMetrics_isNotANearMiss() {
        var d = SeatChangeDetector()
        var results: [SeatChangeSuggestion?] = []
        for i in 0..<6 {
            let t = 100 + Double(i) * 40
            _ = d.observe(state: .drifting(since: t), signals: [.headDrop], metrics: nil,
                          thresholds: thresholds, at: t)
            results.append(d.observe(state: .good, signals: [], metrics: nil,
                                     thresholds: thresholds, at: t + 2))
        }
        XCTAssertTrue(results.allSatisfy { $0 == nil })
    }

    func test_returnWithHeadOffset_suggestsOnReturn() {
        var d = SeatChangeDetector()
        let (suggestion, at) = absenceAndReturn(&d, start: 1000, headDrop: -0.012)
        XCTAssertEqual(suggestion?.trigger, .onReturn(reasons: [.headDrop]))
        XCTAssertEqual(at ?? 0, 1000 + 31 + 1 + 25, accuracy: 0.001)
    }

    func test_returnWithinTolerance_staysSilent() {
        var d = SeatChangeDetector()
        XCTAssertNil(absenceAndReturn(&d, headDrop: -0.005).0)
    }

    func test_returnOffsetOnlyInSecondWindow_staysSilent() {
        var d = SeatChangeDetector()
        XCTAssertNil(absenceAndReturn(&d, headDrop: -0.012, from: 15, to: 25).0)
    }

    func test_uprightOffset_neverCounts() {
        var d = SeatChangeDetector()
        XCTAssertNil(absenceAndReturn(&d, headDrop: 0.02, creep: -0.05).0)
    }

    func test_shortAbsence_noReturnCheck() {
        var d = SeatChangeDetector()
        XCTAssertNil(absenceAndReturn(&d, absentFor: 10, headDrop: -0.012).0)
    }

    func test_noJudging_whileCalibrating() {
        var d = SeatChangeDetector()
        for k in 0..<300 {
            XCTAssertNil(frame(.calibrating, headDrop: -0.012, t: 100 + Double(k) / 10, detector: &d))
        }
        // A return straight into calibrating is not judged either.
        for s in 0...31 { _ = frame(.absent, t: 1000 + Double(s), detector: &d) }
        for k in 0...250 {
            XCTAssertNil(frame(.calibrating, headDrop: -0.012, t: 1032 + Double(k) / 10, detector: &d))
        }
    }

    func test_tolerances_followThresholds() {
        var d = SeatChangeDetector()
        var wide = PostureThresholds()
        wide.headDropThreshold = 0.04
        XCTAssertNil(absenceAndReturn(&d, headDrop: -0.012, thresholds: wide).0)
    }

    // MARK: Fix wave: quiet, carry-over, evidence

    func test_dismissDuringReturnWindow_doesNotAskAgain() {
        var d = SeatChangeDetector()
        for s in 0...31 { _ = frame(.absent, t: 1000 + Double(s), detector: &d) }
        let returnAt: TimeInterval = 1032
        var found: SeatChangeSuggestion?
        for k in 0...250 {
            let rel = Double(k) / 10
            if k == 100 { d.quietUntilNextReturn() }
            if let r = frame(.good, headDrop: -0.012, t: returnAt + rel, detector: &d) { found = r }
        }
        XCTAssertNil(found, "answering mid-window means no question when the window ends")
    }

    func test_nearMissesBeforeLongAbsence_doNotCarry() {
        var d = SeatChangeDetector()
        for i in 0..<4 { XCTAssertNil(nearMiss(&d, at: 100 + Double(i) * 40)) }
        XCTAssertNil(absenceAndReturn(&d, start: 230, headDrop: 0).0)
        XCTAssertNil(nearMiss(&d, at: 290), "the fifth near-miss is the first of a new count")
    }

    func test_nearMissSuggestion_carriesPeaks() {
        var d = SeatChangeDetector()
        var last: SeatChangeSuggestion?
        for i in 0..<5 { last = nearMiss(&d, at: 100 + Double(i) * 40, headDrop: -0.02) }
        XCTAssertEqual(last?.evidence["headDrop"], [0.02, 0.02, 0.02, 0.02, 0.02])
    }

    func test_returnSuggestion_carriesWindowMedians() {
        var d = SeatChangeDetector()
        let (suggestion, _) = absenceAndReturn(&d, start: 1000, headDrop: -0.012)
        XCTAssertEqual(suggestion?.evidence["headDrop"], [0.012, 0.012])
        XCTAssertNil(suggestion?.evidence["forwardCreep"])
    }
}
