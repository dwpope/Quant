import XCTest
import PostureLogic
@testable import Quant

/// The day's band, zoomed to the last hour, with a share for each hour of the whole day
/// (2026-11-19).
///
/// By evening the day's band was too thin to read: on 11-18, 437 of its 439 slouches were under
/// a point wide. Dave wanted one band still, "more zoomed in with the ability to expand to see the
/// whole day", and asked whether percentages would help to see the whole day.
final class PostureTimelineZoomTests: XCTestCase {

    /// On the hour (GMT), so the hours are easy to read.
    private let h0: TimeInterval = 1_791_637_200

    private func state(_ value: String, at s: TimeInterval) -> PostureLogEvent {
        PostureLogEvent(t: h0 + s, kind: "state", value: value)
    }
    private func tick(_ value: String, at s: TimeInterval) -> PostureLogEvent {
        PostureLogEvent(t: h0 + s, kind: "tick", value: value)
    }
    private func date(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: h0 + s) }

    private var gmt: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        return c
    }

    /// 9:00 to 10:30, with ticks so the minutes between lines count: good, then 10 minutes
    /// slouched from 9:50, good again, away from 10:10 to 10:20, good to 10:30.
    private var day: PostureTimeline {
        var events = [state("good", at: 0), state("drifting", at: 3000), state("good", at: 3600),
                      state("absent", at: 4200), state("good", at: 4800)]
        for s in stride(from: 60.0, to: 5400, by: 60) where !events.contains(where: { $0.t == h0 + s }) {
            events.append(tick(s < 3000 || (s > 3600 && s < 4200) || s > 4800 ? "good"
                               : s < 3600 ? "drifting" : "absent", at: s))
        }
        return PostureTimeline(events: events, now: date(5400))
    }

    // MARK: - The last hour

    func test_theLastHour_endsWithTheLastStretch() {
        XCTAssertEqual(day.lastHour, date(1800)...date(5400))
    }

    func test_aDayShorterThanAnHour_isAllShown() {
        let short = PostureTimeline(events: [state("good", at: 0)], now: date(600))
        XCTAssertEqual(short.lastHour, date(0)...date(600))
    }

    func test_theBand_isCutToTheHour() {
        let cut = day.segments(in: date(1800)...date(5400))
        XCTAssertEqual(cut.first, .init(start: date(1800), end: date(3000), band: .good))
        XCTAssertEqual(cut.last?.end, date(5400))
        XCTAssertEqual(cut.map(\.band), [.good, .drifting, .good, .away, .good])
    }

    /// Of the time judged: away doesn't count against you.
    func test_theHoursShare_leavesOutAway() throws {
        // 9:30-10:30: 40 min judged good of 50 judged (10 min away).
        let share = try XCTUnwrap(day.goodShare(in: date(1800)...date(5400)))
        XCTAssertEqual(share, 40.0 / 50.0, accuracy: 1e-9)
    }

    func test_nothingJudged_hasNoShare() {
        XCTAssertNil(day.goodShare(in: date(4300)...date(4700)))
    }

    // MARK: - Each hour of the day

    func test_eachHour_hasItsShare() {
        let hours = day.hours(calendar: gmt)
        XCTAssertEqual(hours.map(\.start), [date(0), date(3600)])
        XCTAssertEqual(hours[0].share ?? -1, 50.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(hours[1].share ?? -1, 1, accuracy: 1e-9, "10:00-10:30, away left out")
    }

    func test_anHourAway_hasNoShare() {
        // Ticks a minute apart, so the app is known to be running throughout.
        let events = stride(from: 0.0, through: 7500, by: 60).map { s in
            tick(s < 3000 || s >= 7200 ? "good" : "absent", at: s)
        }
        let timeline = PostureTimeline(events: events, now: date(7500))
        let hours = timeline.hours(calendar: gmt)
        XCTAssertEqual(hours.count, 3)
        XCTAssertNil(hours.dropFirst().first?.share)
    }

    /// A moment away at the start (11-18: the app opened at 09:49 to choose the log's folder)
    /// doesn't add hours with nothing in them.
    func test_aMomentAwayFirst_addsNoHours() {
        var events = [state("absent", at: 0), state("good", at: 30)]   // closed straight after
        events += stride(from: 3 * 3600.0, through: 3 * 3600 + 1800, by: 60).map { tick("good", at: $0) }
        let timeline = PostureTimeline(events: events, now: date(3 * 3600 + 1800))
        XCTAssertEqual(timeline.hours(calendar: gmt).map(\.start), [date(3 * 3600)])
        XCTAssertEqual(timeline.lastHour, date(3 * 3600)...date(3 * 3600 + 1800))
    }

    /// The words: "84%", or a dash with nothing judged.
    func test_aShareInWords() {
        XCTAssertEqual(PostureTimeline.percent(0.836), "84%")
        XCTAssertEqual(PostureTimeline.percent(nil), "—")
    }

    /// The card's line: the last hour, then the day.
    func test_theCardsLine() {
        XCTAssertEqual(day.lastHourSummary, "Last hour: sat well 80% · today 88% · 0 nudges")
    }
}
