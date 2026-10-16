import XCTest
import PostureLogic
@testable import Quant

/// Your day's posture as a timeline: when you sat well and when you slouched (2026-10-13).
///
/// Built from the posture log, which writes a line whenever the posture, the nudge decision or
/// the task changes. A state lasts until the next state line. The log doesn't say when the app
/// closed, so no line of any kind for `maxGap` means it had: the state ends at its last line.
final class PostureTimelineTests: XCTestCase {

    private let t0: TimeInterval = 1_791_640_000

    private func state(_ value: String, at s: TimeInterval) -> PostureLogEvent {
        PostureLogEvent(t: t0 + s, kind: "state", value: value)
    }
    private func nudge(_ value: String, at s: TimeInterval) -> PostureLogEvent {
        PostureLogEvent(t: t0 + s, kind: "nudge", value: value)
    }
    private func date(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: t0 + s) }

    func test_eachStateLasts_untilTheNext() {
        let timeline = PostureTimeline(events: [
            state("good", at: 0), state("drifting", at: 60), state("bad", at: 90), state("good", at: 120),
            nudge("none", at: 150),
        ], now: date(150))
        XCTAssertEqual(timeline.segments, [
            .init(start: date(0), end: date(60), band: .good),
            .init(start: date(60), end: date(90), band: .drifting),
            .init(start: date(90), end: date(120), band: .bad),
            .init(start: date(120), end: date(150), band: .good),
        ])
    }

    /// Away and calibrating are both grey: no posture to judge.
    func test_awayAndCalibrating_areAway() {
        let timeline = PostureTimeline(events: [
            state("calibrating", at: 0), state("absent", at: 10), state("good", at: 20),
        ], now: date(30))
        XCTAssertEqual(timeline.segments.map(\.band), [.away, .good])
        XCTAssertEqual(timeline.segments.first?.end, date(20))
    }

    /// With nothing written for `maxGap`, the app had closed: the state ends at the last line,
    /// and nothing is drawn until the next state line. On 12 Oct a closing "away" was drawn for
    /// ten minutes after the app closed.
    func test_aLongSilence_endsTheState() {
        let gap = PostureTimeline.maxGap
        let timeline = PostureTimeline(events: [
            state("good", at: 0), nudge("none", at: 100),
            nudge("pending:sink", at: 100 + gap + 50),   // a stray line after the gap: no state yet
            state("absent", at: 100 + gap + 60), state("good", at: 100 + gap + 70),
        ], now: date(100 + gap + 100))
        XCTAssertEqual(timeline.segments, [
            .init(start: date(0), end: date(100), band: .good),
            .init(start: date(100 + gap + 60), end: date(100 + gap + 70), band: .away),
            .init(start: date(100 + gap + 70), end: date(100 + gap + 100), band: .good),
        ])
    }

    /// The last state runs to now while the app is still writing; once it has gone quiet for
    /// the gap, to its last line.
    func test_theLastState_runsToNow_whileTheAppIsWriting() {
        let events = [state("good", at: 0), nudge("none", at: 100)]
        XCTAssertEqual(PostureTimeline(events: events, now: date(220)).segments.last?.end, date(220))
        XCTAssertEqual(PostureTimeline(events: events, now: date(5_000)).segments.last?.end, date(100))
    }

    func test_nudges_withTheirReasons() {
        let timeline = PostureTimeline(events: [
            state("bad", at: 0), nudge("pending:headDrop", at: 0), nudge("fire:headDrop", at: 60),
            nudge("suppressed:cooldownActive", at: 60), nudge("fire:forwardCreep", at: 121),
        ], now: date(130))
        XCTAssertEqual(timeline.nudges, [
            .init(at: date(60), reason: .headDrop), .init(at: date(121), reason: .forwardCreep),
        ])
    }

    /// Time in each band, and the share of the judged time spent sitting well.
    func test_totals() {
        let timeline = PostureTimeline(events: [
            state("absent", at: 0), state("good", at: 60), state("drifting", at: 360),
            state("bad", at: 420), state("good", at: 480),
        ], now: date(600))
        XCTAssertEqual(timeline.total(.good), 420)
        XCTAssertEqual(timeline.total(.away), 60)
        XCTAssertEqual(timeline.slouched, 120)
        XCTAssertEqual(try XCTUnwrap(timeline.goodShare), 420.0 / 540.0, accuracy: 0.0001)
    }

    func test_theCardsLine() {
        // Task changes every few minutes, as in a real log, so the hour isn't read as a gap.
        let tasks = stride(from: 500.0, to: 3_000, by: 500).map {
            PostureLogEvent(t: t0 + $0, kind: "task", value: "reading")
        }
        let timeline = PostureTimeline(events: [state("good", at: 0)] + tasks + [
            state("bad", at: 3_000), nudge("fire:sink", at: 3_060), state("good", at: 3_420),
        ], now: date(3_600))
        XCTAssertEqual(timeline.summary, "Sat well 88% · slouched 7 min · 1 nudge")
        XCTAssertEqual(PostureTimeline.minutes(20), "under a minute")
        XCTAssertEqual(PostureTimeline.label(for: .headDrop), "Head dropped")
    }

    func test_nothingLogged_isEmpty() {
        let timeline = PostureTimeline(events: [], now: date(0))
        XCTAssertTrue(timeline.segments.isEmpty)
        XCTAssertNil(timeline.goodShare)
        XCTAssertNil(timeline.summary)
    }

    /// Lines are read in time order, whatever order they're given in.
    func test_outOfOrderLines_areSorted() {
        let timeline = PostureTimeline(events: [state("bad", at: 30), state("good", at: 0)], now: date(60))
        XCTAssertEqual(timeline.segments.map(\.band), [.good, .bad])
    }

    // MARK: - A log with ticks (2026-10-16)

    /// Since 2026-10-16 the log has a line at least every minute while the camera runs, so
    /// sitting well for 25 minutes is no longer read as the app having closed, and a silence of
    /// `maxGapWithTicks` is: the camera had stopped.
    func test_ticks_keepAStateGoing_andItEndsWhenTheyStop() {
        let ticks = stride(from: 60.0, through: 1_500, by: 60).map {
            PostureLogEvent(t: t0 + $0, kind: "tick", value: "good")
        }
        let timeline = PostureTimeline(events: [state("good", at: 0)] + ticks + [
            state("bad", at: 1_800),
        ], now: date(1_860))
        XCTAssertEqual(timeline.segments, [
            .init(start: date(0), end: date(1_500), band: .good),
            .init(start: date(1_800), end: date(1_860), band: .bad),
        ])
    }

    /// A tick says the state too, so after the camera stops and starts again with the posture
    /// unchanged, the band picks up at the first tick. Only a change writes a state line, and
    /// the band stayed blank until the next one (review of the fix, 2026-10-16).
    func test_aTickAfterAGap_startsTheBandAgain() {
        let tick = { (s: TimeInterval) in PostureLogEvent(t: self.t0 + s, kind: "tick", value: "good") }
        let timeline = PostureTimeline(events: [state("good", at: 0), tick(60), tick(600), tick(660)],
                                       now: date(700))
        XCTAssertEqual(timeline.segments, [
            .init(start: date(0), end: date(60), band: .good),
            .init(start: date(600), end: date(700), band: .good),
        ])
    }

    /// How a nudge reached the Watch isn't a camera frame, so it doesn't keep a state going: a
    /// replay's nudges (not logged themselves) still send one, about once a minute.
    func test_watchLines_dontKeepAStateGoing() {
        let watch = { (s: TimeInterval) in PostureLogEvent(t: self.t0 + s, kind: "watch", value: "message") }
        let timeline = PostureTimeline(events: [
            state("good", at: 0), PostureLogEvent(t: t0 + 60, kind: "tick", value: "good"),
            watch(120), watch(180), watch(240),
        ], now: date(250))
        XCTAssertEqual(timeline.segments, [.init(start: date(0), end: date(60), band: .good)])
    }

    /// And the last state runs to now only while the ticks keep coming.
    func test_withTicks_theLastStateEnds_whenTheyStop() {
        let events = [state("good", at: 0), PostureLogEvent(t: t0 + 60, kind: "tick", value: "good")]
        XCTAssertEqual(PostureTimeline(events: events, now: date(150)).segments.last?.end, date(150))
        XCTAssertEqual(PostureTimeline(events: events, now: date(400)).segments.last?.end, date(60))
    }

    // MARK: - Reading the day's file

    func test_readsTheLinesOfADayFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let lines = """
        {"kind":"state","t":1791640000,"value":"good"}
        not json
        {"kind":"nudge","t":1791640060,"value":"fire:sink"}

        """
        try Data(lines.utf8).write(to: folder.appendingPathComponent("posture-log-2026-10-13.jsonl"))
        try Data().write(to: folder.appendingPathComponent("posture-log-2026-10-12.jsonl"))
        try Data().write(to: folder.appendingPathComponent("posture-log-to-2026-10-13.jsonl"))

        XCTAssertEqual(PostureLogStore.dayKeys(in: folder), ["2026-10-13", "2026-10-12"],
                       "newest first; an export isn't a day")
        let events = PostureLogStore.events(dayKey: "2026-10-13", in: folder)
        XCTAssertEqual(events.map(\.value), ["good", "fire:sink"], "a bad line is skipped")
    }
}

/// The TODAY card reloads on its own while it's up (2026-10-16 audit). Its timer was a property
/// of the view, and the main screen rebuilds the card about ten times a second, so the timer
/// restarted every frame and never fired: the card kept what it read when the screen appeared.
@MainActor
final class PostureTimelineLoaderTests: XCTestCase {

    nonisolated final class Reads: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func add() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func test_today_isReadAgainAndAgain_untilTheCardGoes() async throws {
        let reads = Reads()
        let loader = PostureTimelineLoader(read: { _ in reads.add(); return ([], []) })
        let card = Task { await loader.keepLoadingToday(every: .milliseconds(20)) }

        let deadline = Date().addingTimeInterval(5)
        while reads.count < 3 && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertGreaterThanOrEqual(reads.count, 3)

        card.cancel()
        await card.value
        let after = reads.count
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reads.count, after, "stops when the card goes")
    }
}
