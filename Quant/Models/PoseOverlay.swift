import CoreGraphics
import Foundation
import PostureLogic

/// The points the front camera tracks, placed on the screen over its picture, and the lines the
/// posture measurements are taken from (2026-11-22).
///
/// - Shoulders: the line between them. Its length against the calibrated length is forward lean
///   (closer to the camera reads wider); its middle against the calibrated middle is side lean
///   (sideways) and shoulder sink (down).
/// - Ears: their height above the middle of the shoulders, in shoulder widths, is head drop.
/// - Nose between the ears is head turn.
///
/// Keypoints arrive as the pipeline measures them: 0…1 across the frame, y down, a wide frame's in
/// the upright frame's units (`FrameOrientation.portraitUnits`). The preview shows the frame as in
/// a mirror and filling the screen (`resizeAspectFill`), so the sides are cut off upright and the
/// top and bottom on its side.
struct PoseOverlay: Equatable {
    enum Part: Equatable { case head, shoulders, other }

    /// The posture colour a reading's line is drawn in: green when the measurement is inside its
    /// line, amber past it, red past it once the slouch has gone on (the state's "bad"). Only
    /// these lines use these colours; the tracked points never do (2026-11-22).
    enum Status: Equatable { case good, slouching, stillSlouching }

    struct Dot: Equatable {
        let joint: Joint
        let point: CGPoint
        let part: Part
        /// At or above the confidence the measurements need (`PoseDepthFusion`'s 0.3).
        let measured: Bool
    }

    enum LineKind: Equatable {
        /// Shoulder to shoulder.
        case shoulders
        /// Ear to ear.
        case ears
        /// From between the ears straight down to the shoulders' height: head drop.
        case headHeight
        /// The calibrated shoulder width, centred on today's shoulders: forward lean.
        case calibratedShoulders
        /// Where the ears sat over today's shoulders at calibration: head drop.
        case calibratedHeadHeight
        /// From the calibrated middle of the shoulders to today's: side lean and sink.
        case centreShift

        /// The measurements this line shows, and so the ones that colour it.
        var reasons: Set<NudgeReason> {
            switch self {
            case .shoulders: [.forwardCreep]
            case .headHeight: [.headDrop]
            case .centreShift: [.sideLean, .sink]
            case .ears: [.headTurned]
            case .calibratedShoulders, .calibratedHeadHeight: []
            }
        }
    }

    struct Line: Equatable {
        let kind: LineKind
        let from: CGPoint
        let to: CGPoint
        /// Nil for the calibrated lines, and with no posture being judged.
        var status: Status? = nil
    }

    /// The confidence a keypoint needs before the measurements use it.
    static let measuredConfidence: Float = 0.3

    /// The front camera's frame (`FrontCameraSessionService` asks for 1280 × 720).
    static let frameLongSide = 1280
    static let frameShortSide = 720

    let dots: [Dot]
    let lines: [Line]
    /// The middle of the shoulders at calibration: side lean and sink are how far from it.
    let calibratedCentre: CGPoint?
    /// Today's middle of the shoulders.
    let shoulderCentre: CGPoint?

    init(keypoints: [Keypoint], orientation: FrameOrientation, baseline: Baseline?,
         reading: PoseReading? = nil, in size: CGSize) {
        let onScreen = { Self.screenPoint($0, orientation: orientation, in: size) }
        dots = keypoints.map {
            Dot(joint: $0.joint, point: onScreen($0.position), part: Self.part(of: $0.joint),
                measured: $0.confidence >= Self.measuredConfidence)
        }

        let measured = { (joint: Joint) in
            keypoints.first { $0.joint == joint && $0.confidence >= Self.measuredConfidence }?.position
        }
        var lines: [Line] = []
        let leftShoulder = measured(.leftShoulder), rightShoulder = measured(.rightShoulder)
        let leftEar = measured(.leftEar), rightEar = measured(.rightEar)

        if let le = leftEar, let re = rightEar {
            lines.append(Line(kind: .ears, from: onScreen(le), to: onScreen(re)))
        }

        var calibratedCentre: CGPoint?
        var shoulderCentre: CGPoint?
        if let ls = leftShoulder, let rs = rightShoulder {
            let mid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let width = hypot(rs.x - ls.x, rs.y - ls.y)
            shoulderCentre = onScreen(mid)
            lines.append(Line(kind: .shoulders, from: onScreen(ls), to: onScreen(rs)))

            // The head's height uses the ears, or the nose when an ear is hidden.
            let head: CGPoint? = if let le = leftEar, let re = rightEar {
                CGPoint(x: (le.x + re.x) / 2, y: (le.y + re.y) / 2)
            } else {
                measured(.nose)
            }
            if let head {
                lines.append(Line(kind: .headHeight, from: onScreen(head),
                                  to: onScreen(CGPoint(x: head.x, y: mid.y))))
            }

            if let baseline, !baseline.depthAvailable, baseline.orientation == orientation {
                let base = CGFloat(baseline.shoulderWidth)
                let centre = onScreen(CGPoint(x: CGFloat(baseline.shoulderMidpoint.x),
                                              y: CGFloat(baseline.shoulderMidpoint.y)))
                calibratedCentre = centre
                lines.append(Line(kind: .centreShift, from: centre, to: onScreen(mid)))
                lines.append(Line(kind: .calibratedShoulders,
                                  from: onScreen(CGPoint(x: mid.x - base / 2, y: mid.y)),
                                  to: onScreen(CGPoint(x: mid.x + base / 2, y: mid.y))))
                let earY = mid.y + CGFloat(baseline.neckHeight) * width
                let x = head?.x ?? mid.x
                lines.append(Line(kind: .calibratedHeadHeight,
                                  from: onScreen(CGPoint(x: x - width / 4, y: earY)),
                                  to: onScreen(CGPoint(x: x + width / 4, y: earY))))
            }
        }
        self.lines = lines.map { line in
            var line = line
            line.status = reading?.status(of: line.kind)
            return line
        }
        self.calibratedCentre = calibratedCentre
        self.shoulderCentre = shoulderCentre
    }

    /// Where a keypoint lands on a screen of `size` showing the front camera's mirrored picture.
    static func screenPoint(_ point: CGPoint, orientation: FrameOrientation, in size: CGSize) -> CGPoint {
        let wide = orientation == .landscape
        let frameWidth = wide ? frameLongSide : frameShortSide
        let frameHeight = wide ? frameShortSide : frameLongSide
        let found = FrameOrientation.frameUnits(point, width: frameWidth, height: frameHeight)
        let scale = max(size.width / CGFloat(frameWidth), size.height / CGFloat(frameHeight))
        let shown = CGSize(width: CGFloat(frameWidth) * scale, height: CGFloat(frameHeight) * scale)
        return CGPoint(x: (1 - found.x) * shown.width - (shown.width - size.width) / 2,
                       y: found.y * shown.height - (shown.height - size.height) / 2)
    }

    private static func part(of joint: Joint) -> Part {
        switch joint {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar: .head
        case .leftShoulder, .rightShoulder: .shoulders
        default: .other
        }
    }
}

/// What the posture reading is, for colouring the overlay's lines and counting down
/// (2026-11-22). Taken from the pipeline as each frame's points arrive.
struct PoseReading: Equatable {
    var state: PostureState
    /// The measurements past their lines (`Pipeline.slouchSignals`).
    var pastLines: Set<NudgeReason>
    var headTurned: Bool = false
    /// Seconds until the state changes by itself if the posture holds: drifting to bad, or bad
    /// back to good (`Pipeline.stateChangeDueAt`).
    var stateChangeIn: TimeInterval? = nil
    /// Seconds until the nudge (`Pipeline.nudgeDueAt`).
    var nudgeIn: TimeInterval? = nil

    /// A line's colour: nil while nothing's being judged, or for a line that shows no reading.
    func status(of kind: PoseOverlay.LineKind) -> PoseOverlay.Status? {
        let reasons = kind.reasons
        guard !reasons.isEmpty else { return nil }
        switch state {
        case .absent, .calibrating: return nil
        case .good, .drifting, .bad: break
        }
        if kind == .ears { return headTurned ? .slouching : .good }
        guard !reasons.isDisjoint(with: pastLines) else { return .good }
        return state.isBad ? .stillSlouching : .slouching
    }

    /// The countdown's colour: the posture's own.
    var status: PoseOverlay.Status? {
        switch state {
        case .absent, .calibrating: nil
        case .good: headTurned ? .slouching : .good
        case .drifting: .slouching
        case .bad: .stillSlouching
        }
    }

    /// What changes next and in how many seconds, rounded up: "red in 42 s", or "green in 3 s"
    /// sitting up from red, then "nudge in 30 s" when one is coming. Nil with nothing coming.
    var countdown: String? {
        let seconds = { (t: TimeInterval) in "\(Int(max(0, t).rounded(.up))) s" }
        var parts: [String] = []
        if let change = stateChangeIn {
            switch state {
            case .drifting: parts.append("red in \(seconds(change))")
            case .bad: parts.append("green in \(seconds(change))")
            case .absent, .calibrating, .good: break
            }
        }
        if let nudge = nudgeIn { parts.append("nudge in \(seconds(nudge))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One frame's points as the overlay draws them (2026-11-22).
struct TrackedPose {
    let keypoints: [Keypoint]
    let orientation: FrameOrientation
    let reading: PoseReading
}
