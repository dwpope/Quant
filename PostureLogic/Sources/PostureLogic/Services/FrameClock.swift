import Foundation

/// Puts camera frame times on the calendar clock, the one clock the rest of the app uses.
///
/// ARKit and AVFoundation stamp frames on the device's uptime clock: seconds since boot, which
/// stops while the phone sleeps. Everything else in the app, `Date()` included, counts seconds
/// since 1970. The two were compared directly three times, each a bug (the drift timer read 56
/// years, nudges stopped after the first, sip calibration recorded a 1.79-billion-second sip),
/// and detected sips were saved on the uptime clock and shown as calendar times.
///
/// So every frame's time is converted once, here, where it's captured, and nothing downstream
/// sees the uptime clock. `ClockConventionTests` checks that by reading the source.
///
/// The conversion stays monotonic: the calendar is read once, when the clock is made, so a
/// clock change mid-session can't make time run backwards for a timer. Time asleep is counted by
/// the continuous clock, which keeps running while the uptime clock stops.
public struct FrameClock {

    /// Calendar seconds at continuous-clock zero, fixed when the clock is made.
    private let epoch: TimeInterval
    private let continuousNow: () -> TimeInterval
    private let uptimeNow: () -> TimeInterval

    init(calendarNow: TimeInterval,
         continuousNow: @escaping () -> TimeInterval,
         uptimeNow: @escaping () -> TimeInterval) {
        self.epoch = calendarNow - continuousNow()
        self.continuousNow = continuousNow
        self.uptimeNow = uptimeNow
    }

    /// The app's clock, made at first use.
    public static let shared = FrameClock(
        calendarNow: Date().timeIntervalSince1970,
        continuousNow: { seconds(CLOCK_MONOTONIC_RAW) },   // keeps running while asleep
        uptimeNow: { seconds(CLOCK_UPTIME_RAW) })          // the frames' clock: stops while asleep

    /// A capture time on the uptime clock (an `ARFrame`'s `timestamp`, or a sample buffer's
    /// presentation time on the host clock) as calendar seconds since 1970.
    public func calendarSeconds(fromUptime uptime: TimeInterval) -> TimeInterval {
        // Uptime plus the time asleep since boot is the continuous clock's reading for the
        // capture. A frame is converted within milliseconds, so no sleep falls in between.
        epoch + uptime + (continuousNow() - uptimeNow())
    }

    private static func seconds(_ clock: clockid_t) -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(clock)) / 1_000_000_000
    }
}
