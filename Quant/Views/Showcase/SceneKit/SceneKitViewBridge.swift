import SwiftUI
import SceneKit

/// A `UIViewRepresentable` wrapper around `SCNView` for posture visualization.
/// Manages scene lifecycle, renders a posture body model, and updates deformation
/// in response to `PostureDisplayData` changes.
struct SceneKitViewBridge: UIViewRepresentable {
    let scene: SCNScene
    let data: PostureDisplayData
    let isPlaying: Bool

    init(scene: SCNScene, data: PostureDisplayData, isPlaying: Bool = true) {
        self.scene = scene
        self.data = data
        self.isPlaying = isPlaying
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.isPlaying = isPlaying
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.isPlaying = isPlaying
        PostureSceneBuilder.applyPostureDeformation(to: scene, data: data)
    }
}
