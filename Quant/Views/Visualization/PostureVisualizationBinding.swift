import RealityKit
import SwiftUI
import UIKit
import simd

/// Step 4 — drives the static scaffold's named entities from
/// `PostureVisualizationViewModel`'s published display values.
///
/// Deliberately split into two layers:
///
/// 1. **`resolve`** — a *pure* function turning the ViewModel's display
///    scalars into plain, `Equatable` scene-space transform values. It touches
///    no RealityKit entity, so it unit-tests headlessly (no GPU / no renderer).
///    This is how Step 4 proves its mapping is correct without the on-device
///    visual check that belongs to the manual Step 7.
/// 2. **`apply`** — a thin `@MainActor` adapter that builds quaternions and
///    pokes the live entities. Not unit-tested (it only forwards `resolve`'s
///    output into RealityKit setters whose behaviour is Apple's, not ours).
///
/// Kept a value-type `enum` namespace (no class) so it adds no `@MainActor`
/// isolated `deinit` — sidestepping the toolchain SIGABRT hazard documented in
/// `implementation/progress.md`, the same reason `PostureVisualizationScene` is
/// value-type-only.
enum PostureVisualizationBinding {

    /// Scene-space transform values resolved from the ViewModel. Plain scalars
    /// (no `simd_quatf`) so tests can assert exact, comparable numbers; the
    /// quaternion construction is `apply`'s job.
    struct ResolvedPostureTransforms: Equatable {
        /// Shoulder disc (and its child direction tick): rotation about the
        /// vertical (Y) axis, radians.
        var discYawRadians: Float
        /// Head local position in scene metres — `.x` side lean, `.y` the
        /// preserved rest height, `.z` forward toward the disc front.
        var headTranslation: SIMD3<Float>
        /// Head rotation as Euler radians: `.x` pitch, `.y` yaw, `.z` roll.
        var headEulerRadians: SIMD3<Float>
        /// Uniform scale applied to the whole assembly.
        var assemblyScale: Float
        /// Opacity (0…1) applied to the whole assembly hierarchy.
        var opacity: Float
    }

    // MARK: - Tunable binding constants

    /// Scene metres per ViewModel display point. The ViewModel emits points
    /// (100 pt per metric unit); a unit lean (≈1.0) → ±100 pt → ±0.10 m, half
    /// the 0.20 m disc radius, so the head stays over the disc. A starting
    /// value — tune by eye during demo recording (design "Variable Mapping").
    static let metersPerPoint: Float = 0.001

    /// Torso-lean gain: radians of base-pivot tilt per metre of the resolved
    /// lean offset. With the loaded figure, "side lean" is no longer a head
    /// translation — it rocks the torso about its ground-contact origin (which
    /// carries the parented head). `resolve` still emits the offset in metres
    /// (`headTranslation.x` ≈ ±0.10 m for a unit lean); this converts it to an
    /// angle (~±0.20 rad ≈ ±11°). Tune by eye — one knob for lean intensity.
    static let leanRadiansPerMeter: Float = 2.0

    /// Forward-lean gain: radians of forward base-pivot pitch per metre of the
    /// resolved forward offset (`headTranslation.z`). Separate knob so fore/aft
    /// reads can differ from side lean.
    static let forwardLeanRadiansPerMeter: Float = 2.0

    private static let degreesToRadians = Float.pi / 180

    // MARK: - Pure mapping (RealityKit-free; unit-tested)

    /// Maps the ViewModel's eight continuous display scalars onto scene-space
    /// transform values. Pure: same input → same output, no entity access.
    static func resolve(
        shoulderRotationDegrees: Double,
        sideLeanOffsetPoints: Double,
        headForwardOffsetPoints: Double,
        assemblyScale: Double,
        headYawDegrees: Double,
        headPitchDegrees: Double,
        headRollDegrees: Double,
        opacity: Double
    ) -> ResolvedPostureTransforms {
        ResolvedPostureTransforms(
            discYawRadians: Float(shoulderRotationDegrees) * degreesToRadians,
            headTranslation: SIMD3<Float>(
                Float(sideLeanOffsetPoints) * metersPerPoint,
                PostureVisualizationScene.Layout.headCenterY,
                Float(headForwardOffsetPoints) * metersPerPoint
            ),
            headEulerRadians: SIMD3<Float>(
                Float(headPitchDegrees) * degreesToRadians,
                Float(headYawDegrees) * degreesToRadians,
                Float(headRollDegrees) * degreesToRadians
            ),
            assemblyScale: Float(assemblyScale),
            opacity: Float(opacity)
        )
    }

    /// Convenience overload reading the live ViewModel. `@MainActor` because
    /// the ViewModel is; still pure w.r.t. RealityKit, so tests drive it via
    /// the `ingest(…)` seam to prove the binding consumes the VM correctly.
    @MainActor
    static func resolve(from viewModel: PostureVisualizationViewModel) -> ResolvedPostureTransforms {
        resolve(
            shoulderRotationDegrees: viewModel.shoulderRotationDegrees,
            sideLeanOffsetPoints: viewModel.sideLeanOffsetPoints,
            headForwardOffsetPoints: viewModel.headForwardOffsetPoints,
            assemblyScale: viewModel.assemblyScale,
            headYawDegrees: viewModel.headYawDegrees,
            headPitchDegrees: viewModel.headPitchDegrees,
            headRollDegrees: viewModel.headRollDegrees,
            opacity: viewModel.opacity
        )
    }

    // MARK: - Mirror (RealityKit-free; pure, unit-testable)

    /// Reflects resolved transforms across the vertical plane so the rig reads
    /// like a mirror. A left↔right mirror flips only the *horizontal-sense*
    /// quantities — head X, head yaw, head roll, and the shoulder-disc twist.
    /// Head Z (depth), head pitch, scale and opacity have no left/right sense
    /// and pass through unchanged: negating *those* too would be a point
    /// inversion, not a mirror. Pure (no entity, no `debug` read) so it stays
    /// exactly as headlessly unit-testable as `resolve`.
    static func mirror(_ t: ResolvedPostureTransforms) -> ResolvedPostureTransforms {
        ResolvedPostureTransforms(
            discYawRadians: -t.discYawRadians,
            headTranslation: SIMD3<Float>(
                -t.headTranslation.x,
                t.headTranslation.y,
                t.headTranslation.z
            ),
            headEulerRadians: SIMD3<Float>(
                t.headEulerRadians.x,   // pitch — no left/right sense
                -t.headEulerRadians.y,  // yaw   — flipped
                -t.headEulerRadians.z   // roll  — flipped
            ),
            assemblyScale: t.assemblyScale,
            opacity: t.opacity
        )
    }

    // MARK: - Step 5: state tint with calibrating pulse (RealityKit-free; tested)

    /// The visualization fill colour, with a *pulsing* grey while the system
    /// is still calibrating.
    ///
    /// The four judged posture states keep the ViewModel's fixed, pairwise-
    /// distinct hues (`good` green / `drifting` amber / `bad` red / idle grey)
    /// — the VM owns that mapping; this only consumes its `stateColor`.
    /// `calibrating` instead *breathes*: the neutral grey's brightness is
    /// interpolated between a dim and a bright value by `pulse` (0…1, a sine
    /// phase the view drives from a `TimelineView`). Only luminance changes,
    /// never hue, so it reads as "working…" rather than as a posture verdict.
    /// Pure & deterministic, so the four-states-distinct guarantee is
    /// unit-tested headlessly (plan Step 5 done-criterion).
    static func stateTint(stateColor: Color, isCalibrating: Bool, pulse: Double) -> Color {
        guard isCalibrating else { return stateColor }
        let p = min(max(pulse, 0), 1)
        let white = pulseGreyMin + (pulseGreyMax - pulseGreyMin) * p
        return Color(white: white)
    }

    /// Calibration-pulse grey luminance bounds. Dim..bright keeps the pulse
    /// clearly visible without ever reaching the judged states' saturation.
    private static let pulseGreyMin = 0.35
    private static let pulseGreyMax = 0.85

    /// Composes the head's Euler radians into a single quaternion. Order
    /// `yaw · pitch · roll` (Y then X then Z): yaw turns the face left/right
    /// first, pitch tucks the chin, roll tilts last — the natural read for a
    /// head, and the VM already caps each axis so no gimbal extreme is hit.
    static func headOrientation(_ euler: SIMD3<Float>) -> simd_quatf {
        let yaw = simd_quatf(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
        let roll = simd_quatf(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
        return yaw * pitch * roll
    }

    // MARK: - DEBUG: per-channel isolation (tuning only)

    /// Per-channel switches for tuning **one variable at a time**. Every flag
    /// defaults to its production value, so an untouched `debug` reproduces the
    /// full behaviour exactly — important here because the nightly auto-build
    /// routine commits this file, so a frozen rig must never be the default.
    ///
    /// Flip a flag (and rebuild) to *freeze* that channel at its rest pose
    /// while you dial in another. Typical head-only workflow:
    /// `hideShoulderDisc = true`, then all of
    /// `sideLean / headForward / headYaw / headPitch / headRoll` = `false`
    /// except the single axis you are currently tuning.
    struct DebugChannels {
        /// Spin the shoulder disc about Y with twist. Off → disc held at rest
        /// (tick points to +Z front).
        var shoulderRotation = true
        /// Disable the shoulder disc subtree (disc + its child tick) entirely.
        /// Independent of `shoulderRotation`; use this to clear the disc out of
        /// frame so only the head is visible.
        var hideShoulderDisc = false
        /// Skip adding the calibration-baseline ghost (faint disc + head) so it
        /// doesn't sit behind an isolated head. Unlike the other hides this is
        /// enforced in the scene `make` (the ghost is a separate root the
        /// binding never looks up), so it only takes effect on scene rebuild.
        var hideGhost = false
        /// Disable the head's tone-divide band — the placeholder cylinder that
        /// z-fights the sphere (scene DEC-002). With it off, yaw reads cleanly
        /// off the bare sphere + nose tick, no striping.
        var hideHeadBand = false
        /// Head X translation from side lean. Off → X pinned to 0 (centred).
        var sideLean = true
        /// Head Z translation from forward offset. Off → Z pinned to 0.
        var headForward = true
        /// Head yaw (Y rotation). Off → no yaw.
        var headYaw = true
        /// Head pitch (X rotation). Off → no pitch.
        var headPitch = true
        /// Head roll (Z rotation). Off → no roll.
        var headRoll = true
        /// Whole-assembly uniform scale. Off → scale pinned to 1.
        var assemblyScale = true
        /// Whole-assembly opacity fade. Off → fully opaque.
        var opacity = true
        /// State colour / calibration-pulse retint. Off → keep the neutral
        /// scaffold greys (easiest for reading pure geometry while tuning).
        var stateTint = true
        /// Reflect the rig left↔right so it reads like a mirror (the natural
        /// feel for a front camera). Flips only the horizontal-sense channels
        /// (side-lean, head yaw, head roll, disc twist); pitch / forward /
        /// scale / opacity are deliberately untouched. Default **on** — the
        /// mirror reading is the production behaviour for a front camera;
        /// turn it off only to compare against the unmirrored geometry.
        var mirrored = true
    }

    /// Mutable so a tuning session can flip channels without threading a new
    /// parameter through the `RealityView` update closure. **Reset every flag
    /// to its default before shipping** (all `true`, `hideShoulderDisc` false).
    static var debug = DebugChannels()

    // MARK: - Per-assembly runtime cache (entity lookups + last-applied tint)

    /// Runtime-only component stored on the assembly root. Caches the named
    /// child entities so `apply` doesn't re-walk the scene graph by string
    /// every `TimelineView` tick, and the last applied tint so materials are
    /// only rebuilt when the colour actually changes — recreating an
    /// `UnlitMaterial` at frame rate churns renderer resources for a value
    /// that only changes on state transitions (and per-frame during the
    /// calibration pulse, where rebuilding is the intended behaviour).
    private struct RuntimeCache: Component {
        var disc: Entity?
        var head: Entity?
        var band: Entity?
        var lastTint: UIColor?
    }

    /// One-time component registration, folded into a `static let` so the
    /// first `apply` performs it exactly once.
    private static let registerRuntimeCache: Void = RuntimeCache.registerComponent()

    // MARK: - Apply (thin RealityKit adapter; not unit-tested)

    /// Pushes the resolved transforms onto the scaffold's named entities,
    /// found by `EntityName` from the `assembly` root (the scaffold↔binding
    /// contract) on first call and cached on the assembly thereafter. Called
    /// from the `RealityView` `update:` closure.
    ///
    /// `pulse` (0…1) is the calibration breathing phase the view supplies from
    /// its `TimelineView`; it only affects the calibrating tint (see
    /// ``stateTint(stateColor:isCalibrating:pulse:)``). Defaulted so the
    /// non-animated call sites and tests stay source-compatible.
    @MainActor
    static func apply(
        _ viewModel: PostureVisualizationViewModel,
        to assembly: Entity,
        pulse: Double = 0
    ) {
        _ = registerRuntimeCache
        var cache = assembly.components[RuntimeCache.self] ?? RuntimeCache(
            disc: assembly.findEntity(named: PostureVisualizationScene.EntityName.shoulderDisc),
            head: assembly.findEntity(named: PostureVisualizationScene.EntityName.head),
            band: assembly.findEntity(named: PostureVisualizationScene.EntityName.headBand)
        )
        defer { assembly.components.set(cache) }

        var t = resolve(from: viewModel)
        if debug.mirrored { t = mirror(t) }

        // Whole assembly: uniform scale + opacity fade (propagates to all
        // descendants). The camera lives outside the assembly, so scaling here
        // never moves the viewpoint. A gated-off channel rests at its identity
        // value (scale 1 / fully opaque) rather than tracking live data.
        assembly.scale = SIMD3<Float>(repeating: debug.assemblyScale ? t.assemblyScale : 1)
        assembly.components.set(OpacityComponent(opacity: debug.opacity ? t.opacity : 1))

        // Torso (named `ShoulderDisc`): twist about Y *and* lean about the
        // ground contact. The figure's torso origin is authored at the base, so
        // roll/pitch here rock the whole upper body about that contact point —
        // and because the head is parented to the torso, torso motion carries
        // the head (the propagation the rig is designed for). "Side lean" and
        // "forward" are reinterpreted from the resolved translation into lean
        // angles (see `leanRadiansPerMeter`). `hideShoulderDisc` disables the
        // whole subtree so the head can be isolated while tuning.
        if let torso = cache.disc {
            torso.isEnabled = !debug.hideShoulderDisc
            let twist = debug.shoulderRotation ? t.discYawRadians : 0
            let roll  = debug.sideLean    ? t.headTranslation.x * leanRadiansPerMeter : 0
            let pitch = debug.headForward ? t.headTranslation.z * forwardLeanRadiansPerMeter : 0
            let yawQ   = simd_quatf(angle: twist, axis: SIMD3<Float>(0, 1, 0))
            let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            let rollQ  = simd_quatf(angle: roll,  axis: SIMD3<Float>(0, 0, 1))
            torso.orientation = yawQ * pitchQ * rollQ
        }

        // Head: look (yaw/pitch/roll) about its authored neck origin. Position
        // is left exactly as the USDZ authored it (the neck atop the torso) —
        // unlike the old primitive scaffold we no longer translate the head;
        // lean is the torso's job above. This composes *on top of* the torso's
        // orientation because the head is parented to it, so head-look reads as
        // relative to the torso. Each axis stays independently gated for tuning.
        if let head = cache.head {
            head.orientation = headOrientation(SIMD3<Float>(
                debug.headPitch ? t.headEulerRadians.x : 0,
                debug.headYaw   ? t.headEulerRadians.y : 0,
                debug.headRoll  ? t.headEulerRadians.z : 0
            ))
        }

        // Tone-divide band is a placeholder that z-fights the sphere (scene
        // DEC-002); optionally disable it for a clean, unstriped yaw read.
        if let band = cache.band {
            band.isEnabled = !debug.hideHeadBand
        }

        // State colour tints the primary fills. The dark accents (band, nose
        // tick, disc tick) are separate named entities left untouched so the
        // structure stays legible. Step 5 polish: `stateTint` adds the
        // calibrating breathing pulse on top of the VM's discrete mapping.
        // Skipped wholesale when the channel is off so the head/disc keep their
        // neutral scaffold greys — clearest backdrop for tuning geometry.
        guard debug.stateTint else { return }
        let tint = UIColor(
            stateTint(
                stateColor: viewModel.stateColor,
                isCalibrating: viewModel.isCalibrating,
                pulse: pulse
            )
        )
        guard tint != cache.lastTint else { return }
        cache.lastTint = tint
        retint(cache.disc, to: tint)
        retint(cache.head, to: tint)
    }

    /// Recursively replaces every mesh's fill with a flat, lighting-independent
    /// tint (`UnlitMaterial` — matches the design's "no photorealistic
    /// materials"). Must recurse: in the loaded USDZ the `ModelComponent` lives
    /// on child mesh prims under the named `ShoulderDisc` / `Head` Xforms, so a
    /// single top-level `as? ModelEntity` cast would tint nothing.
    @MainActor
    private static func retint(_ entity: Entity?, to color: UIColor) {
        guard let entity else { return }
        if let model = entity as? ModelEntity, model.model != nil {
            model.model?.materials = [UnlitMaterial(color: color)]
        }
        for child in entity.children { retint(child, to: color) }
    }
}
