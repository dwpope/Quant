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
    /// The quaternion sibling of `lastGoodAngles`: the raw screen-frame head rotation
    /// held across the SAME grace window so the viz-only quaternion channel is present
    /// exactly when the Euler angles are (and released to `nil` at the same frame).
    /// Keeping them in lockstep keeps any downstream presence-gating consistent.
    private var lastGoodOrientation: simd_quatf?
    private var framesSinceTrackedFace = 0
    /// Grace window: how many consecutive untracked ARFrames to hold the last good
    /// head pose before releasing to nil (which flips the figure to the 2D fallback).
    /// ARFrames arrive at 60 FPS, so 90 ≈ 1.5 s. Widened from 30 (~0.5 s): a head TURN
    /// makes `ARFaceAnchor.isTracked` flicker — the face is tracked *sparsely*, not
    /// lost — and 0.5 s was too short to bridge those gaps, collapsing yaw to 2D mid-turn
    /// (the visible snap). Sized from `diagMaxSinceTracked` measured on device; raise if
    /// the peak gap on a normal turn still exceeds it. Trade-off: too long and a *held*
    /// (genuinely lost) turn freezes the figure on the stale forward pose for the window.
    private static let maxStaleFrames = 90

    /// Re-bases ARKit's landscape-referenced camera axes onto the portrait screen so
    /// a head turn reads as yaw, a nod as pitch, a tilt as roll. A +90° rotation about
    /// the camera view (Z) axis is the expected portrait remap.
    ///
    /// DEVICE-CONFIRM KNOB: the exact remap (and the three per-axis signs) can only be
    /// verified against a real head pose. If turn/nod/tilt come out swapped on device,
    /// change this rotation (e.g. -90°); if merely inverted, flip the corresponding
    /// `headYaw/Pitch/RollGain` sign in the binding (do NOT pre-invert here).
    private let portraitFixUp: simd_float3x3 = {
        let a = Float.pi / 2  // +90° about Z
        let c = cos(a), s = sin(a)
        return simd_float3x3(columns: (
            SIMD3(c, s, 0),
            SIMD3(-s, c, 0),
            SIMD3(0, 0, 1)
        ))
    }()

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
            let (yaw, pitch, roll) = HeadOrientationDecomposition.taitBryanZYXDegrees(
                headTransform: face.transform,
                cameraTransform: frame.camera.transform,
                portraitFixUp: portraitFixUp
            )
            let angles = HeadAngles(pitch: pitch, yaw: yaw, roll: roll)
            // Same orthonormalized screen-frame matrix the Euler decomposition reads,
            // carried straight through as a quaternion (no per-axis re-amplification).
            let q = HeadOrientationDecomposition.screenRotationQuat(
                headTransform: face.transform,
                cameraTransform: frame.camera.transform,
                portraitFixUp: portraitFixUp
            )
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
