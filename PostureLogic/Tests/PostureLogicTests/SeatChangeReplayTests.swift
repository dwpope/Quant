import XCTest
@testable import PostureLogic

/// The seat-change check replayed on Dave's real log of 2026-11-23, build 105: it should have asked
/// before he recalibrated by hand, and say nothing after.
///
/// The log holds state lines, not frames, so a replay frame exists only at each state line's `t`.
/// That is enough for near-misses (judged on transitions and peaks) but not for the on-return
/// check, whose 5-15 s and 15-25 s medians need frames the log doesn't have.
final class SeatChangeReplayTests: XCTestCase {

    // 11:26:45 and 12:18:53 on 2026-11-23, Europe/London (GMT).
    private let sessionStart: TimeInterval = 1795433205
    private let sessionEnd: TimeInterval = 1795436333
    private let askedNoEarlierThan: TimeInterval = 1795434140   // 11:42:20
    private let recalibrationStarted: TimeInterval = 1795434209.09  // 11:43:29
    private let newBaselineInForce: TimeInterval = 1795434217.9014149  // 11:43:37

    /// The build-105 settings line: head drop 0.01875, the rest are the defaults.
    private let thresholds = PostureThresholds()

    private struct LogState {
        let t: TimeInterval
        let value: String
        let headDrop: Float, forwardCreep: Float, shoulderSink: Float, lateralShift: Float
    }

    private func state(_ value: String, at t: TimeInterval) -> PostureState? {
        switch value {
        case "good": return .good
        case "drifting": return .drifting(since: t)
        case "bad": return .bad(since: t)
        case "absent": return .absent
        case "calibrating": return .calibrating
        default: return nil
        }
    }

    /// Replays state lines. A drifting frame's signals are the `pending:` reasons within 0.5 s of its `t`.
    /// `resetAt`, if given, calls `reset()` just before the first frame at or after it.
    private func replay(_ states: [LogState], pending: [(t: TimeInterval, reason: String)],
                        resetAt: TimeInterval? = nil) -> [SeatChangeSuggestion] {
        var detector = SeatChangeDetector()
        var found: [SeatChangeSuggestion] = []
        var didReset = false
        for line in states {
            if let resetAt, !didReset, line.t >= resetAt {
                detector.reset()
                didReset = true
            }
            guard let s = state(line.value, at: line.t) else { continue }
            var signals: Set<NudgeReason> = []
            if case .drifting = s {
                for p in pending where abs(p.t - line.t) <= 0.5 {
                    if let r = NudgeReason(rawValue: p.reason) { signals.insert(r) }
                }
            }
            let metrics = RawMetrics(timestamp: line.t, forwardCreep: line.forwardCreep, headDrop: line.headDrop,
                                     shoulderRounding: 0, lateralLean: abs(line.lateralShift), twist: 0,
                                     movementLevel: 0, headMovementPattern: .still,
                                     shoulderSink: line.shoulderSink)
            if let suggestion = detector.observe(state: s, signals: signals, metrics: metrics,
                                                 thresholds: thresholds, at: line.t) {
                found.append(suggestion)
            }
        }
        return found
    }

    private func nov23() -> (states: [LogState], pending: [(t: TimeInterval, reason: String)]) {
        let states = SeatChange20261123.states.map {
            LogState(t: $0.t, value: $0.value, headDrop: $0.headDrop, forwardCreep: $0.forwardCreep,
                     shoulderSink: $0.shoulderSink, lateralShift: $0.lateralShift)
        }
        return (states, SeatChange20261123.pendingNudges.map { (t: $0.t, reason: $0.reason) })
    }

    func test_nov23_asksBeforeDaveRecalibrated() throws {
        let log = nov23()
        let first = try XCTUnwrap(replay(log.states, pending: log.pending).first)
        XCTAssertEqual(first.trigger, .nearMisses(reason: .headDrop, count: 5))
        XCTAssertGreaterThanOrEqual(first.at, askedNoEarlierThan)
        XCTAssertLessThan(first.at, recalibrationStarted)
    }

    func test_nov23_silentAfterRecalibration() {
        let log = nov23()
        let found = replay(log.states, pending: log.pending, resetAt: newBaselineInForce)
        XCTAssertTrue(found.filter { $0.at >= newBaselineInForce && $0.at <= sessionEnd }.isEmpty,
                      "asked again after the recalibration: \(found)")
    }

    /// Runs only with `SEAT_REPLAY_LOG=<jsonl>`; prints suggestions per session and per hour. Asserts nothing.
    func test_frequencyReport_olderSessions() throws {
        guard let path = ProcessInfo.processInfo.environment["SEAT_REPLAY_LOG"] else {
            throw XCTSkip("SEAT_REPLAY_LOG not set")
        }
        let text = try String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8)
        var states: [LogState] = []
        var pending: [(t: TimeInterval, reason: String)] = []
        for raw in text.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  let kind = obj["kind"] as? String, let t = obj["t"] as? Double,
                  let value = obj["value"] as? String else { continue }
            func f(_ key: String) -> Float { (obj[key] as? Double).map(Float.init) ?? 0 }
            if kind == "state" {
                states.append(LogState(t: t, value: value, headDrop: f("headDrop"), forwardCreep: f("forwardCreep"),
                                       shoulderSink: f("shoulderSink"), lateralShift: f("lateralShift")))
            } else if kind == "nudge", value.hasPrefix("pending:") {
                pending.append((t: t, reason: String(value.dropFirst("pending:".count))))
            }
        }
        states.sort { $0.t < $1.t }

        var sessions: [[LogState]] = []
        for s in states {
            if let last = sessions.last?.last, s.t - last.t <= 600 { sessions[sessions.count - 1].append(s) }
            else { sessions.append([s]) }
        }
        let clock = DateFormatter()
        clock.timeZone = TimeZone(identifier: "Europe/London")
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var report = "SEAT-CHANGE FREQUENCY REPORT (\(sessions.count) sessions, split on gaps over 600 s)\n"
        for (i, session) in sessions.enumerated() {
            let from = session.first!.t, to = session.last!.t
            let found = replay(session, pending: pending.filter { $0.t >= from - 1 && $0.t <= to + 1 })
            let hours = (to - from) / 3600
            let rate = hours > 0 ? Double(found.count) / hours : 0
            report += String(format: "session %d  %@ - %@  %.2f h  suggestions %d  %.2f per hour\n", i + 1,
                             clock.string(from: Date(timeIntervalSince1970: from)),
                             clock.string(from: Date(timeIntervalSince1970: to)), hours, found.count, rate)
            for s in found {
                report += "    \(clock.string(from: Date(timeIntervalSince1970: s.at)))  \(s.trigger)\n"
            }
        }
        print(report)
    }
}
