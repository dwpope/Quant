import ARKit
import Combine
import PostureLogic
import os.log

final class ARSessionService: NSObject, PoseProvider {
    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit
    // back-deploy shim out of XCTest's NSInvocation-driven dealloc path, which
    // otherwise corrupts the heap and aborts under Xcode 26 / iOS 26.
    nonisolated deinit {}

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

    /// Whether the rear camera is usable, for the screen. See `RearCameraStatus`.
    var statusPublisher: AnyPublisher<RearCameraStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    var status: RearCameraStatus { statusSubject.value }

    /// The underlying ARSession, exposed so an ARView can share it for camera preview.
    let session = ARSession()
    private let frameSubject = PassthroughSubject<InputFrame, Never>()
    private let sessionStateSubject = CurrentValueSubject<SessionState, Never>(.idle)
    private let statusSubject = CurrentValueSubject<RearCameraStatus, Never>(.ok)
    private var startedAt: Date?
    private var receivedAnyFrame = false
    private var loggedNoFrames = false
    private let logger = Logger(subsystem: "com.quant.posture", category: "ARSession")

    private var currentConfig: ARWorldTrackingConfiguration?
    private var lastFrameTime: Date?
    private var frameTimeoutTimer: Timer?
    private var isRecovering = false
    private var recoveryAttempts = 0
    private var depthEnabled = false
    /// Between `sessionWasInterrupted` and `sessionInterruptionEnded` (a phone call, Siri):
    /// no frames is expected then, not a resource problem (2026-10-11). The timeout used to
    /// "recover" through the interruption and, on its third try, switched depth off for good.
    private var isInterrupted = false
    /// The session's own restarts (a frame timeout, a failure, an interruption ending) go ahead
    /// only while the run they were queued in is still going: not after `stop()`, as for heat.
    private var runs = CameraRuns()

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
        runs.started()
        startedAt = Date()
        receivedAnyFrame = false
        loggedNoFrames = false
        lastFrameTime = nil
        statusSubject.send(.ok)
        session.run(config)

        sessionStateSubject.send(.running)
        logger.info("ARSession started with ARWorldTrackingConfiguration")

        recoveryAttempts = 0
        startFrameTimeoutMonitoring()
    }

    func stop() {
        runs.stopped()
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

    /// Whether a silence is a frame timeout worth recovering from: not during an interruption.
    static func isFrameTimeout(secondsSinceFrame: TimeInterval, interrupted: Bool) -> Bool {
        !interrupted && secondsSinceFrame > 2.0
    }

    private func checkFrameTimeout() {
        guard let lastFrame = lastFrameTime else {
            // Once, not every 2 s: past the grace period it becomes a screen, not a log line.
            if !loggedNoFrames {
                logger.warning("⚠️ No frames received yet")
                loggedNoFrames = true
            }
            if status == .ok,
               let problem = RearCameraStatus.afterFrameCheck(
                   secondsSinceStart: Date().timeIntervalSince(startedAt ?? Date()),
                   receivedAnyFrame: receivedAnyFrame) {
                logger.error("Rear camera sent no frames — showing the person a retry screen")
                statusSubject.send(problem)
            }
            return
        }

        let timeSinceLastFrame = Date().timeIntervalSince(lastFrame)
        if Self.isFrameTimeout(secondsSinceFrame: timeSinceLastFrame, interrupted: isInterrupted) {
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

        let run = runs.current
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.isRecovering = false
            guard self.runs.isStill(run) else { return }  // stopped meanwhile

            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.logger.info("✓ Session restarted after resource constraint")
        }
    }
}

extension ARSessionService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameTime = Date()
        receivedAnyFrame = true
        if status != .ok { statusSubject.send(.ok) }

        // Try smoothed depth first (preferred), then fall back to regular depth
        let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap

        let inputFrame = InputFrame(
            timestamp: FrameClock.shared.calendarSeconds(fromUptime: frame.timestamp),  // one clock: see FrameClock
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
        if let problem = RearCameraStatus.after(error: error) {
            statusSubject.send(problem)
        }

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
        isInterrupted = true
        sessionStateSubject.send(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        logger.info("ARSession interruption ended - resuming")
        isInterrupted = false
        lastFrameTime = Date()  // a fresh 2 s before the timeout looks again
        recoveryAttempts = 0

        guard runs.isStill(runs.current) else { return }  // stopped during the interruption
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
        let run = runs.current
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.runs.isStill(run) else { return }
            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.sessionStateSubject.send(.running)
            self.logger.info("ARSession recovery attempted")
        }
    }
}
