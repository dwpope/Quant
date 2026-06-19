import RealityKit
import UIKit

/// Static RealityKit scene construction for the posture visualization.
///
/// Step 3 scaffold: builds *static placeholder* entities only — a shoulder
/// disc, a head sphere with a tone-divide band, and direction tick markers,
/// plus a camera looking down at a slight angle. No live ViewModel binding
/// yet; Step 4 looks these entities up by their ``EntityName`` and drives
/// their transforms in the `RealityView` update closure.
///
/// Kept as value-type-only API (an `enum` namespace + static factories) so it
/// introduces no `@MainActor` class — sidestepping the toolchain's isolated
/// `deinit` SIGABRT hazard documented in `implementation/progress.md`.
enum PostureVisualizationScene {

    /// Stable entity names. Step 4 resolves transforms via `findEntity(named:)`
    /// using these constants, so the scaffold and the binding step share one
    /// source of truth for the scene graph.
    enum EntityName {
        static let assembly = "PostureAssembly"
        static let shoulderDisc = "ShoulderDisc"
        static let shoulderTick = "ShoulderTick"
        static let head = "Head"
        static let headBand = "HeadBand"
        static let headTick = "HeadTick"
        static let camera = "PostureCamera"
        /// Step 5 — faint static baseline silhouette at the calibrated rest
        /// pose. A separate scene root (not under ``assembly``) so the binding
        /// never transforms it; live deviation reads against this fixed ghost.
        static let ghost = "PostureGhost"
    }

    /// Scene-graph *rest pose* constants the Step 4 binding needs to resolve
    /// transforms without reading live entity state. Sibling of ``EntityName``
    /// in the shared scaffold↔binding contract: `EntityName` says *which*
    /// entities exist, `Layout` says *where* they rest.
    enum Layout {
        /// Head centre height above the disc's top face. The binding sets the
        /// head's X (side lean) and Z (forward) each frame but must preserve
        /// this resting Y.
        ///
        /// Used by the *procedural fallback* scaffold and the `resolve` mapping
        /// (unit-tested). The loaded USDZ figure authors its own head placement
        /// (neck origin), so the live binding no longer writes head position.
        static let headCenterY: Float = 0.15

        /// Uniform scale applied to the loaded USDZ figure. The Blender model is
        /// authored at human scale (~3.73 m tall); the camera was tuned for the
        /// old ~0.2 m primitive scaffold, so the figure is normalised down to
        /// fit. Lives on a *dedicated layer* under the assembly root — the
        /// binding overwrites the root's `scale` every frame for forward-creep,
        /// so normalisation must sit below it to survive. Single knob for the
        /// figure's on-screen size; tune by eye.
        static let figureScale: Float = 0.08
    }

    // MARK: - Tunable scene constants (mirrored/extended by Step 4 mapping)

    private enum Metric {
        static let discRadius: Float = 0.20
        static let discHeight: Float = 0.02
        static let headRadius: Float = 0.06
        static let bandRadius: Float = 0.064
        static let bandHeight: Float = 0.012
        /// Camera elevation measured from the horizontal plane. A low angle
        /// gives a near eye-level *front* view of the standing figure (the old
        /// ~80° near-top-down value suited the flat shoulder-disc scaffold, not
        /// an upright 3D figure). Tune by eye alongside ``Layout/figureScale``.
        static let cameraElevationDegrees: Float = 15
        static let cameraDistance: Float = 0.70
    }

    // MARK: - Materials

    /// Flat, lighting-independent fill. `UnlitMaterial` ignores scene lights —
    /// matches the design's "no photorealistic materials" anti-goal.
    @MainActor
    private static func unlit(white: CGFloat) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(white: white, alpha: 1))
        return material
    }

    // MARK: - Assembly

    /// The posture assembly: shoulder disc + head + tick markers, rooted at a
    /// single named entity so Step 4 can scale/translate the whole group.
    @MainActor
    static func makeAssembly() -> Entity {
        let assembly = Entity()
        assembly.name = EntityName.assembly

        // Shoulder disc — a very flat cylinder, neutral light tone.
        let disc = ModelEntity(
            mesh: .generateCylinder(height: Metric.discHeight, radius: Metric.discRadius),
            materials: [unlit(white: 0.80)]
        )
        disc.name = EntityName.shoulderDisc
        assembly.addChild(disc)

        // Front-of-disc direction tick (dark box at the +Z rim). Parented
        // under the disc (not the assembly) so the Step 4 binding's single
        // `disc.orientation` carries the tick around with shoulder twist —
        // design: "tick marker… rotates around vertical axis with twist".
        // The disc sits at the assembly origin with no offset, so the tick's
        // disc-local position equals its former assembly-local position.
        let shoulderTick = ModelEntity(
            mesh: .generateBox(width: 0.030, height: 0.026, depth: 0.050),
            materials: [unlit(white: 0.25)]
        )
        shoulderTick.name = EntityName.shoulderTick
        shoulderTick.position = SIMD3(0, Metric.discHeight / 2, Metric.discRadius)
        disc.addChild(shoulderTick)

        // Head sphere — light tone (top hemisphere reads light from above).
        let head = ModelEntity(
            mesh: .generateSphere(radius: Metric.headRadius),
            materials: [unlit(white: 0.90)]
        )
        head.name = EntityName.head
        head.position = SIMD3(0, Layout.headCenterY, 0)
        assembly.addChild(head)

        // Tone-divide band at the head's equator (dark). A true two-tone
        // hemisphere reveal is deferred to Step 5 polish (see DEC-002): a
        // single-submesh generated sphere ignores a second material, so a
        // faithful split needs custom mesh/UV work out of scope for a
        // build-only scaffold.
        let band = ModelEntity(
            mesh: .generateCylinder(height: Metric.bandHeight, radius: Metric.bandRadius),
            materials: [unlit(white: 0.30)]
        )
        band.name = EntityName.headBand
        band.position = SIMD3(0, Layout.headCenterY, 0)
        head.addChild(band)

        // "Nose" direction tick on the head's equator (+Z), dark accent.
        let headTick = ModelEntity(
            mesh: .generateBox(width: 0.018, height: 0.018, depth: 0.020),
            materials: [unlit(white: 0.20)]
        )
        headTick.name = EntityName.headTick
        headTick.position = SIMD3(0, 0, Metric.headRadius)
        head.addChild(headTick)

        return assembly
    }

    // MARK: - USDZ figure loader

    /// Loads the stylized Blender figure (`quant_person.usdz`) and wraps it in a
    /// container named ``EntityName/assembly`` for the binding to drive.
    ///
    /// Layering (top → bottom), each layer owned by a distinct concern:
    /// * **container** (`PostureAssembly`) — the binding sets its `scale`
    ///   (forward-creep) and `OpacityComponent` every frame.
    /// * **figure** (the loaded USD root) — holds the constant
    ///   ``Layout/figureScale`` normalisation, *below* the binding's per-frame
    ///   root scale so it is never clobbered.
    /// * `ShoulderDisc` (torso, origin at ground contact) → `Head` (origin at
    ///   neck) — the named entities the binding rotates.
    ///
    /// Falls back to the procedural ``makeAssembly()`` scaffold if the asset is
    /// missing or fails to decode, so the view always shows *something*. Stays a
    /// static func on the value-type namespace — no class, no isolated `deinit`
    /// (the SIGABRT hazard this whole file is shaped around).
    @MainActor
    static func loadAssembly() async -> Entity {
        let container = Entity()
        container.name = EntityName.assembly

        guard let url = Bundle.main.url(forResource: "quant_person", withExtension: "usdz"),
              let figure = try? await Entity(contentsOf: url) else {
            return makeAssembly()   // graceful fallback to the primitive scaffold
        }

        figure.scale = SIMD3<Float>(repeating: Layout.figureScale)
        // Flat, lighting-independent look (the asset ships no light), matching
        // the design's "no photorealistic materials" anti-goal and guaranteeing
        // the figure is visible regardless of scene lighting.
        applyUnlit(to: figure, white: 0.85)
        // The Blender root was renamed "PostureAssembly" too; rename the loaded
        // copy so it can't collide with the container on `findEntity` /
        // `first(where:)` lookups.
        figure.findEntity(named: EntityName.assembly)?.name = "FigureRoot"
        container.addChild(figure)
        return container
    }

    /// Recursively replaces every mesh's materials with a flat ``UnlitMaterial``.
    /// USD meshes sit on child prims *under* the named Xforms (`ShoulderDisc` /
    /// `Head`), so a top-level `as? ModelEntity` would miss them — this walks the
    /// whole subtree.
    @MainActor
    private static func applyUnlit(to entity: Entity, white: CGFloat) {
        if let model = entity as? ModelEntity, model.model != nil {
            model.model?.materials = [unlit(white: white)]
        }
        for child in entity.children { applyUnlit(to: child, white: white) }
    }

    // MARK: - Ghost (calibrated-baseline silhouette)

    /// A faint, static duplicate of the disc + head at the *calibrated rest
    /// pose* (Step 5 polish, design "baseline ghost entities"). Added once as
    /// its own scene root — ``PostureVisualizationBinding/apply(_:to:pulse:)``
    /// only ever resolves entities under ``EntityName/assembly``, so the ghost
    /// is never moved, scaled, or retinted: it stays put as the reference the
    /// live posture is judged against. Opacity is set on the root so it
    /// propagates to both children.
    /// Clones the live assembly at its *rest pose* (creation time, before any
    /// binding tick) into a faint, static baseline. The clone keeps the loaded
    /// figure's geometry and unlit materials but is added as its own scene root
    /// renamed ``EntityName/ghost`` — the binding only ever resolves entities
    /// under ``EntityName/assembly``, so the ghost is never moved, scaled, or
    /// retinted: it stays put as the reference the live posture is judged
    /// against. Renaming the clone's root is essential — an un-renamed clone
    /// would also answer to `PostureAssembly` and the view's `first(where:)`
    /// could bind the *ghost* instead of the live figure.
    @MainActor
    static func makeGhost(from assembly: Entity) -> Entity {
        let ghost = assembly.clone(recursive: true)
        ghost.name = EntityName.ghost
        // Faint so it reads as "where calibrated posture sits" behind the
        // fully-opaque live assembly, not as a competing solid object.
        ghost.components.set(OpacityComponent(opacity: 0.15))
        return ghost
    }

    // MARK: - Camera

    /// A perspective camera placed above the assembly at a slight angle so the
    /// head's tone divide stays visible (design: "~80° from horizontal").
    /// Added directly to the scene (not under ``makeAssembly``) so Step 4's
    /// disc rotation never moves the viewpoint.
    @MainActor
    static func makeCamera() -> Entity {
        let camera = PerspectiveCamera()
        camera.name = EntityName.camera

        let target = SIMD3<Float>(0, Layout.headCenterY, 0)
        let elevation = Metric.cameraElevationDegrees * .pi / 180
        let position = SIMD3<Float>(
            0,
            target.y + Metric.cameraDistance * sin(elevation),
            Metric.cameraDistance * cos(elevation)
        )
        camera.look(at: target, from: position, relativeTo: nil)
        return camera
    }
}
