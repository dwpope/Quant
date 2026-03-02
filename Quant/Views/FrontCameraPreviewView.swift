import SwiftUI
import AVFoundation

/// Displays the front camera feed using an AVCaptureVideoPreviewLayer.
///
/// This is the front-camera equivalent of `CameraPreviewView` (which uses
/// ARView for the rear camera). It wraps an `AVCaptureVideoPreviewLayer`
/// so the user can see themselves while posture tracking runs.
struct FrontCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    /// A UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer.
    /// This ensures the preview layer always matches the view's bounds.
    class PreviewUIView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
