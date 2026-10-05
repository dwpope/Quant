import XCTest
@testable import PostureLogic

/// One clock for the whole app: seconds since 1970 (2026-10-05).
///
/// Camera frames arrive stamped on the device's uptime clock: seconds since boot, about 670,000
/// on Dave's phone, against about 1.79 billion for the calendar. Three bugs came from comparing
/// one with the other (the drift timer, nudges stopping after the first, sip calibration), and a
/// fourth was still live: detected sips were saved on the uptime clock and shown as calendar times.
/// `FrameClock` converts each frame's time once, where it's captured, so everything downstream is
/// on the calendar clock. It stays monotonic: the calendar is read once, so a clock change
/// mid-session can't move frame times, and time asleep is counted.
final class FrameClockTests: XCTestCase {

    /// A clock whose readings the test sets.
    private final class Clocks {
        var continuous: TimeInterval
        var uptime: TimeInterval
        init(continuous: TimeInterval, uptime: TimeInterval) {
            self.continuous = continuous; self.uptime = uptime
        }
    }

    private func clock(_ c: Clocks, calendarNow: TimeInterval) -> FrameClock {
        FrameClock(calendarNow: calendarNow, continuousNow: { c.continuous }, uptimeNow: { c.uptime })
    }

    func test_aFrameCapturedNow_isNowOnTheCalendar() {
        let c = Clocks(continuous: 1_000, uptime: 900)   // 100 s asleep since boot
        let fc = clock(c, calendarNow: 1_800_000_000)
        XCTAssertEqual(fc.calendarSeconds(fromUptime: 900), 1_800_000_000, accuracy: 1e-6)
    }

    func test_aFrameCapturedEarlier_isThatMuchEarlier() {
        let c = Clocks(continuous: 1_000, uptime: 900)
        let fc = clock(c, calendarNow: 1_800_000_000)
        XCTAssertEqual(fc.calendarSeconds(fromUptime: 899.5), 1_799_999_999.5, accuracy: 1e-6)
    }

    /// The uptime clock stops while the phone sleeps; the calendar doesn't. Ten minutes asleep,
    /// then a frame: still the calendar time it was captured.
    func test_timeAsleep_isCounted() {
        let c = Clocks(continuous: 1_000, uptime: 900)
        let fc = clock(c, calendarNow: 1_800_000_000)
        c.continuous += 600 + 5     // 10 min asleep, then 5 s awake
        c.uptime += 5
        XCTAssertEqual(fc.calendarSeconds(fromUptime: c.uptime), 1_800_000_605, accuracy: 1e-6)
    }

    /// The calendar is read once: changing the phone's clock later can't move frame times, so
    /// timers never see time run backwards.
    func test_framesOnlyMoveForward() {
        let c = Clocks(continuous: 1_000, uptime: 900)
        let fc = clock(c, calendarNow: 1_800_000_000)
        let first = fc.calendarSeconds(fromUptime: 900)
        c.continuous += 1; c.uptime += 1
        XCTAssertGreaterThan(fc.calendarSeconds(fromUptime: 901), first)
    }

    // MARK: - On this machine's real clocks

    func test_live_aFrameStampedNow_readsAsNow() {
        let frame = FrameClock.shared.calendarSeconds(fromUptime: ProcessInfo.processInfo.systemUptime)
        XCTAssertEqual(frame, Date().timeIntervalSince1970, accuracy: 1.0)
    }
}
