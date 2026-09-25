import Foundation
import PostureLogic

/// Whether a Jev classification can run right now, and if not, why not.
///
/// Exists because the first thing that happened on a real device was "I tap the button and
/// nothing appears to happen". Four separate conditions refuse a classification, and from the
/// outside they were indistinguishable from each other and from a broken button. Naming them
/// turns a dead control into one that explains itself.
enum JevGate: Equatable {
    /// Everything is in place; this is the payload to send.
    case ready(JevFeatures)

    /// The toggle is off. Ships off, and that default is the privacy boundary.
    case disabled

    /// No calibration baseline. The metrics are all zero rather than nil before calibration, so
    /// a payload built anyway would pass the proxy's validation and mean nothing.
    case notCalibrated

    /// No current pose. `latestSample` goes nil whenever fusion fails while `latestMetrics`
    /// keeps its last value, so sending would pair fresh numbers with a stale pose.
    case noPose

    /// Inside the minimum interval. Never per frame — 130-475ms per call.
    case tooSoon(secondsRemaining: TimeInterval)

    /// A value is non-finite, which the proxy rejects with a 400.
    case unusableValues

    /// Text for the HUD: what happened and what to do about it.
    var message: String {
        switch self {
        case .ready:
            return ""
        case .disabled:
            return "classifier is off"
        case .notCalibrated:
            return "not calibrated — recalibrate first"
        case .noPose:
            return "no pose — check tracking"
        case .tooSoon(let seconds):
            return String(format: "wait %.0fs", max(seconds, 0))
        case .unusableValues:
            return "pose values unusable"
        }
    }
}
