import Foundation

/// Pure, Vision-free conversion of a face observation's head-orientation angles
/// (radians, from Vision rev-3's joint 3D face-model fit) into the degrees the rest
/// of the pipeline speaks. Kept free of any `import Vision` (it takes plain `Float?`
/// radians) so it is unit-tested headlessly in the package — only the live
/// `handler.perform` glue in `PoseService` stays uncovered, the same bar as today's
/// body-pose extraction.
///
/// A `nil` input axis yields a `nil` output axis, so `computeHeadAngles` falls back
/// to the legacy 2D estimate *per-axis* when Vision only fits part of the pose.
///
/// SIGN NOTE: the rad→deg *scale* is exact and certain; this is all the math that
/// can be verified off-device. The *physical sign* of each Vision axis under the
/// non-mirrored portrait front buffer is mapped to the rendered head by the live
/// `headYaw/Pitch/RollGain` signs in `PostureVisualizationBinding` — the same place
/// the legacy signal's direction was dialled in. This converter therefore passes
/// Vision's native sign through (scaled to degrees) and deliberately bakes no
/// physical-direction guess that would fight those gains. Confirm direction on
/// device via the gain signs (see the plan's open questions).
public enum FaceAngleConversion {
    static let radiansToDegrees = Float(180.0 / Double.pi)

    /// - Returns: `(yaw, pitch, roll)` in degrees, each `nil` iff its input was `nil`.
    public static func degrees(
        yawRadians: Float?,
        pitchRadians: Float?,
        rollRadians: Float?
    ) -> (yaw: Float?, pitch: Float?, roll: Float?) {
        (
            yaw: yawRadians.map { $0 * radiansToDegrees },
            pitch: pitchRadians.map { $0 * radiansToDegrees },
            roll: rollRadians.map { $0 * radiansToDegrees }
        )
    }
}

/// Runtime switch for sourcing head orientation from the Vision face-model fit
/// instead of the legacy three-independent-2D-formula estimate. `public` for the
/// same reason as `HeadYawTuning`: a DEBUG build flips it live on device (a panel
/// toggle) to A/B the decoupled source against the legacy path without a rebuild,
/// and in Release it behaves as the baked default.
///
/// Default is **OFF** for now: turning it on changes the head Euler signal's sign
/// and magnitude, so the binding's head gains + `tiltTurnFadePower` must be retuned
/// for the face regime first (the fade in particular must drop toward no-fade, since
/// a decoupled source no longer produces the phantom the fade was added to cancel —
/// left high it would suppress a *real* nod-while-turned). Once the on-device retune
/// is confirmed, bake the face-path gains and flip this default to `true`.
///
/// Concurrency: a plain `static var` read on the pose-processing path, written from
/// the main-thread tuning HUD — the same benign-race scalar-toggle pattern as
/// `HeadYawTuning.oneEarCalibration`. Do not promote to anything gating real scoring.
public enum FaceAngleTuning {
    public static var useFaceAngles: Bool = useFaceAnglesDefault
    public static let useFaceAnglesDefault: Bool = false
}
