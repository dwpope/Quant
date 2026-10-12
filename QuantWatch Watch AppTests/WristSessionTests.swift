import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// Keeping the Watch app running an hour at a time, so nudges arrive on time (2026-10-10).
///
/// In session 3 all four nudges were queued for a closed Watch app and arrived late: watchOS wakes
/// a closed app when it chooses. A physical-therapy extended runtime session keeps the app running
/// in the background for up to an hour, so a nudge is shown the moment it comes. Opening the app
/// starts one; near the hour a notification asks for a tap to start the next.
struct WristSessionTests {

    /// Stands in for `WKExtendedRuntimeSession`.
    final class FakeRuntime: ExtendedRuntime {
        var started = 0
        var invalidated = 0
        func start() { started += 1 }
        func invalidate() { invalidated += 1 }
    }

    final class Harness {
        var runtimes: [FakeRuntime] = []
        var renewals = 0
        var appActive = true
        lazy var session = WristNudgeSession(
            makeRuntime: { [unowned self] _ in
                let r = FakeRuntime(); self.runtimes.append(r); return r
            },
            notifyRenewal: { [unowned self] in self.renewals += 1 },
            isAppActive: { [unowned self] in self.appActive })
    }

    @Test func openingTheApp_startsAnHour() {
        let h = Harness()
        h.session.appBecameActive()
        #expect(h.runtimes.count == 1)
        #expect(h.runtimes.first?.started == 1)
        #expect(h.session.state == .starting)
    }

    @Test func onceStarted_itRunsUntilItsEnd() {
        let h = Harness()
        let end = Date(timeIntervalSince1970: 1_791_640_000)
        h.session.appBecameActive()
        h.session.didStart(until: end)
        #expect(h.session.state == .on(until: end))
        #expect(h.session.isOn)
    }

    @Test func openingTheAppAgain_whileRunning_startsNothingNew() {
        let h = Harness()
        h.session.appBecameActive()
        h.session.didStart(until: Date().addingTimeInterval(3600))
        h.session.appBecameActive()
        #expect(h.runtimes.count == 1)
    }

    @Test func nearTheHour_itAsksForATap() {
        let h = Harness()
        h.session.appBecameActive()
        h.session.didStart(until: Date().addingTimeInterval(3600))
        h.session.willExpire()
        #expect(h.renewals == 1)
    }

    /// The hour ended with the app open: the next one starts straight away.
    @Test func endingWithTheAppOpen_startsTheNextHour() {
        let h = Harness()
        h.session.appBecameActive()
        h.session.didStart(until: Date().addingTimeInterval(3600))
        h.session.didEnd(error: nil)
        #expect(h.runtimes.count == 2)
        #expect(h.session.state == .starting)
    }

    /// Ended with the app closed: off until it's opened (the renewal notification's tap).
    @Test func endingWithTheAppClosed_waitsToBeOpened() {
        let h = Harness()
        h.session.appBecameActive()
        h.session.didStart(until: Date().addingTimeInterval(3600))
        h.appActive = false
        h.session.didEnd(error: nil)
        #expect(h.session.state == .off)
        #expect(!h.session.isOn)
        h.appActive = true
        h.session.appBecameActive()
        #expect(h.runtimes.count == 2)
    }

    /// An error isn't retried in a loop: the screen says so, and opening the app tries again.
    @Test func anError_isShown_andNotRetriedOnItsOwn() {
        let h = Harness()
        h.session.appBecameActive()
        h.session.didEnd(error: "not allowed")
        #expect(h.session.state == .unavailable("not allowed"))
        #expect(h.runtimes.count == 1)
    }

    @Test func theScreenSaysUntilWhen() {
        let end = Date(timeIntervalSince1970: 1_791_640_000)
        let line = WristNudgeSession.statusLine(for: .on(until: end))
        #expect(line == "Nudges on time until \(end.formatted(date: .omitted, time: .shortened))")
        #expect(WristNudgeSession.statusLine(for: .off).contains("may arrive late"))
    }

    @Test func theRenewalNotification_saysWhatToDo() {
        let content = WristNudgeSession.renewalContent()
        #expect(content.title == "Aware")
        #expect(content.body == "Open Aware to keep nudges on time for another hour")
    }

    /// watchOS only keeps the app running with this background mode declared.
    @Test func theAppDeclaresThePhysicalTherapyMode() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "WKBackgroundModes") as? [String]
        #expect(modes?.contains("physical-therapy") == true)
    }
}

/// A start that never answers doesn't leave the screen on "Keeping nudges on time…" for good
/// (2026-10-11 review). watchOS is meant to answer every start, but nothing guarantees it; after
/// 15 s the screen says it didn't start and offers the button, and opening the app tries again.
struct WristSessionStallTests {

    final class Harness {
        var runtimes: [WristSessionTests.FakeRuntime] = []
        var clock = Date(timeIntervalSince1970: 1_791_640_000)
        lazy var session = WristNudgeSession(
            makeRuntime: { [unowned self] _ in
                let r = WristSessionTests.FakeRuntime(); self.runtimes.append(r); return r
            },
            notifyRenewal: {},
            isAppActive: { true },
            now: { [unowned self] in self.clock },
            scheduleCheck: { _, _ in })
    }

    @Test func aStartWithNoAnswer_isShownAsNotStarted_after15Seconds() {
        let h = Harness()
        h.session.appBecameActive()
        h.clock += 10
        h.session.checkStarting()
        #expect(h.session.state == .starting, "still waiting at 10 s")
        h.clock += 6
        h.session.checkStarting()
        #expect(h.session.state == .unavailable("it didn't start"))
        #expect(h.runtimes.first?.invalidated == 1)
    }

    @Test func openingTheApp_afterAStall_startsAgain() {
        let h = Harness()
        h.session.appBecameActive()
        h.clock += 20
        h.session.appBecameActive()
        #expect(h.runtimes.count == 2)
        #expect(h.runtimes.first?.invalidated == 1)
    }

    @Test func openingTheApp_whileAStartIsYoung_startsNothingNew() {
        let h = Harness()
        h.session.appBecameActive()
        h.clock += 5
        h.session.appBecameActive()
        #expect(h.runtimes.count == 1)
    }

    /// Something the stalled session says late changes nothing.
    @Test func anAnswerFromAnAbandonedStart_isIgnored() {
        let h = Harness()
        h.session.appBecameActive()
        let abandoned = h.runtimes[0]
        h.clock += 20
        h.session.appBecameActive()
        h.session.didEnd(error: "late", from: abandoned)
        #expect(h.session.state == .starting)
    }
}
