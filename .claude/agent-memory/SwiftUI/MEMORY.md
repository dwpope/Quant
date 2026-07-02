# Quant SwiftUI — durable notes

## Camera / provider architecture (verified 2026-06-20)
- `PoseProvider` (PostureLogic/Sources/PostureLogic/Protocols/PoseProvider.swift): `framePublisher`, `start() async throws`, `stop()`.
- `SwitchablePoseProvider` (Quant/Services/SwitchablePoseProvider.swift) only FORWARDS frames; it does NOT own lifecycle. AppModel calls start/stop on the real services.
- `ARSessionService` = REAR `ARWorldTrackingConfiguration` (+ smoothedSceneDepth/sceneDepth). `FrontCameraSessionService` = front wide-angle AVCaptureSession (RGB only, no TrueDepth). Modes in CameraMode enum {rearDepth, front2D}.
- **Preview binds the live session directly**: `ContentView.swift:31` `CameraPreviewView(session: appModel.arService.session)` puts an `ARView(cameraMode:.ar, .cameraFeed())` on `arService.session`. So the ARView is a SECOND consumer of the ARSession. Any new front ARFaceTracking session must NOT collide with this; a `CameraMode.frontFace` needs its own preview branch (an ARView on the face session, or hide rear preview) — you cannot run a front ARFaceTrackingConfiguration while an ARView still drives `arService.session`/world tracking (single shared AVCaptureSession backing ARKit; configs are mutually exclusive, last `run()` wins).
- Mode switch ordering (AppModel.switchCameraMode): set mode -> `Task.yield()` -> previous.stop() -> detach() -> attach(new) -> new.start(). NOTE: `stop()` on ARSessionService only `session.pause()`s; the ARView still holds `.session`. Start/stop is async; rapid toggling can race.

## Head-angle pipeline (verified)iiii
- `PoseService.process(frame:)` runs body pose + `VNDetectFaceRectanglesRequestRevision3`, stamps optional `PoseObservation.faceYaw/Pitch/Roll` (degrees). These are NON-Codable.
- `PoseDepthFusion.computeHeadAngles` returns legacy 2D unless `FaceAngleTuning.useFaceAngles` (default FALSE), then per-axis `face?? legacy`. In fuse3D, LiDAR `computeHeadPitch3D` OVERRIDES pitch AFTER computeHeadAngles (line ~292) — would clobber an external face pitch in depthFusion mode.
- `PoseSample` (Codable) carries final resolved headPitch/Yaw/Roll DEGREES; feeds ONLY visualization + debug readout, NEVER PostureEngine scoring.
- Replay: `ReplayPoseProvider` sends `InputFrame(precomputedSample:)` -> Pipeline.processPrecomputed BYPASSES pose+fusion. So any new `InputFrame.externalHeadAngles` is inert during replay (correct — recordings already store resolved degrees).

## Test infra
- PostureLogic is a SwiftPM package, `swift test`, CI-gated (~498 tests reported; 35 test files). ARKit/AVFoundation/ARFaceAnchor are APP-TARGET ONLY — cannot link in the package. Pure matrix->euler decomposition MUST be a package function taking plain simd_float4x4/float3x3 (no ARKit import) to stay headlessly testable. No such decomposition exists yet (grep found none).

## Misc
- `nonisolated deinit {}` on session services is a deliberate XCTest heap-corruption workaround (Xcode 26/iOS 26) — replicate on any new NSObject provider.
- SourceKit in-editor diagnostics unreliable here; xcodebuild/swift test authoritative.
# Quant posture-viz head pipeline (frontFace TrueDepth)

Chain: ARFaceAnchor 60fps -> Pipeline throttle 10Hz (poseFrameInterval=0.1, Pipeline.swift) -> PoseSample deg -> PostureVisualizationViewModel.ingest (headRotationAmplification=1.5, per-axis LowPassFilter alpha=0.2 on yaw/pitch/roll INDEPENDENTLY at 10Hz) -> headYaw/Pitch/RollDegrees -> PostureVisualizationBinding deg->rad -> shapeHeadTilt(deadzone 2deg, scale 0.6) -> tiltTurnFadePower=2.0 cos^2(yaw) fade on pitch+roll -> gains yaw -0.6/pitch -6/roll -3 -> headOrientation compose yaw*pitch*roll (Z-up: yaw=+Z,pitch=+X,roll=+Y) -> simd_slerp(prev,target,orientationSmoothing=0.25) at 60fps.

Key analysis numbers (LowPassFilter value+=alpha*(target-value)):
- alpha=0.2 @10Hz -> tau~0.448s. Head circle @0.5Hz: gain ~0.58 (amp -42%), phase lag ~55deg PER AXIS.
- Yaw lag == pitch lag (same alpha) so circle stays ~round but SHRUNK+ROTATED; tiltTurnFadePower=2.0 (cos^2 yaw) is now MISTUNED for decoupled ARKit source and FLATTENS L/R extents -> oval/peanut, esp the vertical lobes when turned. turnTiltDecouple=0 (off), headPitchDownBoost=1 (off).
- Biggest culprit for SHAPE: tiltTurnFadePower=2.0 still active. Biggest for MOTION lag: 10Hz throttle + alpha=0.2 lowpass cascade. slerp 0.25 adds minor extra lag, mostly helps fluidity.
- Fix shape: set tiltTurnFadePower ~1.0 (or skip fade in frontFace). Fix lag: raise alpha (~0.5) or filter at 60fps / quaternion-slerp the source instead of per-euler lowpass.

## Quaternion head channel (R1, 2026-06-28)
- Parallel viz-only quat channel runs alongside Euler headPitch/Yaw/Roll, all default nil:
  `InputFrame.externalHeadOrientation: simd_quatf?`, `PoseObservation.externalHeadOrientation: simd_quatf?` (added `import simd`), `PoseSample.headOrientation: SIMD4<Float>?` (xyzw, the Codable record/replay boundary).
- `PoseSample` Codable is FULLY compiler-synthesized (no extension/CodingKeys/manual encode anywhere) → adding an optional with `nil` default is automatically backward-compatible (old JSON missing the key decodes to nil). Confirmed via test.
- `HeadOrientationDecomposition.screenRotationQuat(_:)` and `screenRotationQuat(headTransform:cameraTransform:portraitFixUp:)` return the SAME orthonormalized screen 3x3 the Euler `taitBryanZYXDegrees` decomposes, just as `simd_quatf(matrix)`. Agreement proven by re-decomposing the quat → identical yaw/pitch/roll (1e-3).
- `swift test` in PostureLogic/: 521 → 526 (+5) all green.
