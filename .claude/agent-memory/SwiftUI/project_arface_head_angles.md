# ARFaceAnchor head-angle integration (Layer 1) — design notes

Branch context: usdz-figure-pipeline. Goal: source head yaw/pitch/roll from ARKit
ARFaceTrackingConfiguration (TrueDepth, true 6-DOF, decoupled) on Face-ID devices,
REPLACING the monocular Vision/legacy head angles (Vision rev-3 pitch unreliable,
couples with yaw via the legacy 2D `??` fallback). MUST preserve shoulder-based
side-lean (comes from Vision body-pose keypoints, not the head), so ARFaceAnchor
head-only cannot replace the whole PoseSample.

## Verified pipeline facts
- `PoseSample.headPitch/headYaw/headRoll: Float DEGREES` are Codable and feed ONLY
  the visualization (PostureVisualizationViewModel reads p.headYaw/Pitch/Roll →
  headRotationAmplification → PostureVisualizationBinding euler → USDZ figure) +
  debug readout. NEVER PostureEngine scoring. (Scoring = forwardCreep/twist/
  lateralLean/headDrop/shoulderRounding.)
- `PoseObservation.faceYaw/facePitch/faceRoll: Float?` is NON-Codable, set per frame
  in PoseService from Vision rev-3 (`VNDetectFaceRectanglesRequest`).
- `computeHeadAngles(from:)` in PoseDepthFusion.swift:459: builds legacy 2D angles,
  then `guard FaceAngleTuning.useFaceAngles else { return legacy }`, then per-axis
  `pose.facePitch ?? legacy.pitch`. Default `useFaceAngles = false`.
- InputFrame (NOT Codable, has CVPixelBuffer) — safe to add an optional field.
- CameraMode enum {rearDepth, front2D}, String/Codable/CaseIterable, persisted under
  "com.quant.cameraMode". providerForMode in AppModel.swift:810. Picker tags listed
  EXPLICITLY (not allCases) in CalibrationSettingsView + SettingsSheetView, and
  ContentView switches on it for preview — so a 3rd case won't auto-explode switches.

## KEY GOTCHA (the gating trap)
The ARKit source must be authoritative-when-PRESENT REGARDLESS of `useFaceAngles`
(which defaults OFF and gates the MONOCULAR Vision fit). Do NOT funnel ARKit through
the same `pose.faceYaw/Pitch/Roll` + `useFaceAngles` path, or ARKit gets silently
gated off by default. Carry ARKit angles on a SEPARATE channel
(InputFrame.externalHeadAngles → stamped onto PoseObservation as a distinct field,
e.g. `externalHeadAngles: HeadAngles?`) and have computeHeadAngles prefer it
unconditionally before the useFaceAngles/legacy chain. The W-test suite
(test_faceAngles_* in PoseDepthFusionTests, ~line 969+) still gates on useFaceAngles
and must stay green — keep that branch untouched.

## Package boundary
ARKit/AVFoundation = APP-TARGET ONLY (cannot link in PostureLogic SwiftPM package,
498 tests, swift test, CI-gated). The matrix→euler decomposition must be a PURE
package function taking simd_float4x4 / simd_float3x3 (no ARKit import) so it is
headlessly testable, mirroring FaceAngleConversion.

## Provider template
ARSessionService.swift = rear ARWorldTrackingConfiguration template. New
ARFaceTrackingService mirrors it but ARFaceTrackingConfiguration; in
session(_:didUpdate:) pull the ARFaceAnchor from frame.anchors, decompose
anchor.transform (and/or relative to camera) → degrees, send InputFrame(
pixelBuffer: frame.capturedImage [Vision shoulders→lean], cameraIntrinsics,
externalHeadAngles: ...). Replicate `nonisolated deinit {}` (XCTest heap-corruption
workaround). ARFace gives NO sceneDepth depthMap → depthMap nil → DepthMode.twoDOnly.

## Head-angle SMOOTHING/SHAPE pipeline (commit 86d6a89, .frontFace) — circle fidelity
Full path: ARFaceAnchor.transform → HeadOrientationDecomposition.taitBryanZYXDegrees
(ZYX Tait-Bryan, all-atan2, inverse(cam)*head, Gram-Schmidt, portraitFixUp +90°Z,
singularity branch only at cos(pitch)<1e-6 i.e. ±90°) → HeadAngles deg →
Pipeline throttle poseFrameInterval=0.1 (10 Hz source) → PoseSample deg → VM.ingest
(Quant/ViewModels/PostureVisualizationViewModel.swift ~261-340): ×headRotationAmplification
1.5, pitch/roll rest-relative subtract, per-axis clamp (yaw90/pitch60/roll45), then
PER-AXIS LowPassFilter (first-order EWMA value+=α(target-value), α=smoothingAlpha=0.2)
yawFilter/pitchFilter/rollFilter (lines 165-167) → head*Degrees →
Binding.resolve→euler radians, mirror() flips yaw/roll sign →
head block (PostureVisualizationBinding.swift ~552-595): deadzone shapeHeadTilt
(headTiltDeadzoneRadians 2°, headTiltScale 0.6), tiltTurnFadePower=2.0 cos(yaw)^2 fade
on pitch&roll (STILL ON; for decoupled ARKit src there's no phantom to cancel so it
only FLATTENS a real circle's L/R extents → oval), turnTiltDecouple=0.0 (off),
gains headYawGain -0.6 / headPitchGain -6 / headRollGain -3, headPitchDownBoost 1.0,
headOrientation(euler) Z-up quat yaw=+Z pitch=+X roll=+Y, then RECURSIVE
simd_slerp(prevOut,target,orientationSmoothing=0.25) per ~60fps render frame
(smoothed(), RuntimeCache.smoothedHead).

### Circle verdict (NUMERICALLY VERIFIED 2026-06-20, np sim of full chain)
- MOTION smoothness: GOOD. Two stages: per-axis α=0.2 EWMA (10Hz) + quaternion slerp
  0.25 (60fps, interpolates 10→60 along geodesic). Slerp dominant felt smoother, suits
  circular motion. Both add lag, no jitter/snap. ARFaceAnchor source sub-degree smooth.
- DECOMPOSITION ITSELF IS CLEAN (not the distorter): matrix→ZYX-euler→matrix round-trip
  error = 0.0000° at ±15/30/60° (exact away from gimbal). cos(pitch) stays 0.97@±15°,
  0.87@±30°, 0.50@±60° — conditioning healthy; realistic head-circle (±15-30° pitch) is
  nowhere near the ±90° singularity branch. A constant-angular-velocity physical CONE
  gives near-even euler rate: speed max/min 1.07@±20°, 1.17@±30°, only 1.47@±45° (mild
  speed unevenness emerges past ~45°, not at realistic amplitude).
- PER-AXIS LOW-PASS DOES NOT OVAL A SYMMETRIC CIRCLE (correction to earlier note):
  yaw & pitch share the SAME α=0.2 at the SAME orbit frequency → IDENTICAL lag &
  attenuation → circle stays ROUND, just shrinks (~58% radius retained @10Hz/2s orbit)
  and rotates (phase lag). Per-axis EWMA only skews into an ellipse if the two axes
  carry DIFFERENT frequency content — which the gimbal-rate nonlinearity injects only
  at LARGE amplitude (>~45°). At ±15-30° the low-pass cost is round-shrink + lag, not oval.
- DOMINANT SHAPE KILLER = tiltTurnFadePower=2.0 (cos(yaw)^2 fade on pitch&roll), and it
  is STRONGLY PHASE-DEPENDENT: for a 90°-out-of-phase circle (pitch peaks where yaw≈0,
  dodging the fade) ovaling is mild ~6.5% radius var; for an IN-PHASE / diagonal sweep
  it is catastrophic ~150% radius var (circle → bent banana/arc). Real head circles are
  rarely perfectly 90° out of phase → fade is a real, phase-dependent oval risk. For the
  DECOUPLED ARKit source there is NO phantom to cancel, so the fade ONLY flattens a real
  circle. FIX: drop tiltTurnFadePower toward 1.0 (→3.4% var) or 0.0 (→0%) for .frontFace
  (noted in code comments, NOT YET done).
- Net: MOTION smooth yes; SHAPE = round only if you trace a clean 90°-out-of-phase
  circle, otherwise ovals/flattens — and the single highest-leverage fix is dropping
  tiltTurnFadePower for the face path, NOT touching the (already-faithful) decomposition.
