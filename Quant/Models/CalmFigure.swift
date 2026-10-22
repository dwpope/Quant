import Foundation
import PostureLogic
import simd

/// How the calm view draws you: a front view of head, neck and shoulders, the way the phone
/// sees you, standing in a faint outline of your calibrated posture (2026-10-20, after Dave
/// found the first design's column meant nothing). Pure.
///
/// Every metric is a front camera's change since calibration, so each has a front-view shape:
/// leaning in draws you bigger (closer), a head drop shortens the neck, a sink lowers you, a
/// side lean tilts you, a head turn turns the face. Not a side profile: that would draw a
/// rounded back and a forward head the camera can't measure.
///
/// Each part is how far past its line you are, eased so the line itself shows clearly (about
/// two thirds of the part's full change) and far past it stops growing.
struct CalmFigurePose: Hashable {
    /// Toward the phone (+), drawn bigger, or back (−), smaller. −1…1.
    var lean: Double = 0
    /// The head down towards the shoulders. 0…1.
    var drop: Double = 0
    /// The shoulders lower in the chair. 0…1.
    var sink: Double = 0
    /// Leaning sideways, + to the right on screen, as in a mirror. −1…1.
    var tilt: Double = 0
    /// The head turned, + facing right on screen, as in a mirror. −1…1.
    var turn: Double = 0

    static let neutral = CalmFigurePose()

    init() {}

    /// Sitting well, the figure stands in its outline: the metrics wander a little below their
    /// lines all the time, and drawing that would keep the screen moving. With no posture to
    /// show (away, camera stopped), the outline stands empty. `headTurnDegrees` is the head's
    /// yaw from where it was at calibration, + towards your right (`PoseSample.headYaw`).
    init(look: CalmLook, metrics: RawMetrics?, thresholds: PostureThresholds,
         headTurnDegrees: Float?, turnedDegrees: Float = HeadTurnThresholds().turnedDegrees) {
        switch look {
        case .headTurned:
            turn = Self.signedPast(headTurnDegrees ?? 0, line: turnedDegrees)
        case .slouching:
            guard let m = metrics else { return }
            lean = m.forwardCreep >= 0
                ? Self.step(Self.ease(Double(m.forwardCreep / thresholds.forwardCreepThreshold)))
                : -Self.step(Self.ease(Double(m.forwardCreep / thresholds.reclineMaxForwardCreep)))
            // A dropping head reads negative on the device (image y runs down).
            drop = Self.step(Self.ease(Double(-m.headDrop / thresholds.headDropThreshold)))
            sink = Self.step(Self.ease(Double(m.shoulderSink / thresholds.shoulderSinkThreshold)))
            // + is the shoulders towards larger image x: your right (`PoseSample`), the right
            // of a mirror.
            tilt = Self.signedPast(m.lateralLeanSigned, line: thresholds.sideLeanThreshold)
        case .sittingWell, .away, .calibrating, .cameraPaused, .startingCamera, .coolingDown:
            return
        }
    }

    /// 0 at nothing, about 0.63 at the line, towards 1 far past it.
    private static func ease(_ pastLine: Double) -> Double { 1 - exp(-max(0, pastLine)) }

    private static func signedPast(_ value: Float, line: Float) -> Double {
        guard line > 0 else { return 0 }
        let eased = step(ease(Double(abs(value) / line)))
        return value < 0 ? -eased : eased
    }

    /// In steps of 0.05, so a frame's jitter doesn't redraw the screen.
    private static func step(_ value: Double) -> Double { (value * 20).rounded() / 20 }

    /// The outline's neck, as a share of a typical one: your ears' height above your shoulders
    /// at calibration, in shoulder widths (`Baseline.neckHeight`, negative on the device), 0.3
    /// being typical. Kept within 0.15–0.5, so an odd calibration can't draw an odd figure.
    static func neckLength(baselineNeckHeight: Float?) -> Double {
        guard let height = baselineNeckHeight else { return 1 }
        return Double(min(0.5, max(0.15, abs(height)))) / 0.3
    }
}

extension CalmFigurePose {
    /// Part way from one pose to another, for the model's half-second move between them.
    static func mix(_ a: CalmFigurePose, _ b: CalmFigurePose, _ t: Double) -> CalmFigurePose {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var p = CalmFigurePose()
        p.lean = m(a.lean, b.lean); p.drop = m(a.drop, b.drop); p.sink = m(a.sink, b.sink)
        p.tilt = m(a.tilt, b.tilt); p.turn = m(a.turn, b.turn)
        return p
    }
}

/// How a pose moves your 3D model, `quant_person.usdz` (2026-10-22, Dave: "use the 3d model i
/// created and manipulate it to show the different posture states"). Pure.
///
/// The model's own frame is Z up with its front at −Y (Blender's), its torso pivoting at its
/// base and its head at the neck, as `PostureVisualizationBinding` found. Checked in renders: a
/// torso pitch about +X tips it towards the camera, a roll about +Y tilts its top to the
/// right of the screen, a head pitch about +X nods, a yaw about +Z turns the face right.
struct CalmModelPose {
    /// About the torso's base: leaning in or back, and sideways.
    let torso: simd_quatf
    /// About the neck: the nod of a dropped head, and a turn.
    let head: simd_quatf
    /// How far the head sinks into the shoulders, in the model's own units (its head is 1.65).
    let headLowered: Float
    /// The whole model, larger leaning in (closer), smaller leaning back.
    let scale: Float
    /// How far the whole model is lowered, in metres (it stands 0.3 tall).
    let sunk: Float

    init(_ pose: CalmFigurePose) {
        let degrees = Float.pi / 180
        let lean = Float(pose.lean), drop = Float(pose.drop)
        let pitch = simd_quatf(angle: (lean >= 0 ? 12 : 10) * lean * degrees, axis: SIMD3<Float>(1, 0, 0))
        let roll = simd_quatf(angle: 7 * Float(pose.tilt) * degrees, axis: SIMD3<Float>(0, 1, 0))
        torso = pitch * roll
        let turn = simd_quatf(angle: 60 * Float(pose.turn) * degrees, axis: SIMD3<Float>(0, 0, 1))
        let nod = simd_quatf(angle: 24 * drop * degrees, axis: SIMD3<Float>(1, 0, 0))
        head = turn * nod
        headLowered = 0.45 * drop
        scale = 1 + (lean >= 0 ? 0.10 : 0.08) * lean
        sunk = 0.045 * Float(pose.sink)
    }
}

/// The calm view's colours.
enum CalmPalette {
    /// How bright a posture is drawn, of its own colour. Brightness says how much it matters:
    /// sitting well is the quietest the screen gets, a slouch lights up. The edge of the eye
    /// notices a change in brightness before a change in colour, so a slouch is seen without
    /// looking, and sitting well isn't a lit panel in the corner of your eye for hours.
    static func intensity(of band: PostureTimeline.Band) -> Double {
        switch band {
        case .good: return 0.45
        case .drifting: return 0.95
        case .bad: return 1
        case .away: return 0.8
        }
    }
}
