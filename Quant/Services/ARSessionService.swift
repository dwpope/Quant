import ARKit
import Combine
import PostureLogic
import os.log

final class ARSessionService: NSObject, PoseProvider {
    enum SessionState {
        case idle
        case running
        case interrupted
        case failed(Error)
    }

    var framePublisher: AnyPublisher<InputFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    var sessionStatePublisher: AnyPublisher<SessionState, Never> {
        sessionStateSubject.eraseToAnyPublisher()
    }

    private let session = ARSession()
    private let frameSubject = PassthroughSubject<InputFrame, Never>()
    private let sessionStateSubject = CurrentValueSubject<SessionState, Never>(.idle)
    private let logger = Logger(subsystem: "com.quant.posture", category: "ARSession")

    private var currentConfig: ARWorldTrackingConfiguration?
    private var lastFrameTime: Date?
    private var frameTimeoutTimer: Timer?
    private var isRecovering = false
    private var recoveryAttempts = 0
    private var depthEnabled = false

    func start() async throws {
        // Use ARWorldTrackingConfiguration for depth support
        // (We use Vision framework for pose detection, not ARBodyTracking)
        let config = ARWorldTrackingConfiguration()

        // Try to enable depth - check both smoothedSceneDepth and sceneDepth
        depthEnabled = false

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics = .smoothedSceneDepth
            logger.info("✓ Smoothed scene depth enabled (LiDAR detected)")
            depthEnabled = true
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
            logger.info("✓ Scene depth enabled (LiDAR detected)")
            depthEnabled = true
        }

        if !depthEnabled {
            logger.warning("⚠️ Scene depth not available - will use 2D-only mode")
            logger.info("→ Device may lack LiDAR sensor")
        }

        currentConfig = config
        session.delegate = self
        session.run(config)

        sessionStateSubject.send(.running)
        logger.info("ARSession started with ARWorldTrackingConfiguration")

        recoveryAttempts = 0
        startFrameTimeoutMonitoring()
    }

    func stop() {
        frameTimeoutTimer?.invalidate()
        frameTimeoutTimer = nil
        session.pause()
        sessionStateSubject.send(.idle)
        logger.info("ARSession stopped")
    }

    private func startFrameTimeoutMonitoring() {
        frameTimeoutTimer?.invalidate()
        frameTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFrameTimeout()
        }
    }

    private func checkFrameTimeout() {
        guard let lastFrame = lastFrameTime else {
            logger.warning("⚠️ No frames received yet")
            return
        }

        let timeSinceLastFrame = Date().timeIntervalSince(lastFrame)
        if timeSinceLastFrame > 2.0 {
            logger.error("⛔️ Frame timeout: No frames for \(String(format: "%.1f", timeSinceLastFrame))s - resource constraints detected")
            attemptResourceRecovery()
        } else if timeSinceLastFrame < 0.5 && recoveryAttempts > 0 {
            logger.info("✓ Frames flowing normally - resetting recovery counter")
            recoveryAttempts = 0
        }
    }

    private func attemptResourceRecovery() {
        guard !isRecovering else {
            logger.info("Recovery already in progress, skipping")
            return
        }

        guard let config = currentConfig else {
            logger.error("Cannot attempt recovery - no configuration available")
            return
        }

        isRecovering = true
        recoveryAttempts += 1

        if recoveryAttempts >= 3 && depthEnabled {
            logger.warning("🔄 Multiple recovery attempts failed - disabling depth to reduce resource load")
            config.frameSemantics = []
            depthEnabled = false
            currentConfig = config
        } else {
            logger.warning("🔄 Attempting resource recovery #\(self.recoveryAttempts) - restarting session")
        }

        session.pause()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.logger.info("✓ Session restarted after resource constraint")
            self.isRecovering = false
        }
    }
}

extension ARSessionService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameTime = Date()

        // Try smoothed depth first (preferred), then fall back to regular depth
        let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap

        let inputFrame = InputFrame(
            timestamp: frame.timestamp,
            pixelBuffer: frame.capturedImage,
            depthMap: depthMap,
            cameraIntrinsics: frame.camera.intrinsics
        )
        frameSubject.send(inputFrame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            logger.info("📷 Camera tracking: Normal")
        case .notAvailable:
            logger.error("📷 Camera tracking: Not Available")
        case .limited(let reason):
            handleLimitedTracking(reason: reason)
        }
    }

    private func handleLimitedTracking(reason: ARCamera.TrackingState.Reason) {
        switch reason {
        case .initializing:
            logger.info("📷 Camera tracking limited: Initializing")
        case .excessiveMotion:
            logger.warning("📷 Camera tracking limited: Excessive motion")
        case .insufficientFeatures:
            logger.warning("📷 Camera tracking limited: Insufficient features")
        case .relocalizing:
            logger.info("📷 Camera tracking limited: Relocalizing")
        @unknown default:
            logger.warning("📷 Camera tracking limited: Unknown reason")
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        logger.error("ARSession failed with error: \(error.localizedDescription)")
        sessionStateSubject.send(.failed(error))

        let arError = error as NSError
        if arError.domain == ARError.errorDomain {
            switch ARError.Code(rawValue: arError.code) {
            case .sensorFailed:
                logger.warning("Sensor failed - attempting recovery")
                attemptRecovery()
            case .cameraUnauthorized:
                logger.error("Camera unauthorized - cannot recover")
            case .worldTrackingFailed:
                logger.warning("Tracking failed - attempting recovery")
                attemptRecovery()
            default:
                logger.error("Unhandled ARError: \(arError.code)")
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        logger.info("ARSession was interrupted")
        sessionStateSubject.send(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        logger.info("ARSession interruption ended - resuming")

        guard let config = currentConfig else {
            logger.error("No configuration available for resume")
            return
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        sessionStateSubject.send(.running)
    }

    private func attemptRecovery() {
        guard let config = currentConfig else {
            logger.error("Cannot attempt recovery - no configuration available")
            return
        }

        logger.info("Attempting to restart ARSession")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.sessionStateSubject.send(.running)
            self.logger.info("ARSession recovery attempted")
        }
    }
}
