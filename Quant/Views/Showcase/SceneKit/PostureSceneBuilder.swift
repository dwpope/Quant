import SceneKit
import UIKit

/// Factory for creating and manipulating SceneKit scenes used by posture variants.
/// Provides a programmatic stick-figure body model and metric-driven deformation.
enum PostureSceneBuilder {

    // MARK: - Scene Creation

    /// Creates a SceneKit scene with a stick-figure body model as named `SCNNode` hierarchy.
    ///
    /// Node hierarchy:
    /// - `pelvis` (root body node)
    ///   - `spine`
    ///     - `chest`
    ///       - `neck`
    ///         - `head` (sphere)
    ///       - `leftShoulder` (strut)
    ///       - `rightShoulder` (strut)
    static func makeBodyScene() -> SCNScene {
        let scene = SCNScene()

        // Pelvis — base of the body
        let pelvis = SCNNode()
        pelvis.name = "pelvis"
        pelvis.position = SCNVector3(0, -0.3, 0)
        let pelvisGeo = SCNBox(width: 0.25, height: 0.08, length: 0.12, chamferRadius: 0.02)
        pelvisGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        pelvis.geometry = pelvisGeo
        scene.rootNode.addChildNode(pelvis)

        // Spine — vertical cylinder connecting pelvis to chest
        let spine = SCNNode()
        spine.name = "spine"
        spine.position = SCNVector3(0, 0.15, 0)
        let spineGeo = SCNCylinder(radius: 0.025, height: 0.3)
        spineGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        spine.geometry = spineGeo
        pelvis.addChildNode(spine)

        // Chest — box at the top of the spine
        let chest = SCNNode()
        chest.name = "chest"
        chest.position = SCNVector3(0, 0.2, 0)
        let chestGeo = SCNBox(width: 0.3, height: 0.1, length: 0.14, chamferRadius: 0.02)
        chestGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        chest.geometry = chestGeo
        spine.addChildNode(chest)

        // Neck — thin cylinder above chest
        let neck = SCNNode()
        neck.name = "neck"
        neck.position = SCNVector3(0, 0.1, 0)
        let neckGeo = SCNCylinder(radius: 0.02, height: 0.1)
        neckGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        neck.geometry = neckGeo
        chest.addChildNode(neck)

        // Head — sphere on top of neck
        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 0.1, 0)
        let headGeo = SCNSphere(radius: 0.08)
        headGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        head.geometry = headGeo
        neck.addChildNode(head)

        // Left shoulder strut
        let leftShoulder = SCNNode()
        leftShoulder.name = "leftShoulder"
        leftShoulder.position = SCNVector3(-0.2, 0.02, 0)
        let lShoulderGeo = SCNCylinder(radius: 0.02, height: 0.15)
        lShoulderGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        leftShoulder.geometry = lShoulderGeo
        leftShoulder.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        chest.addChildNode(leftShoulder)

        // Right shoulder strut
        let rightShoulder = SCNNode()
        rightShoulder.name = "rightShoulder"
        rightShoulder.position = SCNVector3(0.2, 0.02, 0)
        let rShoulderGeo = SCNCylinder(radius: 0.02, height: 0.15)
        rShoulderGeo.firstMaterial?.diffuse.contents = UIColor.systemGray3
        rightShoulder.geometry = rShoulderGeo
        rightShoulder.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        chest.addChildNode(rightShoulder)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.position = SCNVector3(0, 0, 2.5)
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        // Directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(directionalLight)

        return scene
    }

    // MARK: - Deformation

    /// Animates scene node transforms based on posture metric ratios.
    ///
    /// - `forwardCreep`: Rotates spine forward (positive X rotation)
    /// - `headDrop`: Rotates head downward
    /// - `shoulderRounding`: Pulls shoulder endpoints inward
    /// - `lateralLean`: Tilts spine laterally (Z rotation)
    /// - `twist`: Rotates spine about Y axis
    static func applyPostureDeformation(to scene: SCNScene, data: PostureDisplayData) {
        let fc = data.metric(for: .forwardCreep).clampedRatio
        let hd = data.metric(for: .headDrop).clampedRatio
        let sr = data.metric(for: .shoulderRounding).clampedRatio
        let ll = data.metric(for: .lateralLean).clampedRatio
        let tw = data.metric(for: .twist).clampedRatio

        let root = scene.rootNode

        // Spine: forward creep → X rotation, lateral lean → Z rotation, twist → Y rotation
        if let spine = root.childNode(withName: "spine", recursively: true) {
            spine.eulerAngles = SCNVector3(
                fc * 0.5,       // forward bend up to ~29 degrees
                tw * 0.3,       // twist up to ~17 degrees
                ll * 0.4        // lateral lean up to ~23 degrees
            )
        }

        // Head: head drop → additional forward rotation
        if let head = root.childNode(withName: "head", recursively: true) {
            head.eulerAngles = SCNVector3(
                hd * 0.6,       // nod forward up to ~34 degrees
                0, 0
            )
        }

        // Shoulders: shoulder rounding → pull inward
        let shoulderInward = sr * 0.08
        if let leftShoulder = root.childNode(withName: "leftShoulder", recursively: true) {
            leftShoulder.position.x = -0.2 + shoulderInward
            leftShoulder.eulerAngles = SCNVector3(sr * 0.3, 0, Float.pi / 2)
        }
        if let rightShoulder = root.childNode(withName: "rightShoulder", recursively: true) {
            rightShoulder.position.x = 0.2 - shoulderInward
            rightShoulder.eulerAngles = SCNVector3(sr * 0.3, 0, Float.pi / 2)
        }

        // Update emission colors based on stress
        updateStressColors(scene: scene, data: data)
    }

    // MARK: - Stress Visualization

    /// Updates material emission colors to show stress/tension on body parts.
    private static func updateStressColors(scene: SCNScene, data: PostureDisplayData) {
        let root = scene.rootNode

        let mappings: [(String, MetricKey)] = [
            ("spine", .forwardCreep),
            ("head", .headDrop),
            ("neck", .headDrop),
            ("leftShoulder", .shoulderRounding),
            ("rightShoulder", .shoulderRounding),
            ("pelvis", .lateralLean),
            ("chest", .twist),
        ]

        for (nodeName, metricKey) in mappings {
            guard let node = root.childNode(withName: nodeName, recursively: true),
                  let material = node.geometry?.firstMaterial else { continue }
            let ratio = data.metric(for: metricKey).clampedRatio
            if ratio > 0.01 {
                let r = CGFloat(min(ratio * 1.5, 1.0))
                let g = CGFloat(max(0.3 - ratio * 0.3, 0))
                material.emission.contents = UIColor(red: r, green: g, blue: 0, alpha: CGFloat(ratio))
            } else {
                material.emission.contents = UIColor.clear
            }
        }
    }
}
