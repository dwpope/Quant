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

    // MARK: - Apply (thin RealityKit adapter; not unit-tested)

    /// Pushes the resolved transforms onto the scaffold's named entities,
    /// found by `EntityName` from the `assembly` root (the scaffold↔binding
    /// contract). Called from the `RealityView` `update:` closure.
    @MainActor
    static func apply(_ viewModel: PostureVisualizationViewModel, to assembly: Entity) {
        let t = resolve(from: viewModel)

        // Whole assembly: uniform scale + opacity fade (propagates to all
        // descendants). The camera lives outside the assembly, so scaling here
        // never moves the viewpoint.
        assembly.scale = SIMD3<Float>(repeating: t.assemblyScale)
        assembly.components.set(OpacityComponent(opacity: t.opacity))

        // Shoulder disc rotates about Y with twist; the tick is its child, so
        // one rotation carries the direction marker too.
        if let disc = assembly.findEntity(named: PostureVisualizationScene.EntityName.shoulderDisc) {
            disc.orientation = simd_quatf(angle: t.discYawRadians, axis: SIMD3<Float>(0, 1, 0))
        }

        // Head: side-lean / forward translation (rest Y preserved) + combined
        // yaw/pitch/roll. Its band + nose tick are children, so they follow.
        if let head = assembly.findEntity(named: PostureVisualizationScene.EntityName.head) {
            head.position = t.headTranslation
            head.orientation = headOrientation(t.headEulerRadians)
        }

        // State colour tints the primary fills. The dark accents (band, nose
        // tick, disc tick) are separate named entities left untouched so the
        // structure stays legible; richer state transitions are Step 5 polish.
        let tint = UIColor(viewModel.stateColor)
        retint(assembly.findEntity(named: PostureVisualizationScene.EntityName.shoulderDisc), to: tint)
        retint(assembly.findEntity(named: PostureVisualizationScene.EntityName.head), to: tint)
    }

    /// Replaces a model entity's fill with a flat, lighting-independent tint
    /// (`UnlitMaterial` — matches the design's "no photorealistic materials").
    @MainActor
    private static func retint(_ entity: Entity?, to color: UIColor) {
        guard let model = entity as? ModelEntity else { return }
        model.model?.materials = [UnlitMaterial(color: color)]
    }
}
