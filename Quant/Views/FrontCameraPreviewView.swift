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

        /// Keeps the picture the right way up as the phone turns (2026-11-11). Made once the
        /// session has its camera, which may be after the view is.
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var sessionStarted: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                if let sessionStarted { NotificationCenter.default.removeObserver(sessionStarted) }
                sessionStarted = nil
                return
            }
            followRotation()
            guard sessionStarted == nil else { return }
            sessionStarted = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.followRotation() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            followRotation()
        }

        private func followRotation() {
            if rotationCoordinator == nil,
               let device = previewLayer.session?.inputs
                   .compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first {
                let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                rotationObservation = coordinator.observe(
                    \.videoRotationAngleForHorizonLevelPreview, options: [.new]
                ) { @Sendable [weak self] _, _ in  // KVO calls on any thread
                    DispatchQueue.main.async { self?.followRotation() }
                }
                rotationCoordinator = coordinator
            }
            guard let rotationCoordinator, let connection = previewLayer.connection else { return }
            let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }
    }
}
