import RealityKit
import SwiftUI
import UIKit
import simd
import PostureLogic   // CriticallyDampedScalar — the pure, headlessly-tested follower

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
    /// 20 ⇒ device-tuned by eye (2026-06-19): 70 over-tilted, 20 reads as a
    /// natural lean. With the legacy ×0.1 chain a hard lean (latLean up to ~0.2)
    /// renders ≈0.2 × 0.1 × 20 = 0.4 rad ≈ 23° (then capped at leanCapRadians).
    static let leanRadiansPerMeterDefault: Float = 20.0

    /// Forward-lean gain: radians of forward base-pivot pitch per metre of the
    /// resolved forward offset (`headTranslation.z`). Separate knob so fore/aft
    /// reads can differ from side lean. Signed & tunable like `leanRadiansPerMeter`
    /// (not flipped by `mirror()` — fore/aft has no left/right sense).
    static var forwardLeanRadiansPerMeter: Float = forwardLeanRadiansPerMeterDefault
    static let forwardLeanRadiansPerMeterDefault: Float = 30.0

    /// Clamp on the lean tilt (radians) so a high gain can't rotate the figure
    /// past a believable lean (≈40°). Applied to both side roll and forward pitch.
    static let leanCapRadians: Float = 0.7

    /// How aggressively a head turn cancels side lean — disambiguating a true
    /// lateral lean (you stay facing the camera) from a chair swivel (your face
    /// turns, shifting the shoulder midpoint the same way). The lean roll is scaled
    /// by `cos(headYaw) ^ this`:
    ///   0 → off (no cancellation); 1 → plain `cos`; >1 → sharper (a small turn
    ///   already kills the lean). At a 90° turn the lean is fully cancelled for any
    ///   value > 0. Tunable via a DEBUG slider.
    static var leanTurnAttenPower: Float = leanTurnAttenPowerDefault
    static let leanTurnAttenPowerDefault: Float = 1.0

    /// Head pitch/roll come from noisy, yaw-cross-coupled 2D pose estimation, so
    /// the figure should *turn* (yaw) crisply and only nod/tilt on a clear,
    /// deliberate movement. `headTiltDeadzoneRadians` drops jitter below the
    /// threshold; `headTiltScale` gentles the remainder. Both compose with the
    /// cos(yaw) fade in `apply` that removes the turn-induced phantom tilt. Yaw
    /// itself is left at full strength — it's the reliable signal. (A residual
    /// forward tilt while facing forward is a *calibration* baseline, not this
    /// path: recapture neutral during calibration to clear it.)
    ///
    /// **Reduced 6°→2° on 2026-06-19** for a rounder head-circle: yaw has no
    /// deadzone, so a 6° pitch/roll deadzone made a small circle start as a flat
    /// horizontal line that popped vertical only past 6° (an oval, not a circle).
    /// The temporal `orientationSmoothTime` follower now absorbs the per-frame jitter
    /// the wide deadzone used to mask, so it can be tightened for symmetric onset.
    static let headTiltDeadzoneRadians: Float = 2 * .pi / 180
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
    /// `shapeHeadTilt`. Signed so the sign flips nod direction and the magnitude
    /// damps/boosts it. **−6.0** device-tuned (2026-06-19): the raw pitch read
    /// the wrong way (chin-down rendered as chin-up), so the sign is negative; at
    /// −3 the nod was still shallow (shaped angle is pre-scaled ×0.6 with a 6°
    /// deadzone), so it was opened to −6 for a legible nod.
    static var headPitchGain: Float = headPitchGainDefault
    static let headPitchGainDefault: Float = -6.0

    /// Asymmetric nod. A chin-DOWN (forward) nod is the posture that matters
    /// (forward-head), so `apply` multiplies the nod by this **only on the forward
    /// branch** — empirically the *negative* shaped-pitch sign here (the raw
    /// `PoseSample` "chin-down → headPitch > 0" is inverted by the VM's rest-relative
    /// subtraction and the negative base gain, so boosting the positive branch
    /// amplified the backward nod by mistake). 1.0 = symmetric with `headPitchGain`;
    /// >1 = the forward nod travels further while chin-up/back keeps the base gain.
    ///
    /// **Default reverted to 1.0 (symmetric) on 2026-06-19** at the user's request
    /// for a geometrically round head-circle: an axis-asymmetric gain *cannot*
    /// produce a round circle (the chin-down half stretches ~boost× past the
    /// chin-up half), so a round trajectory and an emphasised forward nod are
    /// mutually exclusive from one static gain. The earlier device-tuned 6.0
    /// (≈ −36 effective forward) is still reachable on the `nod ↓` slider for
    /// anyone who'd rather have the forward-head emphasis than the round circle.
    static var headPitchDownBoost: Float = headPitchDownBoostDefault
    static let headPitchDownBoostDefault: Float = 1.0

    /// Head-roll (tilt) display gain, applied on top of `shapeHeadTilt`. As
    /// `headPitchGain`: **−3.0** device-tuned (2026-06-19) — sign reversed so the
    /// head tilts toward the real side, magnitude boosted for a legible tilt.
    static var headRollGain: Float = headRollGainDefault
    static let headRollGainDefault: Float = -3.0

    // MARK: - Quaternion head-render tunables (Front-Face path)
    //
    // These drive the ADDITIVE quaternion branch in `apply` — used only when the VM
    // exposes a measured head quaternion (`headOrientationQuat != nil`, i.e. ARFace).
    // They replace the per-axis Euler gains above (×−6/−3/−0.6) with ONE uniform
    // rotation-angle gain + ONE total-angle clamp (`HeadOrientationRender`), so a
    // level left↔right turn can't "dip" — there is no per-axis channel to leak into.
    // The Euler gains above stay for the 2D / rear / dropout fallback. Sliders for
    // these land in R5.

    /// Uniform rotation-angle gain on the quaternion head path. **1.0 = faithful**
    /// (the figure mirrors the real head 1:1); ~1.3 = a slight legibility
    /// exaggeration. One scalar scales the rotation about whatever axis the head
    /// turned, so unlike the old anisotropic Euler gains it can never introduce a
    /// cross-axis leak. DEBUG-tunable; R5 adds the slider.
    static var headRotationGain: Float = headRotationGainDefault
    static let headRotationGainDefault: Float = 1.0

    /// Runaway guard on the TOTAL rendered head rotation angle (degrees) on the
    /// quaternion path. At `headRotationGain == 1` the rendered angle equals the REAL
    /// head angle, so a *working* clamp here would cap real head range — and worse, the
    /// hard `min()` in `HeadOrientationRender` PINS the angle once a turn passes the
    /// ceiling (a C0 kink the dt-aware follower lurches onto — the "yaw snaps" report),
    /// while also stealing the angle budget a nod-while-turned needs (pitch reads "dead"
    /// when turned). So the ceiling sits ABOVE physiological head range (~110°): the
    /// `min()` only ever guards a garbage/runaway quaternion and never bites a real pose.
    /// (Was 55° — a relic of the retired Euler ×−6 over-gain, which genuinely needed it.)
    static var headRotationMaxAngleDegrees: Float = headRotationMaxAngleDegreesDefault
    static let headRotationMaxAngleDegreesDefault: Float = 110

    /// The 24 proper (determinant +1) axis-aligned rotations of 3-space — the
    /// **octahedral rotation group**. The basis-remap `B` (`HeadOrientationRender.basis`)
    /// that takes the screen frame into the figure's Z-up frame (yaw=+Z, pitch=+X,
    /// roll=+Y) is one of these; conjugation by `B` remaps the axis of rotation without
    /// touching the angle, so single-axis-in stays single-axis-out (the no-leak
    /// invariant holds for *every* candidate). Rather than guess `B` blind, R5 exposes
    /// the whole list so a human on a TrueDepth device can step the index until a turn
    /// drives figure yaw, a nod pitch and a tilt roll — see the DevNotes entry.
    ///
    /// Generated by enumerating all signed permutation matrices (the 48 ways to place
    /// `±1` in each row/column of a 3×3 — every column a signed axis, no axis repeated)
    /// and keeping the `det ≈ +1` half (the 24 proper rotations; the other 24 are
    /// reflections). **Index 0 is the identity** (the candidate matrix that equals
    /// `matrix_identity_float3x3`), so a fresh build renders faithfully with no remap.
    static let headRenderBasisCandidates: [simd_quatf] = {
        // The six signed axes a column may take, and the three positions.
        let axes: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0),
            SIMD3(0, 1, 0), SIMD3(0, -1, 0),
            SIMD3(0, 0, 1), SIMD3(0, 0, -1)
        ]
        var rotations: [simd_quatf] = []
        // Each column picks a distinct unsigned axis (permutation) with an
        // independent sign → 3! × 2³ = 48 signed permutations.
        for c0 in axes {
            for c1 in axes where simd_abs(c1) != simd_abs(c0) {
                for c2 in axes where simd_abs(c2) != simd_abs(c0)
                                  && simd_abs(c2) != simd_abs(c1) {
                    let m = simd_float3x3(columns: (c0, c1, c2))
                    guard m.determinant > 0 else { continue } // proper rotations only
                    let q = simd_quatf(m).normalized
                    // De-dup: simd_quatf(matrix) is unique per rotation matrix here
                    // (no antipodal collision across distinct matrices), but guard anyway.
                    if !rotations.contains(where: { quaternionsEqual($0, q) }) {
                        rotations.append(q)
                    }
                }
            }
        }
        // Order so index 0 is the identity rotation, leaving the rest in
        // enumeration order (stable across builds).
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if let idx = rotations.firstIndex(where: { quaternionsEqual($0, identity) }), idx != 0 {
            rotations.swapAt(0, idx)
        }
        return rotations
    }()

    /// Two quaternions equal as rotations if they (or their antipodes) match
    /// componentwise within a small tolerance — used only to de-dup / locate the
    /// identity in `headRenderBasisCandidates`.
    private static func quaternionsEqual(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
        let va = a.vector, vb = b.vector
        let same = simd_length(va - vb) < 1e-4
        let anti = simd_length(va + vb) < 1e-4
        return same || anti
    }

    /// Index into ``headRenderBasisCandidates`` selecting the live basis-remap `B`.
    /// The `axis map` stepper in the calibration overlay still walks this for
    /// device confirmation, but the default is no longer a guess: the source
    /// quaternion is now GRAVITY-LEVELLED (turn about +Y up, nod about +X right,
    /// tilt about +Z toward-camera), so the remap into the figure's Z-up frame
    /// (yaw=+Z, pitch=+X, roll=+Y) is derivable a priori — see
    /// ``headRenderBasisIndexDefault``. Per-axis DIRECTIONS may still need the
    /// mirror flag on device; the axis ROUTING should not.
    static var headRenderBasisIndex: Int = headRenderBasisIndexDefault

    /// The candidate index of the derived levelled→figure remap: X→X (nod→pitch),
    /// Y→Z (turn→yaw), Z→−Y (tilt→roll, direction confirmed on device). Located
    /// by value so the enumeration order can never silently invalidate it; falls
    /// back to identity (0) if absent, which cannot happen for a proper signed
    /// permutation but keeps the lookup total.
    static let headRenderBasisIndexDefault: Int = {
        let derived = simd_quatf(simd_float3x3(columns: (
            SIMD3<Float>(1, 0, 0),    // levelled X (right)          → figure X (pitch axis)
            SIMD3<Float>(0, 0, 1),    // levelled Y (world up)       → figure Z (yaw axis)
            SIMD3<Float>(0, -1, 0)    // levelled Z (toward camera)  → figure −Y (roll axis)
        )))
        return headRenderBasisCandidates.firstIndex(where: { quaternionsEqual($0, derived) }) ?? 0
    }()

    /// The FIXED basis-remap `B` (`HeadOrientationRender.basis`) into the figure's
    /// Z-up frame (yaw=+Z, pitch=+X, roll=+Y), resolved from the live
    /// ``headRenderBasisIndex``. Conjugation by `B` remaps the axis of rotation without
    /// touching the angle, so single-axis-in stays single-axis-out — the no-leak
    /// invariant is independent of which candidate is selected. The R4 `apply` call
    /// site reads this name unchanged.
    static var headRenderBasis: simd_quatf {
        let i = min(max(headRenderBasisIndex, 0), headRenderBasisCandidates.count - 1)
        return headRenderBasisCandidates[i]
    }

    /// Final clamp on the **rendered** head pitch/roll (radians), applied in `apply`
    /// AFTER the display gains. The binding gains (×−6 pitch / ×−3 roll) are applied
    /// *past* the ViewModel's pre-gain ±60/±45° cap and nothing re-clamped after, so a
    /// moderate real nod composed past vertical (≈208° at cap saturation) and the head
    /// "snapped" to the extreme. This bounds the composed angle to a physically sane
    /// head range. ~55° pitch lets a full deliberate nod still reach the limit without
    /// flattening intended motion; ~35° roll likewise. (Yaw is net ≈×0.9 and needs no
    /// post-gain clamp — the ViewModel ±90° cap already bounds it.)
    static let headRenderPitchCapRadians: Float = 55 * .pi / 180
    static let headRenderRollCapRadians: Float = 35 * .pi / 180

    /// Turn→nod decoupling — kills the "W" a pure left↔right head sweep traces.
    /// 2D pose cross-couples a pure TURN into a phantom NOD (a pure left/right turn
    /// reads as ~−20° pitch). The `cos(yaw)` tilt-fade only fully cancels that at
    /// the turn *extremes*, so the residual peaks at MID-turn and a left↔right sweep
    /// dips at mid-left and mid-right — a W instead of a flat line. This subtracts an
    /// estimate of the phantom: a turn-correlated pitch bias (`∝ sin|yaw|`, even in
    /// turn direction) is added to the *raw* pitch **before** `shapeHeadTilt`, so the
    /// correction rides the very same deadzone/scale/fade pipeline as the phantom it
    /// cancels. Crucially this is *additive* and keyed only off yaw — unlike
    /// strengthening the fade it does **not** scale down a real, deliberate nod, so a
    /// head-circle stays round while a pure turn flattens.
    ///
    /// **Signed** (the cross-coupling sign is empirical): dial on device until a pure
    /// left↔right sweep is flat; flip the sign if the W gets *deeper*. 0 = off (raw
    /// phantom shows through). Units: radians of correction at a full (90°) turn.
    ///
    /// **Defaulted OFF (0) on 2026-06-19**: on device this *additive* correction
    /// couldn't flatten the W — its fixed `sin|yaw|` shape didn't match the device's
    /// phantom, so raising it bulged the mid-turn instead of cancelling (an additive
    /// term adds signal blind to what's there, so it overshoots). The robust knob is
    /// the multiplicative `tiltTurnFadePower` below, which can only scale the phantom
    /// toward zero and can't overshoot. Left here (off) in case a future, better
    /// phantom model wants a feed-forward term.
    static var turnTiltDecouple: Float = turnTiltDecoupleDefault
    static let turnTiltDecoupleDefault: Float = 0.0

    /// Exponent on the `cos(yaw)` tilt-fade (the `yawAtten` in `apply`). Pitch & roll
    /// are multiplied by `cos(yaw)^this`, so a head TURN fades the (unreliable, often
    /// phantom) nod/tilt: at 1.0 it's plain `cos`; **>1 fades harder**, killing the
    /// phantom-nod "W" of a pure left↔right sweep. Multiplicative, so it can only
    /// drive the phantom *toward* flat — it can't overshoot into a bulge the way the
    /// additive `turnTiltDecouple` did.
    ///
    /// The honest trade: it also fades a *real* nod while the head is turned, so a
    /// deliberate head-circle flattens slightly at its left/right extents. 1.0 keeps
    /// the circle fully round (but shows the full W); higher trades roundness for a
    /// flatter turn. **2.0** device-default 2026-06-19 as a middle ground — raise
    /// toward ~4 for a flatter sweep, drop to 1.0 for a perfectly round circle.
    static var tiltTurnFadePower: Float = tiltTurnFadePowerDefault
    static let tiltTurnFadePowerDefault: Float = 2.0

    /// True while the head source is ARKit's decoupled `ARFaceAnchor` (camera mode
    /// `.frontFace`); set by `AppModel` on every mode change. The whole point of the
    /// `tiltTurnFadePower` fade is to cancel a *phantom* nod that the old coupled 2D
    /// estimate leaked on a pure turn — but the ARFaceAnchor decomposition is
    /// decoupled by construction (a pure yaw gives pitch = 0 exactly), so there is no
    /// phantom to cancel and the fade would only flatten a *real* head-circle at its
    /// left/right extents. While this is set, `apply` reads `faceTiltTurnFadePower`
    /// (default **0 = fade off = perfectly round**) instead. The legacy 2D path's
    /// `tiltTurnFadePower` (2.0) and its slider are left exactly as tuned.
    static var faceTrackingActive: Bool = false

    static var faceTiltTurnFadePower: Float = faceTiltTurnFadePowerDefault
    static let faceTiltTurnFadePowerDefault: Float = 0.0

    /// The fade exponent in force for the active head source — what `apply` actually
    /// uses, and what the `turn↓tilt` slider reads/writes, so one slider tunes
    /// whichever mode is live.
    static var activeTiltTurnFadePower: Float {
        get { faceTrackingActive ? faceTiltTurnFadePower : tiltTurnFadePower }
        set {
            if faceTrackingActive { faceTiltTurnFadePower = newValue }
            else { tiltTurnFadePower = newValue }
        }
    }

    /// The reset/is-default target for the active head source's fade.
    static var activeTiltTurnFadePowerDefault: Float {
        faceTrackingActive ? faceTiltTurnFadePowerDefault : tiltTurnFadePowerDefault
    }

    /// Temporal smoothing for the head & torso orientation. Each frame the freshly
    /// resolved pose is only a *target*; the rendered orientation eases toward it with a
    /// **critically-damped, dt-aware follower** (``CriticallyDampedScalar`` applied per
    /// quaternion component), so a stepwise pose source reads as one fluid arc instead of
    /// a jittery snap. Crucially all four components chase the **combined** target
    /// together, so a blended nod-and-turn (a head "circle") eases along the shortest arc
    /// on the rotation manifold and traces a curve, rather than each axis jerking.
    ///
    /// Why a damped follower and not the old fixed-weight slerp: the head-angle source is
    /// republished at the pipeline's ~10 Hz while the renderer ticks at 60–120 Hz, so the
    /// target is a *staircase*. A first-order slerp chasing a staircase lunges on every
    /// step then decays — a ~10 Hz pulse (the "tracking still isn't smooth" report). A
    /// second-order critically-damped follower carries velocity, so velocity stays
    /// continuous across a step (no pulse), and being **dt-aware** its feel is invariant
    /// to frame rate (ProMotion 120, thermal throttle) — the old fixed weight was not.
    ///
    /// Units are **seconds** (≈ time to converge), NOT a per-frame weight. **0 = no
    /// smoothing** (snap straight to the live pose, the old top-of-slider behaviour);
    /// larger = smoother but laggier. 0.09 s ≈ one 10 Hz sample interval — enough to
    /// bridge the staircase without visible lag. Head and torso share the one value.
    /// Tunable live via a DEBUG slider.
    static var orientationSmoothTime: Float = orientationSmoothTimeDefault
    static let orientationSmoothTimeDefault: Float = 0.09

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
        /// Per-component critically-damped followers carrying the *rendered* head and
        /// torso orientation plus their angular velocity across frames — the state that
        /// turns a stepwise target into a fluid, pulse-free follow. They self-seed on
        /// their first `update` (snap to the first target, no swing-in from identity).
        var headDamp = DampedOrientation()
        var torsoDamp = DampedOrientation()
        /// Wall-clock timestamp (`timeIntervalSinceReferenceDate`) of the previous
        /// `apply`, so the next call can derive a real `dt` for the dt-aware followers.
        /// `nil` until the first animated call; a non-clock caller (tests) leaves it nil
        /// and the followers snap.
        var lastApplyTime: TimeInterval?
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
        pulse: Double = 0,
        now: TimeInterval = 0
    ) {
        _ = registerRuntimeCache
        var cache = assembly.components[RuntimeCache.self] ?? RuntimeCache(
            disc: assembly.findEntity(named: PostureVisualizationScene.EntityName.shoulderDisc),
            head: assembly.findEntity(named: PostureVisualizationScene.EntityName.head),
            band: assembly.findEntity(named: PostureVisualizationScene.EntityName.headBand)
        )
        defer { assembly.components.set(cache) }

        // Real elapsed time for the dt-aware orientation followers. The view passes
        // `now` = wall clock (`timeIntervalSinceReferenceDate`); the first animated frame
        // (no prior timestamp) and any non-clock caller (tests, with the default 0) get
        // dt = 0 so the followers snap to the live pose instead of swinging in from a
        // stale one. Clamp to [1/1000, 1/15] s: the ceiling stops a stall or a background
        // resume from spiking the step; the tiny floor only guards a duplicate/zero-delta
        // timestamp (keeps dt > 0) and sits far below any real refresh rate (even 240 Hz),
        // so every reachable frame rate integrates its true dt — the followers stay
        // frame-rate honest.
        let dt: Float
        if now > 0, let last = cache.lastApplyTime {
            dt = Float(min(max(now - last, 1.0 / 1000.0), 1.0 / 15.0))
        } else {
            dt = 0
        }
        if now > 0 { cache.lastApplyTime = now }

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
            // Side lean, faded out as the head turns away: a chair swivel shifts the
            // shoulder midpoint just like a lean does, but it also turns the face
            // (head yaw), so cos(headYaw) tells the two apart — facing the camera
            // (yaw≈0) keeps the lean, turning away cancels it. `t.headEulerRadians.y`
            // is the display yaw (≤ ±90° via yawCapDegrees); cos symmetric, so the
            // mirror flip doesn't matter.
            let yawCos = cos(min(abs(t.headEulerRadians.y), .pi / 2))   // 1 facing → 0 turned
            let leanAtten = powf(yawCos, leanTurnAttenPower)
            let roll  = (debug.sideLean ? max(-cap, min(cap, t.headTranslation.x * leanRadiansPerMeter)) : 0) * leanAtten
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
            let torsoTarget = yawQ * pitchQ * rollQ
            // dt-aware critically-damped follow (see `orientationSmoothTime`); the
            // follower carries the rendered pose + velocity inside the cache.
            torso.orientation = cache.torsoDamp.update(
                toward: torsoTarget, smoothTime: orientationSmoothTime, dt: dt
            )
        }

        // Head: look (yaw/pitch/roll) about its authored neck origin. Position
        // is left exactly as the USDZ authored it (the neck atop the torso) —
        // unlike the old primitive scaffold we no longer translate the head;
        // lean is the torso's job above. This composes *on top of* the torso's
        // orientation because the head is parented to it, so head-look reads as
        // relative to the torso. Each axis stays independently gated for tuning.
        if let head = cache.head {
          // QUATERNION PATH (Front Face): when the VM exposes a measured head
          // quaternion, drive the figure head straight from it via the pure
          // `HeadOrientationRender` (rest-relative → uniform angle gain → angle clamp
          // → basis remap). Additive and GATED on `headOrientationQuat != nil`: this
          // never runs for the 2D / rear / dropout fallback, which takes the unchanged
          // Euler `else` below. Viz-only — nothing here touches scoring.
          if let headQuat = viewModel.headOrientationQuat {
            // Per-axis debug isolation (headYaw/Pitch/Roll) is Euler-path-only; on the
            // quaternion path the head is one unit (a rotation can't be cleanly frozen
            // per-axis). Only the all-off case is honoured — freeze to identity.
            let allHeadAxesOff = !debug.headYaw && !debug.headPitch && !debug.headRoll
            let target: simd_quatf
            if allHeadAxesOff {
                target = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            } else {
                // Rest-relative + uniform gain + total-angle clamp + basis remap, all
                // pure. Rest defaults to identity until the VM captures a neutral.
                let render = HeadOrientationRender(
                    gain: headRotationGain,
                    maxAngleRadians: headRotationMaxAngleDegrees * .pi / 180,
                    basis: headRenderBasis
                )
                let figure = render.render(
                    head: headQuat,
                    rest: viewModel.restOrientationQuat ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                )
                // Mirror (front camera): negate the imaginary components about the
                // figure's yaw(+Z) and roll(+Y) axes, keep pitch(+X) — matching the
                // Euler `mirror()` which flips yaw+roll and keeps pitch. DEVICE-CONFIRM
                // in R5 (verify which components flip on the figure).
                if debug.mirrored {
                    let v = figure.vector
                    target = simd_quatf(vector: SIMD4<Float>(v.x, -v.y, -v.z, v.w))
                } else {
                    target = figure
                }
            }
            // Feed the EXISTING dt-aware critically-damped follower, exactly like the
            // Euler path — same follower, same smooth time — so the temporal feel is
            // identical and a combined nod+turn eases as one arc.
            head.orientation = cache.headDamp.update(
                toward: target, smoothTime: orientationSmoothTime, dt: dt
            )
          } else {
            // EULER PATH (2D / rear / dropout fallback) — UNCHANGED from before the
            // quaternion branch landed.
            // Head look — yaw-dominant. Yaw is the reliable signal and drives the
            // head at full strength. Pitch/roll are noisy and yaw-cross-coupled
            // (a pure left/right turn reads as ~−20° pitch + ~−15° roll), and
            // since the neck pivot sits below the head's centre that phantom tilt
            // swings the head *down*. So pitch/roll are shaped (deadzone + gentle
            // scale + cos(yaw) fade — see `shapeHeadTilt`) so the head turns
            // crisply and only nods/tilts on a clear, deliberate movement.
            let rawYaw = debug.headYaw ? t.headEulerRadians.y : 0
            // Damp pitch/roll by the *actual* turn amount (pre-gain), so the
            // cross-coupling fade tracks how far the head really turned. The
            // `tiltTurnFadePower` exponent sets how hard a turn fades the (phantom)
            // nod/tilt — >1 flattens the pure-turn "W"; monotone, can't overshoot.
            let yawAtten = powf(cos(min(abs(rawYaw), .pi / 2)), activeTiltTurnFadePower)
            // Flip + tame the yaw for display: front-camera direction and a
            // proportional turn instead of slamming to the ±90° cap.
            let renderedYaw = rawYaw * headYawGain
            // Cancel the yaw→pitch cross-coupling that makes a pure left↔right sweep
            // trace a "W": add a turn-correlated bias to the raw pitch *before*
            // shaping, so it rides the same deadzone/scale/fade as the phantom it
            // cancels. sin(turn) is 0 facing forward (nothing to cancel) and grows
            // with the turn; abs() makes it even so left and right correct alike.
            // Additive + yaw-keyed, so a real nod is untouched (see turnTiltDecouple).
            let turnMag = min(abs(rawYaw), .pi / 2)
            let decoupledPitch = t.headEulerRadians.x + turnTiltDecouple * sin(turnMag)
            // Nod is asymmetric: the forward (chin-DOWN) nod gets extra travel;
            // chin-up/back keeps the base gain. Empirically the forward nod renders
            // on the NEGATIVE shaped-pitch branch here (the VM's rest-relative
            // subtraction + the negative base gain invert the raw PoseSample sign),
            // so boost when shapedPitch < 0. Mirror leaves pitch unflipped.
            let shapedPitch = shapeHeadTilt(decoupledPitch, yawAtten: yawAtten)
            let pitchDownBoost: Float = shapedPitch < 0 ? headPitchDownBoost : 1
            // Clamp the RENDERED pitch/roll AFTER the gains (see headRenderPitchCapRadians):
            // the ×−6/×−3 binding gains run past the ViewModel's pre-gain cap, so without
            // this a moderate nod composes past vertical and the head snaps to the extreme.
            let pitchTerm = debug.headPitch ? shapedPitch * headPitchGain * pitchDownBoost : 0
            let rollTerm  = debug.headRoll  ? shapeHeadTilt(t.headEulerRadians.z, yawAtten: yawAtten) * headRollGain : 0
            let headTarget = headOrientation(SIMD3<Float>(
                max(-headRenderPitchCapRadians, min(headRenderPitchCapRadians, pitchTerm)),
                renderedYaw,
                max(-headRenderRollCapRadians, min(headRenderRollCapRadians, rollTerm))
            ))
            // Critically-damped follow from the previous rendered pose toward this
            // target so a combined nod+turn eases as one arc — the fluid, pulse-free
            // follow that a per-axis snap can't give (see `orientationSmoothTime`).
            head.orientation = cache.headDamp.update(
                toward: headTarget, smoothTime: orientationSmoothTime, dt: dt
            )
          }
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
