import Foundation

/// When a head turn becomes worth a nudge.
///
/// Its own type rather than more `PostureThresholds` fields: those are persisted with every Jev
/// record, and a synthesized `Codable` can't read a record saved before a field existed.
public struct HeadTurnThresholds: Equatable {
    /// Head yaw, either way, from which the head counts as turned. Dave's turns to a second
    /// screen read 60-78°; looking at the main screen reads about 0°, and leaning turns the head
    /// up to about 25°. The Jev wording uses the same 45° for a swivel.
    public var turnedDegrees: Float = 45

    /// Forward creep at or below this means the shoulders narrowed: the chair turned with the
    /// head, so the neck isn't twisted. The Jev wording's swivel cut; every measured swivel read
    /// -0.048 or lower, and every head turn +0.008 or higher.
    public var swivelMaxForwardCreep: Float = -0.03

    /// How long the head stays turned before a nudge. Dave: it gets uncomfortable after about
    /// five minutes (2026-10-04).
    public var durationBeforeNudge: TimeInterval = 300

    /// How long looking back ends an episode. Shorter is a glance at the main screen or a frame
    /// the face tracker dropped, not a rest for the neck.
    public var gracePeriod: TimeInterval = 5

    public init() {}
}

/// Times how long the head has been held turned to one side with the shoulders still facing the
/// phone: the neck twisted, as when working on a second screen off to the side.
///
/// Separate from the posture engine, because a turned head isn't a slouch and the two can happen
/// at once. The nudge engine fires for whichever is due.
final class HeadTurnTracker {

    var thresholds: HeadTurnThresholds

    /// When the current episode began, on the frame clock, or nil when the head isn't turned.
    private(set) var turnedSince: TimeInterval?
    private var lastTurnedAt: TimeInterval?

    init(thresholds: HeadTurnThresholds = HeadTurnThresholds()) {
        self.thresholds = thresholds
    }

    /// The rule: turned past `turnedDegrees` either way, with the shoulders not narrowed.
    static func isNeckTurned(headYaw: Float, forwardCreep: Float, thresholds: HeadTurnThresholds) -> Bool {
        abs(headYaw) >= thresholds.turnedDegrees && forwardCreep > thresholds.swivelMaxForwardCreep
    }

    /// The other half of the rule: the head turned past `turnedDegrees` AND the shoulders
    /// narrowed, so the whole chair turned. Not bad posture, and head drop can read a little
    /// negative then (two measured swivels: -0.016 and -0.021), so the posture engine doesn't
    /// count it as a slouch while it holds.
    static func isChairTurned(headYaw: Float, forwardCreep: Float, thresholds: HeadTurnThresholds) -> Bool {
        abs(headYaw) >= thresholds.turnedDegrees && forwardCreep <= thresholds.swivelMaxForwardCreep
    }

    /// Takes one frame and returns when the current episode began, or nil.
    ///
    /// Nothing counts as turned without a clear view (the posture engine's rule). Not turned for
    /// longer than `gracePeriod` ends the episode.
    @discardableResult
    func update(headYaw: Float, forwardCreep: Float, trackingQuality: TrackingQuality,
                timestamp: TimeInterval) -> TimeInterval? {
        let turned = trackingQuality.allowsPostureJudgement
            && Self.isNeckTurned(headYaw: headYaw, forwardCreep: forwardCreep, thresholds: thresholds)
        if turned {
            if turnedSince == nil { turnedSince = timestamp }
            lastTurnedAt = timestamp
        } else if let last = lastTurnedAt, timestamp - last > thresholds.gracePeriod {
            turnedSince = nil
            lastTurnedAt = nil
        }
        return turnedSince
    }

    func reset() {
        turnedSince = nil
        lastTurnedAt = nil
    }
}
