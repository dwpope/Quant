import Foundation
import PostureLogic

/// A day's posture as a timeline: when you sat well, when you slouched, and when you were
/// nudged (2026-10-13). Pure; built from the posture log's lines.
///
/// Dave asked to see on the phone when his posture was good and when it went bad. The posture
/// log already has it: a line whenever the posture, the nudge decision or the task changes. A
/// state lasts until the next state line. The log doesn't say when the app closed, so no line of
/// any kind for `maxGap` means it had, and the state is taken to end at its last line; within an
/// hour of real use the longest quiet was 7 minutes (12 Oct). Until then, the state going on runs
/// to now.
///
/// Since 2026-10-16 the log also writes a tick a minute while nothing changes, so a log with
/// ticks in it has gone quiet only when the camera stopped: `maxGapWithTicks` is enough. Before,
/// sitting well for over 10 minutes read as the app having closed.
nonisolated struct PostureTimeline: Equatable {

    /// What a stretch of time is drawn as.
    enum Band: String, CaseIterable {
        case good, drifting, bad
        /// Away or calibrating: no posture to judge.
        case away
    }

    struct Segment: Equatable {
        let start: Date
        let end: Date
        let band: Band
    }

    struct Nudge: Equatable {
        let at: Date
        let reason: NudgeReason
    }

    let segments: [Segment]
    let nudges: [Nudge]

    /// No line for this long and the app had closed (drawn up to its last line), in a log
    /// written before ticks (2026-10-16).
    static let maxGap: TimeInterval = 600
    /// The same in a log with ticks: a line comes at least every `PostureLogRecorder.tickEvery`
    /// while the camera runs.
    static let maxGapWithTicks: TimeInterval = 150

    init(events: [PostureLogEvent], now: Date) {
        var segments: [Segment] = []
        var nudges: [Nudge] = []
        var current: (band: Band, since: TimeInterval)?
        var lastLine: TimeInterval?
        let maxGap = events.contains { $0.kind == "tick" } ? Self.maxGapWithTicks : Self.maxGap

        func close(at end: TimeInterval) {
            guard let open = current, end > open.since else { current = nil; return }
            let start = Date(timeIntervalSince1970: open.since), stop = Date(timeIntervalSince1970: end)
            if let last = segments.last, last.band == open.band, last.end == start {
                segments[segments.count - 1] = Segment(start: last.start, end: stop, band: open.band)
            } else {
                segments.append(Segment(start: start, end: stop, band: open.band))
            }
            current = nil
        }

        // Only lines written from camera frames say the camera was running: how a nudge reached
        // the Watch doesn't, and a replay's nudges still send one (2026-10-16).
        for event in events.sorted(by: { $0.t < $1.t }) where event.kind != "watch" {
            if let last = lastLine, event.t - last > maxGap {
                close(at: last)
            }
            lastLine = event.t
            switch event.kind {
            // A tick says the state too, so the band picks up again after a gap with the posture
            // unchanged: only a change writes a state line.
            case "state", "tick":
                let band = Self.band(of: event.value)
                if current?.band != band {
                    close(at: event.t)
                    current = (band, event.t)
                }
            case "nudge":
                if event.value.hasPrefix("fire:"),
                   let reason = NudgeReason(rawValue: String(event.value.dropFirst("fire:".count))) {
                    nudges.append(Nudge(at: Date(timeIntervalSince1970: event.t), reason: reason))
                }
            default:
                break
            }
        }
        if let last = lastLine {
            let stillWriting = now.timeIntervalSince1970 - last <= maxGap
            close(at: stillWriting ? now.timeIntervalSince1970 : last)
        }
        self.segments = segments
        self.nudges = nudges
    }

    private static func band(of state: String) -> Band {
        switch state {
        case "good": return .good
        case "drifting": return .drifting
        case "bad": return .bad
        default: return .away
        }
    }

    /// Seconds in a band.
    func total(_ band: Band) -> TimeInterval {
        segments.filter { $0.band == band }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// Seconds slouched: drifting and bad.
    var slouched: TimeInterval { total(.drifting) + total(.bad) }

    /// The share of the judged time (not away) spent sitting well, or nil with none judged.
    var goodShare: Double? {
        let judged = total(.good) + slouched
        return judged > 0 ? total(.good) / judged : nil
    }

    /// From the first stretch to the last, for the chart's span.
    var span: ClosedRange<Date>? {
        guard let first = segments.first, let last = segments.last else { return nil }
        return first.start...last.end
    }

    // MARK: - Zoomed in (2026-11-19)

    /// The last hour of the band, up to its last stretch, or all of it when shorter: what the
    /// cards show, so a slouch is wide enough to see by evening (on 11-18, 437 of the day's 439
    /// were under a point wide across the whole day).
    var lastHour: ClosedRange<Date>? {
        guard let span = judgedSpan ?? span else { return nil }
        return max(span.lowerBound, span.upperBound.addingTimeInterval(-3600))...span.upperBound
    }

    /// From the first stretch judged to the last: a moment away at either end, as when the app
    /// was opened at 09:49 on 11-18 to choose the log's folder, doesn't stretch the zoomed views
    /// over hours with nothing in them. Nil with nothing judged.
    var judgedSpan: ClosedRange<Date>? {
        let judged = segments.filter { $0.band != .away }
        guard let first = judged.first, let last = judged.last else { return nil }
        return first.start...last.end
    }

    /// The stretches within `range`, cut at its ends.
    func segments(in range: ClosedRange<Date>) -> [Segment] {
        segments.compactMap { segment in
            let start = max(segment.start, range.lowerBound), end = min(segment.end, range.upperBound)
            return start < end ? Segment(start: start, end: end, band: segment.band) : nil
        }
    }

    /// The share of the judged time within `range` spent sitting well, or nil with none judged.
    /// Away doesn't count against you, so a short sitting isn't a bad hour.
    func goodShare(in range: ClosedRange<Date>) -> Double? {
        var good: TimeInterval = 0, judged: TimeInterval = 0
        for segment in segments(in: range) where segment.band != .away {
            let seconds = segment.end.timeIntervalSince(segment.start)
            judged += seconds
            if segment.band == .good { good += seconds }
        }
        return judged > 0 ? good / judged : nil
    }

    /// One of the day's hours, and its share sitting well (nil when away all of it).
    struct Hour: Equatable {
        let start: Date
        let share: Double?
    }

    /// Each clock hour from the first stretch judged to the last, for the whole day's
    /// percentages.
    func hours(calendar: Calendar = .current) -> [Hour] {
        guard let span = judgedSpan ?? span, let first = calendar.dateInterval(of: .hour, for: span.lowerBound)?.start
        else { return [] }
        var hours: [Hour] = []
        var start = first
        while start < span.upperBound {
            let end = start.addingTimeInterval(3600)
            hours.append(Hour(start: start, share: goodShare(in: start...end)))
            start = end
        }
        return hours
    }

    /// A share as a whole percentage, or a dash with nothing judged.
    static func percent(_ share: Double?) -> String {
        share.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
    }

    /// The card's line under the last hour: "Last hour: sat well 84% · today 88% · 3 nudges".
    var lastHourSummary: String? {
        guard let lastHour, goodShare != nil else { return nil }
        let nudgeWord = nudges.count == 1 ? "nudge" : "nudges"
        return "Last hour: sat well \(Self.percent(goodShare(in: lastHour))) · "
            + "today \(Self.percent(goodShare)) · \(nudges.count) \(nudgeWord)"
    }

    /// One line for the card: "Sat well 88% · slouched 7 min · 3 nudges", or nil with nothing
    /// judged yet.
    var summary: String? {
        guard let share = goodShare else { return nil }
        let nudgeWord = nudges.count == 1 ? "nudge" : "nudges"
        return "Sat well \(Int((share * 100).rounded()))% · slouched \(Self.minutes(slouched)) · "
            + "\(nudges.count) \(nudgeWord)"
    }

    /// Whole minutes, or "under a minute".
    static func minutes(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return m < 1 ? "under a minute" : "\(m) min"
    }

    /// A nudge's reason in a word or two, for the list under the chart.
    static func label(for reason: NudgeReason) -> String {
        switch reason {
        case .forwardCreep: return "Leaning in"
        case .headDrop: return "Head dropped"
        case .sink: return "Sinking in the chair"
        case .sideLean: return "Leaning to one side"
        case .sustainedSlouch: return "Slouching"
        case .headTurned: return "Head turned"
        }
    }
}
