import CoreGraphics
import Foundation
import PostureLogic

/// Which main screen shows: the debug one for tuning, or the calm view (2026-10-20).
///
/// Dave is still tuning the measurements, so debug comes first; the calm view is the one to
/// switch to. The choice is kept across launches.
enum MainScreenStyle: String {
    case debug, calm

    static let storageKey = "mainScreen.style"
    static let initial = MainScreenStyle.debug

    var other: MainScreenStyle { self == .debug ? .calm : .debug }

    /// The switch's name, for VoiceOver: where it goes.
    var switchLabel: String { self == .debug ? "Switch to calm view" : "Switch to debug view" }
}

/// What the calm view shows: your posture in a word, a column standing as tall as you sit, and
/// the countdown to the nudge (2026-10-20). Pure.
///
/// Built from the glance the Watch is sent, so the phone and the Watch can't disagree. The
/// column is the timeline's band, live and large: one shape for now and for the day.
enum CalmLook: Equatable {
    case sittingWell
    /// `sustained` once it has gone on long enough to be nudged (the pipeline's "bad").
    case slouching(since: Date?, sustained: Bool, nudgeAt: Date?)
    case headTurned(since: Date, nudgeAt: Date?)
    case away
    case calibrating
    /// No frame judged lately: the camera has stopped, been interrupted, or a replay is over.
    case cameraPaused
    /// No frame judged yet since the app opened.
    case startingCamera
    /// Critical heat: the camera is stopped until the phone cools.
    case coolingDown

    init(glance: PostureGlance, thermalLevel: ThermalLevel, cameraStarted: Bool = true) {
        if thermalLevel == .critical { self = .coolingDown; return }
        if glance == .paused, !cameraStarted { self = .startingCamera; return }
        let at = { (t: Double?) in t.map { Date(timeIntervalSince1970: $0) } }
        switch glance.state {
        case "good":
            if let turned = at(glance.headTurnedSince) {
                self = .headTurned(since: turned, nudgeAt: at(glance.nudgeAt))
            } else {
                self = .sittingWell
            }
        case "drifting":
            self = .slouching(since: at(glance.since), sustained: false, nudgeAt: at(glance.nudgeAt))
        case "bad":
            self = .slouching(since: at(glance.since), sustained: true, nudgeAt: at(glance.nudgeAt))
        case "absent": self = .away
        case "calibrating": self = .calibrating
        default: self = .cameraPaused
        }
    }

    /// The band the column stands at, or nil with no posture to show. A head turn while
    /// sitting well is drawn full, as the timeline beside it draws that time.
    var band: PostureTimeline.Band? {
        switch self {
        case .sittingWell, .headTurned: return .good
        case .slouching(_, let sustained, _): return sustained ? .bad : .drifting
        case .away, .calibrating: return .away
        case .cameraPaused, .startingCamera, .coolingDown: return nil
        }
    }

    /// In the words used on the card, the timeline and the Watch.
    var headline: String {
        switch self {
        case .headTurned: return "Head turned"
        case .calibrating: return "Calibrating"
        case .cameraPaused: return "Camera paused"
        case .startingCamera: return "Starting camera"
        case .coolingDown: return "Cooling down"
        case .sittingWell, .slouching, .away: return band?.label ?? ""
        }
    }

    /// When what's being counted began: a slouch or a head turn.
    var since: Date? {
        switch self {
        case .slouching(let since, _, _): return since
        case .headTurned(let since, _): return since
        default: return nil
        }
    }

    /// The countdown to the nudge, as the Watch shows it.
    enum Countdown: Equatable {
        case until(Date)
        /// Due now: the phone fires on its next frame.
        case due
    }

    /// Nil with no nudge coming: sitting well, away, or nudges held back (silenced, the hourly
    /// cap), when the pipeline has no due time.
    func countdown(now: Date) -> Countdown? {
        let nudgeAt: Date?
        switch self {
        case .slouching(_, _, let at): nudgeAt = at
        case .headTurned(_, let at): nudgeAt = at
        default: nudgeAt = nil
        }
        guard let nudgeAt else { return nil }
        return nudgeAt > now ? .until(nudgeAt) : .due
    }
}

/// The calm view's top line: whether the camera is watching, and seeing you.
enum CalmStatus: Equatable {
    case live, warm, paused, coolingDown, starting
    /// Tracking isn't good (a shoulder hidden, say): the posture is held, not judged.
    case unclear
    /// Calibrating, and while calibrating, waiting for the clear view it starts from.
    case calibrating, waitingForClearView

    init(glance: PostureGlance, thermalLevel: ThermalLevel, tracking: TrackingQuality = .good,
         cameraStarted: Bool = true) {
        if thermalLevel == .critical { self = .coolingDown }
        else if glance == .paused { self = cameraStarted ? .paused : .starting }
        // Away is the camera seeing nobody, which "Live" says; tracking is lost then as a rule.
        else if tracking != .good, glance.state != "absent", glance.state != "calibrating" {
            self = .unclear
        }
        else if thermalLevel >= .serious { self = .warm }
        else { self = .live }
    }

    /// While calibrating. It starts only once tracking is good, which the calibration screen
    /// doesn't say; the debug panel's hint did (2026-09-26).
    static func calibrating(tracking: TrackingQuality) -> CalmStatus {
        tracking == .good ? .calibrating : .waitingForClearView
    }

    var label: String {
        switch self {
        case .live: return "Live"
        case .warm: return "Warm · less accurate"
        case .paused: return "Paused"
        case .coolingDown: return "Cooling down"
        case .starting: return "Starting"
        case .unclear: return "Can't see you clearly"
        case .calibrating: return "Calibrating"
        case .waitingForClearView: return "Waiting for a clear view"
        }
    }

    /// The posture shown is the last one judged, held while the camera can't see you clearly.
    var holdsPosture: Bool { self == .unclear }
}

/// Layout rules for the calm view, kept out of the view so they can be tested.
enum CalmLayout {
    /// Everything in the portrait view but the column, at the usual text size: the word and its
    /// two lines, today, the sips and the controls, with their gaps.
    static let portraitFixedHeight: CGFloat = 480

    /// How tall the column stands, in portrait, given the height below the top line. It takes
    /// most of what the rest leaves, so an iPhone SE needn't scroll, and stops at 240 pt. Larger
    /// text sizes scroll instead.
    static func columnHeight(available: CGFloat) -> CGFloat {
        min(240, max(110, (available - portraitFixedHeight) * 0.85))
    }

    /// The time slouched today: "7 min", then "1 h 5 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The share sat well: "88%", or a dash with nothing judged yet.
    static func percent(_ share: Double?) -> String {
        share.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    /// Positions the view steps through, one a minute.
    static let burnInSteps = 8

    /// How far the whole view sits from centre this minute (2026-10-20). The screen is on for
    /// hours with the same pixels lit; like StandBy and Always-On, it moves a little, too
    /// little and too seldom to notice: up to 3 pt, round a circle, a point further on each
    /// minute (about 2.3 pt).
    static func burnInShift(minute: Int) -> CGSize {
        let step = ((minute % burnInSteps) + burnInSteps) % burnInSteps
        let angle = Double(step) / Double(burnInSteps) * 2 * .pi
        return CGSize(width: (3 * cos(angle) * 10).rounded() / 10,
                      height: (3 * sin(angle) * 10).rounded() / 10)
    }
}
