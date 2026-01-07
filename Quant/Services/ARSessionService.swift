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

    private var currentConfig: ARBodyTrackingConfiguration?

    func start() async throws {
        let config = ARBodyTrackingConfiguration()
        config.frameSemantics = .bodyDetection

        currentConfig = config
        session.delegate = self
        session.run(config)

        sessionStateSubject.send(.running)
        logger.info("ARSession started successfully")
    }

    func stop() {
        session.pause()
        sessionStateSubject.send(.idle)
        logger.info("ARSession stopped")
    }
}

extension ARSessionService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let inputFrame = InputFrame(
            timestamp: frame.timestamp,
            pixelBuffer: frame.capturedImage,
            depthMap: frame.sceneDepth?.depthMap,
            cameraIntrinsics: frame.camera.intrinsics
        )
        frameSubject.send(inputFrame)
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
