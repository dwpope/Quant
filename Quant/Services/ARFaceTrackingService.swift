import ARKit
import Combine
import PostureLogic
import os.log
import simd

/// Layer 1 pose provider: sources a true metric 6-DOF head orientation from the
/// TrueDepth `ARFaceAnchor` while still publishing the front camera image so the
/// existing Vision body-pose path can recover shoulders (side-lean survives).
///
/// ```
/// ARFaceTrackingConfiguration (front TrueDepth)
///   ├─ frame.capturedImage ──► InputFrame.pixelBuffer ──► Vision body pose ─► shoulders ─► side-lean
///   └─ ARFaceAnchor.transform ─► HeadOrientationDecomposition ─► InputFrame.externalHeadAngles ─► head
/// ```
///
/// Only this file touches ARKit; the trig lives in the pure, headlessly-tested
/// `HeadOrientationDecomposition`. The decomposed angles travel as a plain
/// `HeadAngles` value — no `ARFrame`/`ARFaceAnchor` is ever allowed to escape the
/// delegate (they retain the capture pipeline).
///
/// Mirrors `ARSessionService`'s session-recovery machinery; the configuration type
/// (and the head-angle extraction) is the only real difference.
final class ARFaceTrackingService: NSObject, PoseProvider {
    // Teardown only releases stored properties; it touches no main-actor state.
    // `nonisolated` keeps Swift's MainActor isolated-deinit shim out of XCTest's
    // NSInvocation dealloc path (heap-corruption workaround — see ARSessionService).
    nonisolated deinit {}

    /// Whether this device has the TrueDepth hardware face tracking needs. Evaluated
    /// once — hardware doesn't change at runtime. Callers MUST gate mode selection on
    /// this; `session.run` with an unsupported configuration would crash.
    static let isFaceTrackingSupported = ARFaceTrackingConfiguration.isSupported

    // MARK: - DEBUG diagnostics (read by the dev HUD; no behavior)
    //
    // Static so the values overlay can read them without plumbing through the VM.
    // They answer, on device, WHERE the ARFace head source breaks vs the 2D fallback
    // the figure silently uses: did `start()` run the session (`diagSessionStarted`),
    // are its delegate frames arriving (`diagFramesSeen` climbing), and is a face ever
    // tracked (`diagTrackedSeen` climbing)? All-zero ⇒ this service isn't running /
    // not the attached provider; frames>0 but tracked==0 ⇒ session runs but never
    // tracks a face. Data-race-tolerant (diagnostic counters only).
    static var diagSessionStarted = false
    static var diagFramesSeen = 0
    static var diagTrackedSeen = 0
    /// Live count of consecutive frames since the last *tracked* face (mirrors
    /// `framesSinceTrackedFace`); `diagMaxSinceTracked` is its session high-water mark.
    /// These size the grace window empirically: when this exceeds `maxStaleFrames`,
    /// the head orientation has collapsed to nil and `src` flips to 2D. Watch the peak
    /// while turning — it is the true worst gap between tracked frames on a turn,
    /// independent of the window (it keeps counting past the cap until a face returns).
    static var diagFramesSinceTracked = 0
    static var diagMaxSinceTracked = 0
    /// Head-to-camera distance in meters from the last *tracked* face (Spike S1:
    /// lean-in SNR measurement — read by the dev HUD `dist` row). `nan` until the
    /// first tracked face; holds the last tracked value across dropouts (the `gap`
    /// row already conveys staleness).
    static var diagHeadDistanceMeters = Float.nan

    var framePublisher: AnyPublisher<InputFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    /// Exposed so a `CameraPreviewView` can share this session for the live preview
    /// (required: the preview is bound per camera mode, so `.frontFace` needs its own
    /// session to display).
    let session = ARSession()

    private let frameSubject = PassthroughSubject<InputFrame, Never>()
    private let logger = Logger(subsystem: "com.quant.posture", category: "ARFaceTracking")

    private var currentConfig: ARFaceTrackingConfiguration?
    private var lastFrameTime: Date?
    private var frameTimeoutTimer: Timer?
    private var isRecovering = false
    private var recoveryAttempts = 0

    // MARK: - Head-pose dropout smoothing (hold-last-good)

    /// Last decoupled head pose from a tracked face, reused for a brief grace window
    /// when the anchor momentarily drops, so the figure freezes rather than snapping
    /// back to the coupled legacy fallback (the dropout seam). Released to `nil` after
    /// the window so a truly-absent face hands off cleanly to tracking-quality loss.
    private var lastGoodAngles: HeadAngles?
    /// The quaternion sibling of `lastGoodAngles`: the gravity-levelled relative head
    /// rotation (turn about world-up, nod about horizontal-right, tilt about the
    /// toward-camera axis — NOT the Euler-contract signs, which are applied only to
    /// `HeadAngles`), held across the SAME grace window so the viz-only quaternion
    /// channel is present exactly when the Euler angles are (and released to `nil`
    /// at the same frame). Keeping them in lockstep keeps presence-gating consistent.
    private var lastGoodOrientation: simd_quatf?
    private var framesSinceTrackedFace = 0
    /// Grace window: how many consecutive untracked ARFrames to hold the last good
    /// head pose before releasing to nil (which flips the figure to the 2D fallback).
    /// ARFrames arrive at 60 FPS, so 130 ≈ 2.2 s. On device, `diagMaxSinceTracked` peaked
    /// at 87 on a normal desk turn under the earlier 90 window — it held, but with only
    /// ~3 frames of margin, so a slightly faster/wider turn would overflow and snap to 2D.
    /// 130 gives ~1.5× headroom over that measured peak. A head TURN makes
    /// `ARFaceAnchor.isTracked` flicker (the face is tracked *sparsely*, not lost); this
    /// bridges those gaps. Trade-off: too long and a *held* (genuinely lost) turn freezes
    /// the figure on the stale forward pose for the full window.
    private static let maxStaleFrames = 130

    // The old `portraitFixUp` remap is gone: head angles now come from the
    // GRAVITY-LEVELLED decomposition, whose reference frame is built from world-up
    // and the camera's horizontal heading — screen orientation and device tilt
    // never enter it, so there is nothing to re-base (and nothing to dial). The
    // camera-frame path it replaced mixed a level head turn into pitch/roll by
    // exactly the phone's prop angle (measured −14° pitch on a level turn).

    // MARK: - PoseProvider

    func start() async throws {
        guard Self.isFaceTrackingSupported else {
            logger.error("ARFaceTracking unsupported on this device — caller should have gated on isFaceTrackingSupported")
            throw ARFaceTrackingError.unsupported
        }

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = false

        currentConfig = config
        session.delegate = self
        session.run(config)
        Self.diagSessionStarted = true

        logger.info("ARFaceTracking session started")
        recoveryAttempts = 0
        lastGoodAngles = nil
        lastGoodOrientation = nil
        framesSinceTrackedFace = 0
        Self.diagFramesSinceTracked = 0
        Self.diagMaxSinceTracked = 0
        Self.diagHeadDistanceMeters = .nan
        startFrameTimeoutMonitoring()
    }

    func stop() {
        frameTimeoutTimer?.invalidate()
        frameTimeoutTimer = nil
        session.pause()
        logger.info("ARFaceTracking session stopped")
    }

    enum ARFaceTrackingError: Error { case unsupported }

    // MARK: - Frame-timeout recovery (mirrors ARSessionService)

    private func startFrameTimeoutMonitoring() {
        frameTimeoutTimer?.invalidate()
        frameTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFrameTimeout()
        }
    }

    private func checkFrameTimeout() {
        guard let lastFrame = lastFrameTime else {
            logger.warning("⚠️ ARFaceTracking: no frames received yet")
            return
        }
        let elapsed = Date().timeIntervalSince(lastFrame)
        if elapsed > 2.0 {
            logger.error("⛔️ ARFaceTracking frame timeout (\(String(format: "%.1f", elapsed))s) — restarting")
            attemptRecovery()
        } else if elapsed < 0.5 && recoveryAttempts > 0 {
            logger.info("✓ ARFaceTracking frames flowing — resetting recovery counter")
            recoveryAttempts = 0
        }
    }

    private func attemptRecovery() {
        guard !isRecovering, let config = currentConfig else { return }
        isRecovering = true
        recoveryAttempts += 1
        logger.warning("🔄 ARFaceTracking recovery attempt #\(self.recoveryAttempts)")
        session.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.isRecovering = false
        }
    }
}

extension ARFaceTrackingService: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrameTime = Date()
        Self.diagFramesSeen += 1

        // Extract the head pose from the first tracked face. Decomposition is pure
        // and thread-safe, so it runs here on ARKit's delegate queue; only the
        // resulting value struct leaves this scope (never the ARFrame/anchor).
        let trackedFace = frame.anchors
            .compactMap { $0 as? ARFaceAnchor }
            .first { $0.isTracked }
        if trackedFace != nil { Self.diagTrackedSeen += 1 }

        let headAngles: HeadAngles?
        // Viz-only quaternion sibling of `headAngles`, tracked in lockstep: present
        // when the angles are, nil at the same frame on dropout (a value type, so the
        // no-escape rule holds — no ARFrame/anchor leaves this scope).
        let headOrientation: simd_quatf?
        if let face = trackedFace {
            // Gravity-levelled: turn/nod/tilt about world-referenced axes, immune
            // to the phone's prop angle. Signs are flipped onto the DOCUMENTED
            // HeadAngles contract (PoseSample: yaw + = turn toward the subject's
            // RIGHT, roll + = LEFT ear lower, pitch + = chin down) so this source
            // agrees with the legacy 2D fallback at the grace-window handoff seam:
            // +turn is subject-LEFT (right-hand rule about world up) → yaw = −turn;
            // +tilt is right-ear-lower → roll = −tilt; +nod is chin-down → pitch = nod.
            let (turn, nod, tilt) = HeadOrientationDecomposition.gravityLevelledHeadAngles(
                headTransform: face.transform,
                cameraTransform: frame.camera.transform
            )
            let angles = HeadAngles(pitch: nod, yaw: -turn, roll: -tilt)
            // The SAME levelled-relative rotation as a quaternion (it re-decomposes
            // to the angles above, so HUD numbers and the figure cannot disagree).
            let q = HeadOrientationDecomposition.gravityLevelledRotationQuat(
                headTransform: face.transform,
                cameraTransform: frame.camera.transform
            )
            // Spike S1: the translation the orientation path discards — metric
            // head-to-camera distance for the HUD `dist` row (diagnostic only).
            Self.diagHeadDistanceMeters = simd_length(
                HeadOrientationDecomposition.cameraSpaceHeadPosition(
                    headTransform: face.transform,
                    cameraTransform: frame.camera.transform
                ))
            lastGoodAngles = angles
            lastGoodOrientation = q
            framesSinceTrackedFace = 0
            headAngles = angles
            headOrientation = q
        } else {
            // Dropout: hold the last good pose for a short grace window, then release.
            // Angles and orientation share the one frame counter so they hold together
            // and clear to nil together — never one present without the other.
            framesSinceTrackedFace += 1
            let withinGrace = framesSinceTrackedFace <= Self.maxStaleFrames
            headAngles = withinGrace ? lastGoodAngles : nil
            headOrientation = withinGrace ? lastGoodOrientation : nil
            if headAngles == nil {
                lastGoodAngles = nil
                lastGoodOrientation = nil
            }
        }

        // Mirror the live grace counter to the HUD and track its session peak — the
        // worst gap (in frames) between two tracked faces. Keeps counting past
        // `maxStaleFrames` so it measures the true gap regardless of the window.
        Self.diagFramesSinceTracked = framesSinceTrackedFace
        if framesSinceTrackedFace > Self.diagMaxSinceTracked {
            Self.diagMaxSinceTracked = framesSinceTrackedFace
        }

        let inputFrame = InputFrame(
            timestamp: frame.timestamp,
            pixelBuffer: frame.capturedImage,
            depthMap: nil,  // ARFaceTracking has no sceneDepth map; shoulders stay 2D, head is ARKit
            cameraIntrinsics: frame.camera.intrinsics,
            externalHeadAngles: headAngles,
            externalHeadOrientation: headOrientation
        )
        frameSubject.send(inputFrame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        logger.error("ARFaceTracking session failed: \(error.localizedDescription)")
        attemptRecovery()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        logger.info("ARFaceTracking session interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard let config = currentConfig else { return }
        logger.info("ARFaceTracking interruption ended — resuming")
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
}
