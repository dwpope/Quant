import AVFoundation
import Combine
import PostureLogic
import os.log

/// Captures video from the front-facing camera using AVFoundation.
///
/// This service provides the same `PoseProvider` interface as `ARSessionService`
/// but uses the front camera instead of the rear ARKit camera. Depth is always
/// nil since the front TrueDepth sensor isn't used (Vision 2D pipeline only).
///
/// ## Why AVFoundation Instead of ARKit?
///
/// ARKit's body tracking requires the rear camera. For front-facing posture
/// tracking (user faces the screen), we use AVFoundation to capture frames
/// and feed them into the same Vision-based pose detection pipeline.
///
/// ## Permission Handling
///
/// The service checks camera permission on `start()`:
/// - `.notDetermined` → requests permission
/// - `.authorized` → configures and starts capture
/// - `.denied` / `.restricted` → publishes status, returns without starting
///
/// The published `permissionStatus` lets the UI show appropriate messages.
final class FrontCameraSessionService: NSObject, PoseProvider {

    // MARK: - PoseProvider

    var framePublisher: AnyPublisher<InputFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    // MARK: - Published State

    @Published private(set) var permissionStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - Private Properties

    private let frameSubject = PassthroughSubject<InputFrame, Never>()

    /// The underlying AVCaptureSession, exposed so a preview layer can display the camera feed.
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.quant.frontCamera.session")
    private let outputQueue = DispatchQueue(label: "com.quant.frontCamera.output")
    private let logger = Logger(subsystem: "com.quant.posture", category: "FrontCamera")
    private var isConfigured = false

    // MARK: - PoseProvider Lifecycle

    func start() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run { permissionStatus = status }

        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { permissionStatus = granted ? .authorized : .denied }
            guard granted else {
                logger.warning("Camera permission denied by user")
                return
            }
        case .authorized:
            break
        case .denied:
            logger.warning("Camera permission denied — cannot start front camera")
            return
        case .restricted:
            logger.warning("Camera permission restricted — cannot start front camera")
            return
        @unknown default:
            logger.warning("Unknown camera permission status — cannot start front camera")
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureSession()
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        logger.info("Front camera session started")
    }

    func stop() {
        sessionQueue.async { [self] in
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
            logger.info("Front camera session stopped")
        }
    }

    // MARK: - Session Configuration

    private func configureSession() throws {
        guard !isConfigured else { return }

        guard let frontCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            logger.error("No front camera available")
            throw FrontCameraError.noFrontCamera
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .hd1280x720

        // Input
        let input = try AVCaptureDeviceInput(device: frontCamera)
        guard captureSession.canAddInput(input) else {
            logger.error("Cannot add front camera input to capture session")
            throw FrontCameraError.cannotAddInput
        }
        captureSession.addInput(input)

        // Output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard captureSession.canAddOutput(videoOutput) else {
            logger.error("Cannot add video output to capture session")
            throw FrontCameraError.cannotAddOutput
        }
        captureSession.addOutput(videoOutput)

        // Mirror the front camera so the image matches the user's perspective.
        // Vision pose detection expects a non-mirrored image for correct
        // left/right joint assignment, but ARKit's rear camera is also not
        // mirrored, so we disable mirroring to stay consistent with the
        // existing pipeline expectations.
        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = false
        }

        isConfigured = true
        logger.info("Front camera session configured (720p, BGRA)")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FrontCameraSessionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frame = InputFrame(
            timestamp: timestamp,
            pixelBuffer: pixelBuffer,
            depthMap: nil,
            cameraIntrinsics: nil
        )
        frameSubject.send(frame)
    }
}

// MARK: - Errors

enum FrontCameraError: LocalizedError {
    case noFrontCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noFrontCamera:
            return "No front-facing camera available on this device."
        case .cannotAddInput:
            return "Cannot add front camera input to the capture session."
        case .cannotAddOutput:
            return "Cannot add video output to the capture session."
        }
    }
}
