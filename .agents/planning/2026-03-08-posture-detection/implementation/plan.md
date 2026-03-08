# Implementation Plan — Posture Detection App

## Checklist

### Phase 1 — MVP: Camera → Watch Tap
- [x] Step 1: Logic Package & Test Harness
- [x] Step 2: ARKit Integration Spike
- [x] Step 3: Supported Range Documentation
- [x] Step 4: ARSession Lifecycle Hardening
- [x] Step 5: Depth Service & Confidence
- [x] Step 6: Mode Switcher (DepthFusion ↔ TwoDOnly)
- [x] Step 7: Debug Overlay v1
- [x] Step 8: Vision Pose Detection (Throttled)
- [x] Step 9: PoseSample Builder (2D-First)
- [x] Step 10: MetricsEngine Implementation
- [x] Step 11: Metrics Smoothing
- [x] Step 12: Calibration Flow
- [x] Step 13: PostureEngine State Machine
- [x] Step 14: NudgeEngine Implementation
- [x] Step 15: Audio Feedback
- [x] Step 16: Acknowledgement Detection
- [x] Step 17: Apple Watch Connectivity

### Post-MVP Completeness
- [x] Step 18: headDrop & shoulderRounding in PostureEngine
- [x] Step 19: Specific NudgeReasons

### Front Camera Support
- [x] Step 20: Camera Mode & Switchable Provider Scaffolding
- [x] Step 21: Front Camera Provider
- [x] Step 22: AppModel Runtime Switching & Persistence
- [x] Step 23: Front Camera UI Controls
- [x] Step 24: Front Camera Permission/Error UX
- [x] Step 25: Front Camera Tests & Regression

### Debug Improvements
- [x] Step 26: Expose latestMetrics in AppModel
- [x] Step 27: Dual-Column Calibrated Metrics Debug Display

### Twist Fix
- [x] Step 28: Twist Measurement Fix (Orientation + Baseline)

### Phase 2 — Enhancement
- [ ] Step 29: 3D Position Calculation
- [ ] Step 30: Depth Fusion in PoseSample Builder
- [ ] Step 31: RecorderService (Timestamped Samples)
- [ ] Step 32: Tagging During Record
- [ ] Step 33: ReplayService (Simulator-Friendly)
- [ ] Step 34: Golden Recordings
- [ ] Step 35: Recording & Replay Pipeline Integration
- [ ] Step 36: TaskModeEngine Implementation
- [ ] Step 37: Task-Adjusted Thresholds
- [ ] Step 38: Thresholds Settings Screen
- [ ] Step 39: TaskModeEngine Pipeline Integration
- [ ] Step 40: Setup Validation
- [ ] Step 41: Stale Baseline Detection

### Phase 3 — Hardening
- [ ] Step 42: Long-Run Stability Harness (90 min)
- [ ] Step 43: Thermal Throttling Strategy
- [ ] Step 44: Background Mode Investigation
- [ ] Step 45: Mac Companion App

---

## Phase 1 — MVP: Camera → Watch Tap

> **Goal**: Deliver the core value loop — detect bad posture from camera, nudge via Apple Watch — as fast as possible. 2D-only; no depth fusion, recording, or task classification needed yet.

---

### Step 1: Logic Package & Test Harness

**Objective**: Create the `PostureLogic` Swift Package with a `MockPoseProvider` so all posture logic can be unit-tested without a device.

**Implementation Guidance**:
- Create `PostureLogic/Package.swift` targeting iOS 17+ / macOS 14+
- Define the `PoseProvider` protocol with `framePublisher` and `start()/stop()`
- Implement `MockPoseProvider` using `PassthroughSubject` with `emit(frame:)` and `emit(scenario:)` test helpers
- Create stub `Pipeline` class that accepts a `PoseProvider`

**Test Requirements**:
- `test_mockFrameFlowsThroughPipeline`: Mock frame → Pipeline → output is non-nil
- `swift test` passes with 0 failures

**Integration**: Foundation layer — all subsequent steps build on this package.

**Demo**: `swift test` passes. Package builds for iOS in Xcode. MockPoseProvider emits frames that reach the Pipeline.

---

### Step 2: ARKit Integration Spike

**Objective**: Connect ARKit to the `PoseProvider` protocol so live camera frames reach the Pipeline.

**Implementation Guidance**:
- Create `Quant/Services/ARSessionService.swift` conforming to `PoseProvider`
- Use `ARBodyTrackingConfiguration` with `.bodyDetection` frame semantics
- Convert `ARFrame` to `InputFrame` in `session(_:didUpdate:)` delegate
- Wire into the app's entry point

**Test Requirements**:
- Manual: camera frames reach pipeline, console logs frame timestamps
- Manual: app runs on device without crash

**Integration**: Builds on Step 1 (PoseProvider protocol). ARSessionService is the production input source.

**Demo**: App runs on device. Camera opens. Console logs a steady stream of increasing frame timestamps.

---

### Step 3: Supported Range Documentation

**Objective**: Document the expected operating conditions (distance, angle, lighting, position).

**Implementation Guidance**:
- Create `SUPPORTED_RANGE.md` with distance (0.5m–1.5m), angle (±15° horizontal, 0°–30° vertical), lighting, and position constraints
- Based on manual testing observations from Step 2

**Test Requirements**:
- Manual: file exists with specific numeric ranges for all sections

**Integration**: Reference document used by setup validation (Step 40) and calibration.

**Demo**: `SUPPORTED_RANGE.md` committed to repo with all sections populated.

---

### Step 4: ARSession Lifecycle Hardening

**Objective**: Make `ARSessionService` survive interruptions (phone calls, backgrounding, camera dialogs).

**Implementation Guidance**:
- Implement `sessionWasInterrupted`, `sessionInterruptionEnded`, `session(_:didFailWithError:)` delegates
- Pause posture detection on interruption, resume with fresh configuration on return
- Handle camera permission denial gracefully

**Test Requirements**:
- Manual: app survives lock/unlock, app switching, camera permission changes without crashing

**Integration**: Builds on Step 2. Makes the input source production-ready.

**Demo**: App running → lock phone → unlock → session resumes. Switch apps and return → no crash. Camera permission revoked → graceful error state.

---

### Step 5: Depth Service & Confidence

**Objective**: Sample depth at keypoint locations and compute overall depth confidence for mode switching.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Services/DepthService.swift`
- Implement `sampleDepth(at:from:)` with `CVPixelBuffer` locking and coordinate scaling
- Implement `computeConfidence(from:)` that returns `.unavailable` when no depth map, analyzes quality otherwise
- Remember: depth map resolution differs from RGB — scale coordinates

**Test Requirements**:
- `test_depthConfidence_returnsUnavailable_whenNoDepthMap`
- Manual: on LiDAR device, confidence is not `.unavailable`; covering LiDAR sensor drops confidence

**Integration**: Builds on Step 4 (InputFrame has depthMap). Feeds Step 6 (mode switching).

**Demo**: Unit test passes. On LiDAR device, depth confidence shows non-unavailable values. Covering sensor → confidence drops.

---

### Step 6: Mode Switcher (DepthFusion ↔ TwoDOnly)

**Objective**: Automatically switch between depth and 2D modes based on depth confidence, with hysteresis to prevent flapping.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Services/ModeSwitcher.swift`
- Drop to `twoDOnly` immediately when confidence < medium
- Require `depthRecoveryDelay` seconds of good confidence before returning to `depthFusion`
- Use configurable threshold from `PostureThresholds`

**Test Requirements**:
- `test_switchesToTwoDOnly_whenConfidenceDrops`
- `test_waitsForRecoveryDelay_beforeSwitchingBack`
- `test_resetsRecoveryTimer_ifConfidenceDropsAgain`

**Integration**: Uses DepthService output (Step 5). Mode value consumed by PoseDepthFusion (Step 9) and Pipeline.

**Demo**: On device, mode switches visible in logs. Covering LiDAR → immediate switch to twoDOnly. Good depth sustained for `depthRecoveryDelay` → back to depthFusion.

---

### Step 7: Debug Overlay v1

**Objective**: Show live state from all `DebugDumpable` components so developers can observe the system in real-time.

**Implementation Guidance**:
- Create `Quant/Views/DebugOverlayView.swift` as a SwiftUI overlay
- Display: current mode, depth confidence, tracking quality, FPS
- Later expanded to include posture state, nudge decision, audio/watch status, full pose readout
- Use monospaced caption font with ultraThinMaterial background

**Test Requirements**:
- Manual: overlay visible on device, values update live, numbers don't freeze
- Manual: survives rotation and app lifecycle

**Integration**: Reads from `AppModel` published properties. Displays output of Steps 5–6.

**Demo**: Debug overlay visible on screen showing mode, depth, tracking, FPS — all updating in real-time as you move.

---

### Step 8: Vision Pose Detection (Throttled)

**Objective**: Extract body keypoints from camera frames using Vision framework, throttled to ~10 FPS.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Services/PoseService.swift`
- Use `VNDetectHumanBodyPoseRequest` on `InputFrame.pixelBuffer`
- Throttle: skip frames if < 0.1s since last process
- Map `VNRecognizedPoint` to `Keypoint` for each `Joint`
- Remember: flip Y coordinates (`1.0 - point.y`)

**Test Requirements**:
- `test_throttling_skipsFramesWithinInterval`
- `test_returnsNil_whenNoPixelBuffer`
- Manual: keypoints produced at ~10 FPS, no crash when no person in frame

**Integration**: Builds on Pipeline (Step 1). Output feeds PoseDepthFusion (Step 9).

**Demo**: App running with person in frame → debug overlay shows keypoint count updating at ~10 FPS. Empty scene → graceful nil handling.

---

### Step 9: PoseSample Builder (2D-First)

**Objective**: Build `PoseSample` from 2D keypoints using normalized coordinates, with head position fallback chain.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Services/PoseDepthFusion.swift`
- Build PoseSample from 2D keypoints with z=0
- Head position fallback chain: nose → eye midpoint → single eye → ear midpoint
- Compute derived angles (torsoAngle, headForwardOffset, shoulderTwist) from 2D geometry
- Use shoulder width as scale reference
- Return nil on missing critical keypoints
- Accept `trackingQuality` parameter

**Test Requirements**:
- `test_builds2DSample_withGoodKeypoints`
- `test_returnsNil_onMissingCriticalKeypoints`
- `test_headPositionFallback_usesEyeMidpoint`
- Manual: PoseSample produced in twoDOnly mode, angles change when you move

**Integration**: Uses PoseService output (Step 8) and DepthService output (Step 5). Feeds MetricsEngine (Step 10).

**Demo**: Pipeline produces PoseSample with depthMode `.twoDOnly`. Debug overlay shows non-zero positions. Leaning forward → torsoAngle changes visibly.

---

### Step 10: MetricsEngine Implementation

**Objective**: Compute all five `RawMetrics` as deltas from baseline, using shoulder width as scale reference in 2D mode.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Engines/MetricsEngine.swift`
- Compute: forwardCreep, headDrop, shoulderRounding, lateralLean, twist
- All metrics are deltas from baseline (positive = worse)
- Without baseline: return zeros (can't compute deltas)
- Forward creep in 2D: use `shoulderWidthRaw` delta as distance proxy
- Twist: `abs(sample.shoulderTwist - baseline.shoulderTwist)`

**Test Requirements**:
- `test_returnsZeros_withNoBaseline`
- `test_forwardCreep_increasesWhenCloser`
- `test_headDrop_increasesWhenHeadLower`
- `test_twist_baselineSubtracted`
- `test_twist_atBaseline_isZero`
- Verify against input/output examples in design doc

**Integration**: Uses PoseSample (Step 9) and Baseline (Step 12). Feeds Smoother (Step 11) and PostureEngine (Step 13).

**Demo**: After calibration, metrics near 0. Slouch forward → forwardCreep increases. Drop head → headDrop increases. Return upright → metrics return to ~0.

---

### Step 11: Metrics Smoothing

**Objective**: Apply exponential moving average to reduce jitter without hiding real posture changes.

**Implementation Guidance**:
- Create `MetricsSmoother` struct with configurable alpha (default 0.3)
- Lerp each metric field: `smoothed = prev * (1-alpha) + current * alpha`
- Also compute `movementLevel`: frame-to-frame velocity of shoulders+head, normalized 0–1
- Also compute `headMovementPattern` classification: sliding window of recent head positions → `.still`, `.smallOscillations`, `.largeMovements`, `.erratic`

**Test Requirements**:
- `test_smoothing_reducesJitter`
- `test_smoothing_followsRealChanges`
- `test_movementLevel_increasesDuringMotion`

**Integration**: Takes raw MetricsEngine output (Step 10). Feeds PostureEngine (Step 13) and TaskModeEngine (Step 36).

**Demo**: Side-by-side raw vs smoothed metrics — smoothed values less noisy. Clear posture change → smoothed values follow within reasonable delay.

---

### Step 12: Calibration Flow

**Objective**: Implement guided calibration with countdown, sampling, variance validation, and median baseline computation.

**Implementation Guidance**:
- Create `CalibrationEngine` with configurable `CalibrationConfig` (sample count, variance thresholds)
- 3-second countdown before sampling begins
- Collect PoseSample frames for 5 seconds, require ≥30 good frames
- SIMD-based positional and angular variance validation
- Median aggregation for baseline computation
- Baseline includes `shoulderTwist` for delta computation
- Create `Quant/Views/CalibrationView.swift` with countdown UI, progress bar, status messages
- Persist baseline (including clear on recalibrate)

**Test Requirements**:
- `test_calibration_rejectsHighVariance`
- `test_calibration_requiresMinSamples`
- `test_calibration_computesMedianBaseline`
- `test_recalibrate_clearsPersistedBaseline_soRelaunchRequiresCalibration`
- Manual: hold still → success. Move during calibration → rejection with reason.

**Integration**: Uses PoseSample stream (Step 9). Produces Baseline consumed by MetricsEngine (Step 10).

**Demo**: App shows "Sit up straight" → 3-second countdown → "Hold still..." → progress bar fills → "Calibration complete!" (or "Failed: too much movement").

---

### Step 13: PostureEngine State Machine

**Objective**: Implement posture state transitions (absent → calibrating → good ↔ drifting ↔ bad) with timer management.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Engines/PostureEngine.swift`
- State machine: good → drifting (any metric exceeds threshold) → bad (after `driftingToBadThreshold` seconds)
- Recovery: bad → drifting → good when all metrics below thresholds
- **Never change state when tracking quality is low** — just pause timers
- `checkPostureBad()`: check all five metrics against thresholds with task mode multipliers
- Stretching mode: always return false (disabled)

**Test Requirements**:
- `test_transitionsToGood_afterCalibration`
- `test_transitionsToDrifting_whenPostureBad`
- `test_transitionsToBad_afterDriftingTimeout`
- `test_recoversToGood_whenPostureImproves`
- `test_pausesTimer_whenTrackingQualityLow`

**Integration**: Uses smoothed metrics (Step 11) and baseline (Step 12). Feeds NudgeEngine (Step 14).

**Demo**: Debug overlay shows posture state. Sit upright → "Good". Slouch → "Drifting(since: ...)" → "Bad(since: ...)". Sit up → back to "Good".

---

### Step 14: NudgeEngine Implementation

**Objective**: Decide when to fire nudges based on posture state, cooldown, hourly limits, and suppression rules.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Engines/NudgeEngine.swift`
- Check suppression conditions first: low tracking quality, stretching, cooldown active, max nudges reached
- Fire when `.bad(since:)` duration ≥ `slouchDurationBeforeNudge`
- Return `.pending` with time remaining when approaching threshold
- Track nudge count per hour with rolling window
- `recordNudgeFired()` and `recordAcknowledgement()` for state management

**Test Requirements**:
- `test_firesAfterSustainedSlouch`
- `test_respectsCooldown`
- `test_respectsMaxPerHour`
- `test_suppressedDuringStretching`
- `test_suppressedWhenTrackingLow`

**Integration**: Uses PostureState (Step 13) and TaskMode. Output triggers audio (Step 15) and Watch (Step 17).

**Demo**: Slouch for 5+ minutes → NudgeDecision changes from `.pending` to `.fire`. After nudge, cooldown active for 10 minutes.

---

### Step 15: Audio Feedback

**Objective**: Play a subtle audio cue when a nudge fires, respecting system volume and mute switch.

**Implementation Guidance**:
- Programmatic 880Hz sine wave generation (no external audio files)
- In-memory WAV with fade-in (10%) / fade-out (30%) envelope
- `.ambient` audio session category
- 0.5s minimum play interval guard
- Configurable volume (default 0.3) and enable/disable toggle

**Test Requirements**:
- Manual: nudge triggers → audio plays once
- Manual: silent mode → respects mute switch
- Manual: rapid nudges don't spam audio (cooldown guard)

**Integration**: Triggered by NudgeEngine `.fire` decision (Step 14).

**Demo**: Force a nudge (lower thresholds for testing) → hear a pleasant, non-jarring tone. Mute phone → tone silenced.

---

### Step 16: Acknowledgement Detection

**Objective**: Detect when the user corrects their posture after a nudge and record the acknowledgement.

**Implementation Guidance**:
- After nudge fires, monitor posture state transitions
- If state returns to `.good` within `acknowledgementWindow` (30s), call `recordAcknowledgement()`
- This resets nudge state and starts cooldown

**Test Requirements**:
- `test_acknowledges_whenPostureCorrectWithinWindow`
- `test_noAcknowledgement_whenCorrectionTooLate`

**Integration**: Bridges PostureEngine state changes (Step 13) with NudgeEngine acknowledgement (Step 14).

**Demo**: Nudge fires → correct posture within 30s → debug shows acknowledgement recorded, cooldown starts.

---

### Step 17: Apple Watch Connectivity

**Objective**: Send nudge events to Apple Watch for haptic feedback within 2 seconds.

**Implementation Guidance**:
- iPhone: `WCSession` with dual-channel delivery — `sendMessage` for real-time, `transferUserInfo` as fallback
- Watch: full `WatchSessionDelegate` with haptic playback and connection state tracking
- Watch UI: simple `ContentView` showing connection status and last nudge time
- Debug state: isPaired, isReachable, totalSent, lastSentTime
- Fix: `stopMonitoring()` must preserve lifetime subscriptions

**Test Requirements**:
- `test_stopMonitoring_preservesWatchSettingsSubscription`
- Manual: nudge on phone → haptic on Watch within ~2 seconds
- Manual: phone screen off → connectivity still works

**Integration**: Triggered by NudgeEngine `.fire` decision (Step 14). Completes the MVP value loop.

**Demo**: Phone detects sustained slouch → audio tone plays → Watch buzzes. Full end-to-end: camera → keypoints → metrics → state → nudge → watch tap.

---

### ═══ MVP MILESTONE COMPLETE ═══

---

### Step 18: headDrop & shoulderRounding in PostureEngine

**Objective**: Add `headDrop` and `shoulderRounding` to posture judgement so all five computed metrics contribute to state transitions.

**Implementation Guidance**:
- Add `headDropThreshold` and `shoulderRoundingThreshold` to `PostureThresholds`
- Update `checkPostureBad()` to include `headDrop > headDropThreshold` and `shoulderRounding > shoulderRoundingThreshold`
- headDrop: no task-mode adjustment
- shoulderRounding: uses same multiplier as forwardCreep

**Test Requirements**:
- `test_transitionsToDrifting_whenHeadDropExceedsThreshold`
- `test_transitionsToDrifting_whenShoulderRoundingExceedsThreshold`
- `test_headDrop_notAffectedByTaskMode`
- `test_shoulderRounding_relaxedInReadingMode`
- All existing PostureEngine tests still pass (no regressions)

**Integration**: Extends PostureEngine (Step 13). Uses existing thresholds infrastructure.

**Demo**: Drop head forward without leaning → state transitions to drifting → bad. Round shoulders without moving closer → same transition.

---

### Step 19: Specific NudgeReasons

**Objective**: Make `NudgeEngine` return the specific dominant metric violation as the nudge reason instead of always `.sustainedSlouch`.

**Implementation Guidance**:
- Extend `NudgeEngine.evaluate()` to accept `RawMetrics`
- When nudge fires, compare each metric's `value / threshold` ratio
- Highest ratio determines reason: `.forwardCreep`, `.headDrop`, or `.sustainedSlouch` (default)

**Test Requirements**:
- `test_nudgeReason_forwardCreep_whenDominant`
- `test_nudgeReason_headDrop_whenDominant`
- Existing NudgeEngine tests still pass

**Integration**: Extends NudgeEngine (Step 14). Uses RawMetrics from pipeline.

**Demo**: Lean forward → nudge reason is `.forwardCreep`. Drop head → nudge reason is `.headDrop`. Both → dominant metric wins.

---

### Step 20: Camera Mode & Switchable Provider Scaffolding

**Objective**: Add `CameraMode` enum and `SwitchablePoseProvider` so Pipeline can be initialized once and input sources swapped at runtime.

**Implementation Guidance**:
- Create `Quant/Models/CameraMode.swift` with `.rearDepth` and `.front2D`
- Create `Quant/Services/SwitchablePoseProvider.swift` conforming to `PoseProvider`
- `attach(source:)` subscribes to the source's `framePublisher` and forwards frames
- `detach()` cancels the subscription
- Update `AppModel` to initialize `Pipeline(provider: switchableProvider)` and attach `arService` as default

**Test Requirements**:
- `test_forwardsFramesFromAttachedSource`
- `test_detachStopsForwarding`
- `test_reattachSwitchesSource`
- App builds and runs identically to before (rear mode default)

**Integration**: Wraps existing ARSessionService. Pipeline unchanged. Enables Steps 21–25.

**Demo**: App runs exactly as before — rear mode, ARKit frames flow through SwitchablePoseProvider to Pipeline. No behavior change.

---

### Step 21: Front Camera Provider

**Objective**: Implement `FrontCameraSessionService` using AVFoundation to capture from the front-facing camera.

**Implementation Guidance**:
- Create `Quant/Services/FrontCameraSessionService.swift` conforming to `PoseProvider`
- Use `AVCaptureSession` with `builtInWideAngleCamera` front camera
- **Critical**: Set `connection.videoOrientation = .portrait` on capture connection
- Run `startRunning()`/`stopRunning()` on dedicated serial queue (NOT main actor)
- Handle permission states: authorized, notDetermined, denied, restricted
- Emit `InputFrame` with `depthMap: nil`, `cameraIntrinsics: nil`

**Test Requirements**:
- Manual: front camera captures frames, Vision detects keypoints
- Manual: no crash on permission denial

**Integration**: New PoseProvider source for SwitchablePoseProvider (Step 20).

**Demo**: Switch to front camera → frames captured → Vision detects body pose → Pipeline processes normally in twoDOnly mode.

---

### Step 22: AppModel Runtime Switching & Persistence

**Objective**: Add runtime camera mode switching with UserDefaults persistence.

**Implementation Guidance**:
- Add `@Published var cameraMode: CameraMode` to AppModel (persisted)
- Implement `switchCameraMode(to:)`: stop current source → detach → attach new source → start → persist → update published property
- `startMonitoring()` uses persisted mode
- No duplicate subscriptions on switch

**Test Requirements**:
- `test_defaultCameraMode_isRearDepth`
- `test_cameraModePersistedInUserDefaults`
- `test_switchingModeUpdatesActiveProvider`

**Integration**: Uses SwitchablePoseProvider (Step 20) and FrontCameraSessionService (Step 21).

**Demo**: Switch modes programmatically → Pipeline receives frames from new source. Kill and relaunch → mode persists.

---

### Step 23: Front Camera UI Controls

**Objective**: Add camera mode picker to settings and adapt content view for front camera mode.

**Implementation Guidance**:
- Add camera mode picker section in `CalibrationSettingsView`
- Rear mode: keep existing `CameraPreviewView`
- Front mode: show front camera preview in background (user can see themselves while interacting)
- Optionally show current camera mode in debug overlay

**Test Requirements**:
- Manual: can switch modes from settings UI
- Manual: front mode shows camera preview, user can view/use screen simultaneously

**Integration**: Uses AppModel switching (Step 22). UI layer only.

**Demo**: Settings → Camera Mode picker → select "Front 2D" → camera preview switches → posture tracking continues from front camera.

---

### Step 24: Front Camera Permission/Error UX

**Objective**: Handle front camera permission denied/restricted with clear user-facing UI and recovery instructions.

**Implementation Guidance**:
- Monitor `FrontCameraSessionService.permissionStatus`
- Show actionable message when denied ("Camera permission required. Open Settings to grant access.")
- Include deep link to app Settings
- Rear mode remains functional regardless of front permission state
- No crash or freeze on missing permission

**Test Requirements**:
- Manual: deny camera permission → clear message shown, no crash
- Manual: rear mode still works when front permission denied

**Integration**: Extends FrontCameraSessionService (Step 21) and UI (Step 23).

**Demo**: Deny camera permission → informative error with Settings link. Grant permission → front camera starts immediately.

---

### Step 25: Front Camera Tests & Regression

**Objective**: Add tests for the full front camera feature and verify no regressions.

**Implementation Guidance**:
- Test `SwitchablePoseProvider` forwarding, detach, reattach
- Test camera mode UserDefaults persistence
- Test AppModel switching updates active provider
- Run all existing PostureLogic tests — must pass unchanged

**Test Requirements**:
- All tests from Steps 20–24 consolidated and passing
- `swift test --package-path PostureLogic` — zero failures
- `xcodebuild test` with QuantNoWatchTests — zero failures

**Integration**: Validates all front camera steps (20–24) together.

**Demo**: Full test suite green. Rear camera path unchanged. Front camera path works end-to-end.

---

### Step 26: Expose latestMetrics in AppModel

**Objective**: Subscribe AppModel to `Pipeline.latestMetrics` so calibrated delta metrics are available to the UI.

**Implementation Guidance**:
- Add `@Published var latestMetrics: RawMetrics?` to AppModel
- Subscribe: `pipeline.$latestMetrics.assign(to: &$latestMetrics)`
- Value is nil before calibration, populated after

**Test Requirements**:
- Manual: nil before calibration, populated with ~0 values after, increases when slouching

**Integration**: Exposes Pipeline output (Step 10) to UI layer. Enables Step 27.

**Demo**: Set breakpoint → nil before calibration. After calibration → metrics populated near 0. Slouch → forwardCreep increases.

---

### Step 27: Dual-Column Calibrated Metrics Debug Display

**Objective**: Show raw (absolute) PoseSample values alongside calibrated (delta-from-baseline) RawMetrics with color-coded threshold proximity.

**Implementation Guidance**:
- Update `DebugOverlayView` with dual-column layout: "Raw" and "Cal" columns
- Raw: absolute PoseSample values (head Y, shoulder width, torso angle, etc.)
- Cal: delta-from-baseline values (+0.000 format) with sign prefix
- Color coding: green (<50% threshold), yellow (50–99%), red (≥100%)
- Show "--" in Cal column before calibration
- Helper functions: `metricValue()` for formatting, `metricColor()` for threshold-based coloring

**Test Requirements**:
- Manual: Cal shows "--" before calibration
- Manual: Cal shows ~"+0.000" (green) after calibration
- Manual: Lean forward → Fwd Crp turns yellow then red
- Manual: Return upright → all green again
- Raw column unchanged throughout

**Integration**: Uses AppModel.latestSample (existing) and latestMetrics (Step 26).

**Demo**: Debug overlay with two columns. Calibrate → all green zeros. Slouch → metrics drift yellow/red. Correct → back to green. Raw column always shows absolute values.

---

### Step 28: Twist Measurement Fix (Orientation + Baseline)

**Objective**: Fix two bugs that made twist read ~87° when shoulders were level, making posture unusable with front camera.

**Implementation Guidance**:
- **Front camera orientation**: Set `connection.videoOrientation = .portrait` in `FrontCameraSessionService` so Vision receives portrait-oriented frames
- **Baseline shoulder twist**: Add `shoulderTwist: Float` to `Baseline` (default 0 for backward compat)
- **Calibration capture**: Average `shoulderTwist` from samples in `CalibrationEngine.buildBaseline()`
- **Baseline subtraction**: Change MetricsEngine from `abs(sample.shoulderTwist)` to `abs(sample.shoulderTwist - baseline.shoulderTwist)`
- **Tests**: Update `makeBaseline()` helper to accept `shoulderTwist` parameter

**Test Requirements**:
- `test_twist_baselineSubtracted`
- `test_twist_atBaseline_isZero`
- All existing tests pass with updated Baseline signatures
- Manual: twist Cal column shows ~0° after calibration (was ~87°)
- Manual: posture state shows "Good" when sitting upright (was stuck on "Drifting")

**Integration**: Fixes MetricsEngine (Step 10), CalibrationEngine (Step 12), FrontCameraSessionService (Step 21).

**Demo**: Front camera → calibrate → twist shows ~0° (not ~87°). Posture state is "Good" when sitting upright.

---

## Phase 2 — Enhancement

> **Goal**: Add depth fusion for better accuracy, recording/replay for regression testing, task mode classification, and settings UI.

---

### Step 29: 3D Position Calculation

**Objective**: Convert 2D keypoints + depth to 3D world coordinates in meters using camera intrinsics.

**Implementation Guidance**:
- Implement `unproject(point:depth:intrinsics:)` function
- Use camera intrinsics: `fx = intrinsics[0,0]`, `cx = intrinsics[2,0]`, etc.
- Formula: `x = (px - cx) * depth / fx`, `y = (py - cy) * depth / fy`, `z = depth`
- Watch for column-major ordering in `simd_float3x3`

**Test Requirements**:
- `test_unproject_withKnownValues_producesCorrectPosition`
- Manual: log unprojected points on device, verify Z changes with distance

**Integration**: Used by PoseDepthFusion (Step 30). Standalone utility function.

**Demo**: Unit test passes. On device, unprojected points have sensible X/Y/Z values. Moving closer → Z decreases.

---

### Step 30: Depth Fusion in PoseSample Builder

**Objective**: Enhance `PoseDepthFusion` to use 3D positions when depth is available, falling back to 2D when not.

**Implementation Guidance**:
- When `confidence >= .medium`: use `unproject()` to convert keypoints + depth to 3D world coords
- When `confidence < .medium`: use existing 2D path from Step 9
- Compute derived angles using 3D geometry when available
- Ignore depth values within 5% of frame edges (unreliable)

**Test Requirements**:
- `test_uses3DPositions_whenDepthAvailable`
- `test_fallsBackTo2D_whenDepthUnavailable`
- All existing 2D tests still pass (no regressions)
- Manual: 3D mode less jittery than 2D

**Integration**: Extends PoseDepthFusion (Step 9) with 3D path using unprojection (Step 29).

**Demo**: LiDAR device → PoseSample has `depthFusion` mode with real Z values. Non-LiDAR → 2D path unchanged. 3D metrics visibly more stable.

---

### Step 31: RecorderService (Timestamped Samples)

**Objective**: Record stream of `PoseSample` to memory and export to JSON for regression testing.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Services/RecorderService.swift`
- `startRecording()` / `stopRecording()` lifecycle
- `record(sample:)` appends to in-memory array
- `stopRecording()` returns `RecordedSession` with all samples, tags, metadata
- JSON export target: <5MB for 5 minutes at 10 FPS

**Test Requirements**:
- `test_recordsSamples_whenRecording`
- `test_ignoresSamples_whenNotRecording`
- `test_stopsAndReturnsSession`
- Manual: record 1–2 minutes, export JSON, verify file size

**Integration**: Subscribes to Pipeline sample output. Foundation for Steps 32–35.

**Demo**: Start recording → 1 minute → stop → RecordedSession with >0 samples → JSON file saved.

---

### Step 32: Tagging During Record

**Objective**: Add manual button tags and voice recognition tags during recording sessions.

**Implementation Guidance**:
- `addTag(_ tag: Tag)` on RecorderService
- Button-based manual tagging (good posture, slouching, reading, typing, etc.)
- Voice tagging via `SFSpeechRecognizer`: continuous listening for "Mark good", "Mark slouch", etc.
- Tags stored with timestamp and source (manual vs voice vs automatic)

**Test Requirements**:
- `test_addTag_storesWithTimestamp`
- Manual: tap tag button → tag count increases
- Manual: say "Mark slouch" → voice tag added

**Integration**: Extends RecorderService (Step 31). Tags used in golden recordings (Step 34).

**Demo**: While recording, tap "Slouch" button → tag added. Say "Mark good" → voice tag added. Stop → exported JSON contains tag entries.

---

### Step 33: ReplayService (Simulator-Friendly)

**Objective**: Play back recorded sessions as if live, with adjustable speed, for Simulator-based testing.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Services/ReplayService.swift`
- `load(session:)` / `play()` / `stop()` lifecycle
- `play()` returns `AsyncStream<PoseSample>` with timing based on inter-sample timestamps
- Configurable `playbackSpeed` (1x, 2x, 10x)
- Track progress as 0.0–1.0

**Test Requirements**:
- `test_emitsSamplesInOrder`
- `test_respectsPlaybackSpeed`
- `test_stopHaltEmission`
- Manual: replay in Simulator at 1x and 10x, verify debug overlay updates

**Integration**: Loads RecordedSession from RecorderService (Step 31). Feeds Pipeline via mock provider (Step 35).

**Demo**: Load a recorded session → play at 1x → samples emitted over time → switch to 10x → noticeably faster → stop mid-way → emission stops.

---

### Step 34: Golden Recordings

**Objective**: Create reference recordings with ground-truth tags for regression testing against success criteria.

**Implementation Guidance**:
- Record and export at least 4 sessions:
  1. `good_posture_5min.json` — 5 min sustained good posture
  2. `gradual_slouch.json` — starts good, deteriorates over 10 min
  3. `reading_vs_typing.json` — alternating tasks
  4. `depth_fallback_scenario.json` — includes depth loss moments
- Store in `GoldenRecordings/` directory
- Write replay-based regression test that verifies detection

**Test Requirements**:
- `test_detectsSlouchInGoldenRecording`: replay gradual_slouch → `badPostureDetected == true`
- All 4 recordings load and replay correctly

**Integration**: Uses RecorderService (Step 31) and ReplayService (Step 33) for creation and playback.

**Demo**: 4 JSON files committed. Replay test passes — system correctly detects slouch in golden recording.

---

### Step 35: Recording & Replay Pipeline Integration

**Objective**: Wire RecorderService and ReplayService into Pipeline and AppModel for use from the app.

**Implementation Guidance**:
- Pipeline → RecorderService: forward `latestSample` when recording active
- AppModel recording controls: `startRecording()` / `stopRecording()` with JSON export to disk
- Replay as PoseProvider: `ReplayPoseProvider` wraps ReplayService output into InputFrames
- AppModel replay controls: `loadSession(_ url:)` / `startReplay()` that swap to replay mode
- Live camera and replay share the same Pipeline code path

**Test Requirements**:
- Manual: start/stop recording from debug UI, JSON file saved
- Manual: load recording in Simulator, replay, debug overlay shows state changes
- Verify no duplicated logic between live and replay paths

**Integration**: Connects Steps 31–33 into the app. Enables Simulator-based development workflow.

**Demo**: Record 1 minute on device → save JSON → load in Simulator → replay → posture state changes visible in debug overlay.

---

### Step 36: TaskModeEngine Implementation

**Objective**: Classify current user activity (reading/typing/meeting/stretching) from movement patterns.

**Implementation Guidance**:
- Create `PostureLogic/Sources/PostureLogic/Engines/TaskModeEngine.swift`
- Analyze 10-second rolling window of `RawMetrics`
- Reading: low movement + small oscillations
- Typing: moderate movement + large movements
- Stretching: high movement (>0.7)
- Require ≥10 samples before classifying (default: `.unknown`)

**Test Requirements**:
- `test_classifiesReading_withLowMovementSmallOscillations`
- `test_classifiesTyping_withModerateMovement`
- `test_classifiesStretching_withHighMovement`
- `test_returnsUnknown_withInsufficientSamples`

**Integration**: Uses smoothed metrics (Step 11). Output feeds PostureEngine and NudgeEngine (Step 39).

**Demo**: Replay `reading_vs_typing.json` → task mode flips between reading and typing at correct segments.

---

### Step 37: Task-Adjusted Thresholds

**Objective**: Apply different posture thresholds per task mode so context-appropriate leniency is granted.

**Implementation Guidance**:
- Threshold multipliers by mode:
  - Reading: 1.3x forward creep, 1.2x shoulder rounding
  - Typing: 1.2x twist
  - Meeting: 1.2x forward creep, 1.5x twist, 1.2x lean + rounding
  - Stretching: disabled (all thresholds infinite)
  - Unknown: 1.0x (baseline)
- Apply multipliers in `PostureEngine.checkPostureBad()`

**Test Requirements**:
- `test_readingMode_moreForwardCreepAllowed`
- `test_stretchingMode_disablesJudgement`
- Existing PostureEngine tests still pass

**Integration**: Uses TaskMode from Step 36. Extends PostureEngine logic (Step 13).

**Demo**: Reading mode → can lean forward 30% more before triggering drifting. Stretching → large movements, no state transition.

---

### Step 38: Thresholds Settings Screen

**Objective**: UI to adjust all posture thresholds at runtime without rebuilding the app.

**Implementation Guidance**:
- Create settings screen with sliders/steppers for all `PostureThresholds` fields
- Include headDropThreshold, shoulderRoundingThreshold (from Step 18)
- Changes apply immediately (live-reload thresholds)
- Persist to UserDefaults or JSON file
- Load at app launch

**Test Requirements**:
- Manual: change threshold → engine behavior changes immediately
- Manual: kill/relaunch → threshold persists
- Manual: extreme test value → predictable state transition effect

**Integration**: Modifies PostureThresholds consumed by all engines.

**Demo**: Settings → slide forward creep threshold up → harder to trigger drifting. Relaunch → setting persisted.

---

### Step 39: TaskModeEngine Pipeline Integration

**Objective**: Wire TaskModeEngine into Pipeline so inferred task mode replaces the hardcoded `.unknown`.

**Implementation Guidance**:
- Add `TaskModeEngine` to Pipeline init
- Maintain rolling `[RawMetrics]` buffer (~100 entries = ~10 seconds at 10 FPS)
- After smoothing, append to buffer, trim to max, call `infer(from:)`
- Add `@Published var taskMode: TaskMode = .unknown` to Pipeline
- Replace hardcoded `.unknown` in `postureEngine.update()` and `nudgeEngine.evaluate()` calls

**Test Requirements**:
- Manual: task mode in debug overlay no longer always `.unknown`
- Manual: reading behavior → mode changes, thresholds adjust
- Manual: stretching → posture judgement disabled

**Integration**: Connects TaskModeEngine (Step 36) into Pipeline. PostureEngine and NudgeEngine now receive real task mode.

**Demo**: Debug overlay shows live task mode. Alternate reading/typing → mode changes. Stretch → mode switches, posture judgement disabled.

---

### Step 40: Setup Validation

**Objective**: Verify phone position is within supported range during calibration, using depth or 2D shoulder-width proxy.

**Implementation Guidance**:
- Create `SetupValidator` struct
- Depth mode: check `shoulderMidpoint.z` against 0.5m–1.5m range
- 2D mode: check `shoulderWidthRaw` as distance proxy (>0.5 = too close, <0.15 = too far)
- Also check vertical angle and full upper body visibility
- Integrate into calibration flow — warn before/during sampling

**Test Requirements**:
- `test_failsTooClose_depthMode`
- `test_failsTooFar_depthMode`
- `test_failsTooClose_2DMode`
- `test_failsTooFar_2DMode`
- `test_passesValidRange`
- Manual: phone too close → warning. Too far → warning. Correct distance → passes.

**Integration**: Extends calibration flow (Step 12). Uses SUPPORTED_RANGE.md thresholds (Step 3).

**Demo**: Place phone at 30cm → "Too close, move back." Place at 2m → "Too far, move closer." Place at 80cm → validation passes.

---

### Step 41: Stale Baseline Detection

**Objective**: Detect when baseline no longer matches the user's position and suggest recalibration.

**Implementation Guidance**:
- Compare current shoulder position against baseline
- If position shifted >30%, suggest recalibration
- Time-based staleness: baseline older than 1 hour flags as stale
- Show "Recalibrate" suggestion in UI
- Don't force recalibration — just suggest

**Test Requirements**:
- `test_detectsStaleBaseline_afterSignificantShift`
- `test_detectsStaleBaseline_afterTimeout`
- Manual: calibrate, move phone/chair noticeably → recalibration suggested

**Integration**: Uses baseline (Step 12) and current PoseSample stream (Step 9).

**Demo**: Calibrate → move phone 50cm → "Baseline may be stale. Recalibrate?" Return to original position → warning clears.

---

## Phase 3 — Hardening

> **Goal**: Long-run stability, thermal management, background operation, and Mac companion for daily use.

---

### Step 42: Long-Run Stability Harness (90 min)

**Objective**: Automated test proving 90-minute session stability with no memory leaks or crashes.

**Implementation Guidance**:
- MockPoseProvider emitting 54,000 frames (90 min at 10 FPS) at accelerated speed
- Monitor memory usage throughout — must stay <100MB
- No crashes, no unbounded growth
- Profile with Instruments if issues found

**Test Requirements**:
- `test_90MinuteSession_noMemoryLeak`: memory usage < 100MB after 54k frames
- Manual: Xcode memory gauge stabilizes, doesn't climb

**Integration**: Uses MockPoseProvider (Step 1) and full Pipeline.

**Demo**: Test passes in CI. Memory graph shows stable plateau, not growing line.

---

### Step 43: Thermal Throttling Strategy

**Objective**: Prevent device overheating by gracefully degrading service based on thermal state.

**Implementation Guidance**:
- Create `ThermalMonitor` observing `ProcessInfo.thermalState` notifications
- Response table: Nominal → full operation; Fair → 5 FPS; Serious → 3 FPS, disable depth; Critical → pause detection, show "Cooling down..."
- Mock thermal states for testing (real values only on device)

**Test Requirements**:
- `test_throttlesFPS_onFairThermalState`
- `test_disablesDepth_onSeriousThermalState`
- `test_pausesDetection_onCriticalThermalState`
- Manual: longer session on device → graceful degradation, no crash

**Integration**: Monitors system state. Controls Pipeline FPS and depth mode.

**Demo**: Simulate thermal state change → FPS drops, depth disables, or "Cooling down..." screen appears based on severity.

---

### Step 44: Background Mode Investigation

**Objective**: Research and document viable approaches for background operation on iOS.

**Implementation Guidance**:
- Investigate: background audio, Live Activity, BGProcessingTask, location updates
- Document constraints, trade-offs, battery impact for each
- Clear recommendation with pros/cons

**Test Requirements**:
- Investigation document exists with at least 3 approaches evaluated
- Each approach validated against Apple docs

**Integration**: Informs future background mode implementation.

**Demo**: Decision document committed with clear recommendation and trade-offs.

---

### Step 45: Mac Companion App

**Objective**: macOS app that broadcasts "User Active" state to iPhone via BLE to enhance task mode context.

**Implementation Guidance**:
- Monitor keyboard/mouse activity on Mac
- Broadcast "User Active" via BLE advertising packet
- iPhone receives signal and uses it to confirm "working" context
- **Does not suppress** slouch detection — only adds context
- If typing but slouching, user should still be nudged

**Test Requirements**:
- Manual: Mac app detects keyboard/mouse activity
- Manual: phone receives signal within seconds
- Manual: posture detection NOT suppressed by Mac signal

**Integration**: Enhances TaskMode context. Does not modify PostureEngine logic.

**Demo**: Mac companion running → type on keyboard → phone shows "User Active" in debug overlay. Slouch while typing → still get nudged.
