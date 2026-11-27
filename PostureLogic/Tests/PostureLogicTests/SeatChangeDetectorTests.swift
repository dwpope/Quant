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

    // MARK: After a calibration, and while forward lean builds (2026-11-27)

    /// Session 15 asked at 09:08:55 and 09:09:46, 3 and 4 minutes after Dave calibrated: a fresh
    /// calibration is how he sits now, so the seat can't have moved yet.
    func test_afterACalibration_nearMissesInTheFirstTenMinutes_dontCount() {
        var d = SeatChangeDetector()
        d.reset()
        _ = frame(.good, t: 1000, detector: &d)
        for i in 0..<6 { XCTAssertNil(nearMiss(&d, at: 1100 + Double(i) * 40)) }
        var later: SeatChangeSuggestion?
        for i in 0..<5 { later = nearMiss(&d, at: 1600 + Double(i) * 40) ?? later }
        XCTAssertEqual(later?.trigger, .nearMisses(reason: .headDrop, count: 5),
                       "only the near-misses after the ten minutes count")
    }

    /// The calibration's ten minutes outlast Log only's restart of the count.
    func test_theCalibrationGrace_survivesForgettingNearMisses() {
        var d = SeatChangeDetector()
        d.reset()
        _ = frame(.good, t: 1000, detector: &d)
        d.forgetNearMisses()
        for i in 0..<5 { XCTAssertNil(nearMiss(&d, at: 1100 + Double(i) * 40)) }
    }

    /// Five head-drop near-misses, 40 s apart, in the last three minutes of an 8-minute stretch of
    /// good frames whose forward lean runs from `creepFrom` to `creepTo`. Returns every suggestion.
    private func nearMissesWhileCreeping(from creepFrom: Float, to creepTo: Float) -> [SeatChangeSuggestion] {
        var d = SeatChangeDetector()
        var found: [SeatChangeSuggestion] = []
        let start: TimeInterval = 100, length: TimeInterval = 500
        var s = start
        while s <= start + length {
            let creep = creepFrom + (creepTo - creepFrom) * Float((s - start) / length)
            let drifting = (320...480).contains(s - start) && Int(s - start) % 40 == 0
            let state: PostureState = drifting ? .drifting(since: s) : .good
            if let r = frame(state, signals: drifting ? [.headDrop] : [], headDrop: drifting ? -0.02 : 0,
                             creep: creep, t: s, detector: &d) { found.append(r) }
            s += 1
        }
        return found
    }

    /// 09:23–09:29 on 11-27: head drop kept brushing its line while forward lean climbed to
    /// bad. That is a slouch building, not a moved seat, which shifts readings once.
    func test_nearMisses_whileForwardLeanBuilds_dontAsk() {
        XCTAssertEqual(nearMissesWhileCreeping(from: -0.06, to: 0.0), [])
    }

    /// 11-23's real seat change: forward lean steady through the near-misses.
    func test_nearMisses_withForwardLeanSteady_stillAsk() {
        let found = nearMissesWhileCreeping(from: -0.02, to: -0.02)
        XCTAssertEqual(found.first?.trigger, .nearMisses(reason: .headDrop, count: 5))
    }

    /// Forward lean easing back towards upright is no slouch building.
    func test_nearMisses_withForwardLeanEasing_stillAsk() {
        let found = nearMissesWhileCreeping(from: 0.0, to: -0.06)
        XCTAssertEqual(found.first?.trigger, .nearMisses(reason: .headDrop, count: 5))
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

    // MARK: Short dropouts after a return (2026-11-26, 16:06)

    /// Away 46 s, back for 5 s, tracking lost for 2 s, then sitting on: the shape of 11-26 at 16:06,
    /// when Dave had moved his seat. Frames at 10 fps; returns every suggestion with its time.
    private func returnWithDropout(_ d: inout SeatChangeDetector, creep: Float,
                                  dropout: TimeInterval = 2) -> [SeatChangeSuggestion] {
        var found: [SeatChangeSuggestion] = []
        for s in 0...46 { _ = frame(.absent, t: 1000 + Double(s), detector: &d) }
        let back: TimeInterval = 1047
        for k in 0..<50 {
            if let r = frame(.good, creep: creep, t: back + Double(k) / 10, detector: &d) { found.append(r) }
        }
        var k = 0
        while Double(k) / 10 < dropout {
            if let r = frame(.absent, t: back + 5 + Double(k) / 10, detector: &d) { found.append(r) }
            k += 1
        }
        for k in 0...400 {
            if let r = frame(.good, creep: creep, t: back + 5 + dropout + Double(k) / 10, detector: &d) {
                found.append(r)
            }
        }
        return found
    }

    func test_shortDropoutAfterReturn_pausesTheCheck_ratherThanCancelling() throws {
        var d = SeatChangeDetector()
        let found = returnWithDropout(&d, creep: 0.077)
        XCTAssertEqual(found.count, 1)
        let s = try XCTUnwrap(found.first)
        XCTAssertEqual(s.trigger, .onReturn(reasons: [.forwardCreep]))
        XCTAssertEqual(s.at, 1047 + 25 + 2, accuracy: 0.11, "the 2 s away don't count towards the 25 s")
    }

    func test_shortDropoutAfterReturn_withinTolerance_staysSilent() {
        var d = SeatChangeDetector()
        XCTAssertTrue(returnWithDropout(&d, creep: 0.02).isEmpty)
    }

    func test_longDropoutAfterReturn_startsAFreshCheck() throws {
        var d = SeatChangeDetector()
        let found = returnWithDropout(&d, creep: 0.077, dropout: 31)
        let s = try XCTUnwrap(found.first)
        XCTAssertEqual(s.at, 1047 + 5 + 31 + 25, accuracy: 0.11, "judged from the second return")
    }
}
