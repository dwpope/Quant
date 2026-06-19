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
    /// resolved lean offset.
    ///
    /// NOTE the scale: `headTranslation.x = lateralLeanSigned × sideLeanPointsPerUnit
    /// (100) × metersPerPoint (0.001)`, so this gain multiplies a value ≈
    /// `lateralLeanSigned × 0.1`. A real torso lean shifts the shoulder midpoint
    /// only ~0.05–0.10 of frame width, so the default is deliberately large to make
    /// that small normalized signal a visible tilt (the old 2.0 assumed a
    /// near-full-frame "unit lean" that never happens). The points→metres chain is
    /// now vestigial (the head no longer translates); a future cleanup can fold it
    /// into a single degrees-per-unit gain.
    ///
    /// **Signed & tunable.** A `#if DEBUG` slider overrides it live on device so
    /// we can confirm direction (slide past 0 to flip the lean sign — net sign is
    /// gain × `mirror()`'s `-headTranslation.x` flip) and dial intensity in one
    /// gesture. Output is clamped to ±`leanCapRadians`. Release uses the default.
    static var leanRadiansPerMeter: Float = leanRadiansPerMeterDefault
    /// 70 ⇒ a full side lean (measured latLean ≈ 0.059 on device) reads as
    /// ≈0.059 × 0.1 × 70 ≈ 0.41 rad ≈ 24° of tilt (then capped at leanCapRadians).
    static let leanRadiansPerMeterDefault: Float = 70.0

    /// Forward-lean gain: radians of forward base-pivot pitch per metre of the
    /// resolved forward offset (`headTranslation.z`). Separate knob so fore/aft
    /// reads can differ from side lean. Signed & tunable like `leanRadiansPerMeter`
    /// (not flipped by `mirror()` — fore/aft has no left/right sense).
    static var forwardLeanRadiansPerMeter: Float = forwardLeanRadiansPerMeterDefault
    static let forwardLeanRadiansPerMeterDefault: Float = 30.0

    /// Clamp on the lean tilt (radians) so a high gain can't rotate the figure
    /// past a believable lean (≈40°). Applied to both side roll and forward pitch.
    static let leanCapRadians: Float = 0.7

    /// Head pitch/roll come from noisy, yaw-cross-coupled 2D pose estimation, so
    /// the figure should *turn* (yaw) crisply and only nod/tilt on a clear,
    /// deliberate movement. `headTiltDeadzoneRadians` drops jitter below ~6°;
    /// `headTiltScale` gentles the remainder. Both compose with the cos(yaw)
    /// fade in `apply` that removes the turn-induced phantom tilt. Yaw itself is
    /// left at full strength — it's the reliable signal. (A residual forward
    /// tilt while facing forward is a *calibration* baseline, not this path:
    /// recapture neutral during calibration to clear it.)
    static let headTiltDeadzoneRadians: Float = 6 * .pi / 180
    static let headTiltScale: Float = 0.6

    /// Head-yaw display gain. **Negative flips** the turn direction to match the
    /// front-camera view (mirror is also on); **magnitude < 1** tames the
    /// ViewModel's ×1.5 amplification, which otherwise pegs even a moderate head
    /// turn at the ±90° cap and reads as "all or nothing" — at 0.6 a full turn
    /// renders ~54° and the mid-range tracks proportionally. Signed & tunable
    /// (DEBUG slider): flip the sign to reverse, raise/lower for sensitivity.
    static var headYawGain: Float = headYawGainDefault
    static let headYawGainDefault: Float = -0.6

    /// Head-pitch (nod / forward-head) display gain, applied on top of
    /// `shapeHeadTilt`. 1.0 = the shaped angle as-is; signed so a DEBUG slider can
    /// flip nod direction or damp/boost the forward-head cue.
    static var headPitchGain: Float = headPitchGainDefault
    static let headPitchGainDefault: Float = 1.0

    /// Head-roll (tilt) display gain, applied on top of `shapeHeadTilt`. As
    /// `headPitchGain`, for the head's side-tilt.
    static var headRollGain: Float = headRollGainDefault
    static let headRollGainDefault: Float = 1.0

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
        // AXES NOTE — the loaded figure's local frame is Blender **Z-up**: the
        // USDZ's Y-up conversion sits on the `/root` prim, so every entity below
        // it (torso, head) keeps a Z-up local frame (head's local "up toward the
        // crown" is +Z, its front is +Y). So the head's anatomical axes are:
        //   yaw (turn)  → up        = +Z
        //   pitch (nod) → left-right = +X
        //   roll (tilt) → front      = +Y
        // NOT the Y-up RealityKit default. Yawing about +Y (the old assumption)
        // rotated the head about a near-horizontal world axis — i.e. it *tilted*
        // the head down instead of turning it (the reported bug).
        let yaw = simd_quatf(angle: euler.y, axis: SIMD3<Float>(0, 0, 1))
        let pitch = simd_quatf(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
        let roll = simd_quatf(angle: euler.z, axis: SIMD3<Float>(0, 1, 0))
        return yaw * pitch * roll
    }

    /// Shapes a noisy head pitch/roll angle (radians) for display: a deadzone
    /// drops jitter below ``headTiltDeadzoneRadians``, ``headTiltScale`` gentles
    /// the remainder, and `yawAtten` (cos of the current yaw) fades it out as the
    /// head turns — where 2D pose estimation can't be trusted for tilt. Pure, so
    /// it could be unit-tested, but it's tuning so it lives with `apply`'s knobs.
    static func shapeHeadTilt(_ angle: Float, yawAtten: Float) -> Float {
        let beyond = max(abs(angle) - headTiltDeadzoneRadians, 0)
        let signed: Float = angle < 0 ? -beyond : beyond
        return signed * headTiltScale * yawAtten
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
        /// Skip adding the calibration-baseline ghost (faint rest-pose clone) so
        /// it doesn't sit in front of / behind the live figure. Unlike the other
        /// hides this is enforced in the scene `make` (the ghost is a separate
        /// root the binding never looks up), so it only takes effect on scene
        /// rebuild — dismiss and reopen the visualization to apply.
        ///
        /// Default **on** as a product decision (2026-06-14): with the stylized
        /// USDZ figure the baseline clone obstructs the read more than it helps, so
        /// the shipped visualization omits it. Flip to `false` only to bring the
        /// calibration baseline back for debugging.
        var hideGhost = true
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

    #if DEBUG
    /// Live torso telemetry for the tuning HUD — diagnostic only. Tells us, on
    /// device, whether the `ShoulderDisc` entity actually resolved and the angles
    /// (degrees) `apply` last wrote to it, so "the figure won't lean" can be
    /// pinned to entity-missing vs. zero-signal vs. wrong-axis without guessing.
    static var debugDiscResolved = false
    static var debugTorsoRollDegrees: Float = 0
    static var debugTorsoPitchDegrees: Float = 0
    static var debugTorsoTwistDegrees: Float = 0
    #endif

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
        #if DEBUG
        debugDiscResolved = cache.disc != nil
        #endif
        if let torso = cache.disc {
            torso.isEnabled = !debug.hideShoulderDisc
            // Depth-gated channels: axial twist and forward-lean both need the
            // third dimension (twist = shoulder *tilt* in 2D, not rotation; forward
            // = depth-only headForwardOffset). Off in 2D so the figure doesn't
            // misbehave on signals it can't see; they light up automatically under
            // LiDAR. Side lean stays unconditional — it's a true 2D signal.
            let depthOK = viewModel.depthActive
            let twist = (debug.shoulderRotation && depthOK) ? t.discYawRadians : 0
            let cap = leanCapRadians
            let roll  = debug.sideLean ? max(-cap, min(cap, t.headTranslation.x * leanRadiansPerMeter)) : 0
            let pitch = (debug.headForward && depthOK) ? max(-cap, min(cap, t.headTranslation.z * forwardLeanRadiansPerMeter)) : 0
            #if DEBUG
            debugTorsoTwistDegrees = twist * 180 / .pi
            debugTorsoRollDegrees = roll * 180 / .pi
            debugTorsoPitchDegrees = pitch * 180 / .pi
            #endif
            // Z-up local frame (see headOrientation's AXES NOTE): twist about
            // up (+Z), forward-lean pitch about left-right (+X), side-lean roll
            // about front (+Y).
            let yawQ   = simd_quatf(angle: twist, axis: SIMD3<Float>(0, 0, 1))
            let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            let rollQ  = simd_quatf(angle: roll,  axis: SIMD3<Float>(0, 1, 0))
            torso.orientation = yawQ * pitchQ * rollQ
        }

        // Head: look (yaw/pitch/roll) about its authored neck origin. Position
        // is left exactly as the USDZ authored it (the neck atop the torso) —
        // unlike the old primitive scaffold we no longer translate the head;
        // lean is the torso's job above. This composes *on top of* the torso's
        // orientation because the head is parented to it, so head-look reads as
        // relative to the torso. Each axis stays independently gated for tuning.
        if let head = cache.head {
            // Head look — yaw-dominant. Yaw is the reliable signal and drives the
            // head at full strength. Pitch/roll are noisy and yaw-cross-coupled
            // (a pure left/right turn reads as ~−20° pitch + ~−15° roll), and
            // since the neck pivot sits below the head's centre that phantom tilt
            // swings the head *down*. So pitch/roll are shaped (deadzone + gentle
            // scale + cos(yaw) fade — see `shapeHeadTilt`) so the head turns
            // crisply and only nods/tilts on a clear, deliberate movement.
            let rawYaw = debug.headYaw ? t.headEulerRadians.y : 0
            // Damp pitch/roll by the *actual* turn amount (pre-gain), so the
            // cross-coupling fade tracks how far the head really turned.
            let yawAtten = cos(min(abs(rawYaw), .pi / 2))
            // Flip + tame the yaw for display: front-camera direction and a
            // proportional turn instead of slamming to the ±90° cap.
            let renderedYaw = rawYaw * headYawGain
            head.orientation = headOrientation(SIMD3<Float>(
                debug.headPitch ? shapeHeadTilt(t.headEulerRadians.x, yawAtten: yawAtten) * headPitchGain : 0,
                renderedYaw,
                debug.headRoll  ? shapeHeadTilt(t.headEulerRadians.z, yawAtten: yawAtten) * headRollGain : 0
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
