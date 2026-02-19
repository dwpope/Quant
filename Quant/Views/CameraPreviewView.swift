import SwiftUI
import RealityKit
import ARKit

struct CameraPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions = .disableAREnvironmentLighting
        arView.environment.background = .cameraFeed()
        arView.session = session
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
