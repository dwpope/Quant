# Quant SwiftUI — durable notes

## Cross-project: Swift 6.3 strict-concurrency gotchas
See `swift6_concurrency_gotchas.md` (found in `~/Developer/Remember the moment`,
a different repo, but generally applicable): (1) actor calling an `async`
method on a non-Sendable stored-property class → "sending risks data races";
fix with justified `nonisolated(unsafe)` if actor logic already serializes
access. (2) actor `let` Sendable-typed stored properties need explicit
`await` to read from a DIFFERENT module (fine same-module) — mark `nonisolated`
if meant for free external observation. (3) fixed epoch-offset `Date` test
constants silently go stale vs a real `Date()`-based clock under test.

## Cross-project: iOS Simulator manual-verification gotchas (2026-07)
See `ios_simulator_verification_gotchas.md`: (1) `xcrun simctl` name-based
lookups (`boot "iPhone 17"`, `install "iPhone 17" ...`) are ambiguous when
multiple runtimes install a device with the identical name (e.g. "iPhone 17"
exists once per iOS 26.0/26.1/26.2/26.4/26.5) — it silently picks one
(observed: matches the newest/default runtime) rather than erroring; pin a
UDID for reproducible scripted verification. Also covers (5) no PIL/
ImageMagick/ffmpeg preinstalled for pixel-exact screenshot analysis — use a
`python3 -m venv` + `pip install pillow` (system pip3 install fails, PEP 668),
`sips --cropOffset` is confusing/unreliable, don't fight it; (6) enum cases
with associated values (e.g. `UIState.kept(momentID:)`) still match a bare
`case .kept:` in a switch, that's valid Swift, not a brief/source mismatch;
(7) in a Canvas waveform, alpha-driven and height-driven visual channels can
be verified independently via pixel scan — don't assume flat bar heights mean
broken audio capture. (2) `find ~/Library/Developer/
Xcode/DerivedData -name 'X.app' | head -1` is NOT safe to assume "the app I
just built" — stale DerivedData dirs from old sessions sort alphabetically
before fresh ones; check mtime instead. (3) SpeechAnalyzer/SpeechTranscriber
(iOS 26) locale support (`SpeechTranscriber.supportedLocale(equivalentTo:)`)
was observed NOT resolving on iOS 26.5 Simulator even though the host Mac's
own locale matched exactly (en_GB) — symptom: log repeats only
"Fetching languages of supported Assistant assets" (SFSpeechAssetManager XPC)
every retry with zero further `AssetInventory`/transcription progress, forever,
on a clean interval (proves the caller's retry loop itself isn't hung — the
locale call fails fast and cleanly every time). Treat as a known Simulator
limitation requiring a physical device to fully verify on-device transcription,
not a bug in composition code that calls it. (4) NO tap/UI-automation works in
this sandbox — `osascript`/System Events against the Simulator always times
out (`-1712`), no `idb`/`cliclick` installed either; don't retry it. Workaround
for screenshotting a tap-only-reachable view: temporarily swap the App root to
render that view directly, screenshot, then revert byte-for-byte (`git diff`
zero) before committing — same pattern as reverted container-file seeding.
(8) For a multi-screen tap-gated flow (list → sheet → button → dismiss →
refresh), chain a small `Task.sleep`-delayed scaffold at *each* tap point,
calling the exact same methods the real buttons call — it self-chains via the
real `onDone`/dismiss callbacks until the data runs out. Over-provision
delays (6-8s/step) or just redo the seed+build+install cycle with fresh data
rather than fighting one exact timing window. Full detail: gotcha #8 in
`ios_simulator_verification_gotchas.md`.

## "Remember the moment" AppCore — SDD task-brief conventions (verified 2026-07-15, Tasks 10-12)
- Repo `~/Developer/Remember the moment` (path has a space — always quote it),
  SwiftPM package `AppCore/`, tasks driven by `.superpowers/sdd/task-N-brief.md`
  files with verbatim test+impl code blocks. The brief's own printed "expected
  test count" (e.g. "Test run with 37 tests...") is routinely STALE by the time
  a task is actually run (earlier tasks' test counts drifted). The task's outer
  instructions/context message gives the corrected authoritative count — trust
  that over the brief. As of Task 12 (`VisualSourceRouter`): 45 tests, 7 suites.
  On any mismatch, `rm -rf AppCore/.build` before retrying
  `swift test --package-path AppCore` (stale incremental build DB can otherwise
  throw `disk I/O error` / `fatalError` on the next run after a scope error) —
  a one-off `disk I/O error` line alongside an otherwise-passing "Test run with
  N tests..." result is harmless build-DB noise, not a real failure (confirmed
  by rerunning clean multiple times with identical passing output, Task 12).
- App-target composition (`AppEnvironment.swift`) intentionally stays
  `ObservableObject`/`@Published` (Tasks 1-12), NOT `@Observable` — an
  established repo convention predating the global `@Observable`-preferred
  guideline; don't retrofit it as part of an unrelated task.
- grep on this machine is `ugrep` (no `./` prefix) and one brief-verbatim SF
  Symbol (`camera.slash`, Task 12) doesn't exist on this SDK — see gotcha #9
  in `ios_simulator_verification_gotchas.md` for how to verify both rather
  than eyeballing. Fixed in the Task 12 review wave (2026-07-15) to
  `video.slash`.
- `.superpowers/sdd/` has its own `.gitignore` (`*`) — task briefs/reports/diffs
  in there are intentionally untracked scratch docs; write/append to them as
  instructed but don't try to `git add` them into a commit (it'll refuse
  unless forced, which isn't the intent).
- Wiring a callback into a kit type's `@Sendable` closure param (e.g.
  `GlassesVisualSource.onInterruption` → `EpisodeManager`) can require making
  the captured dependency (`ProbeLog`) `@unchecked Sendable`, plus hoisting it
  out of an inline-constructed sibling property into a `let` property assigned
  before the sibling in `init()` — see gotcha #4 in
  `swift6_concurrency_gotchas.md`.
- `@unchecked Sendable` is used repeatedly and deliberately on capture-source
  classes (`FrameLookbackBuffer`, `PhoneCameraSource`) via a documented
  lock-guarded-buffer / single-owner-actor-calls-start-stop justification —
  this is plan-governed for this repo, not a shortcut to flag in review.
- `CIContext.jpegRepresentation(of:colorSpace:options:)` behaves IDENTICALLY on
  macOS and iOS (confirmed via `swift test` on macOS host): produces a valid
  JPEG (correct SOI marker `0xFFD8`, plausible byte count) from a CVPixelBuffer
  built via plain `CVPixelBufferCreate`+`CIImage(cvPixelBuffer:)`. Safe to unit
  test this pure conversion cross-platform without an iOS Simulator.
- Pattern for AVFoundation-backed `VisualMomentSource`/mic sources in this repo:
  session wiring (`AVCaptureSession` start/stop, device/input/output config) is
  `#if os(iOS)`-gated and deliberately left UNTESTED by `swift test` (no runtime
  exercise on macOS); only the pure conversion functions (e.g.
  `static func jpeg(from: CVPixelBuffer) -> Data?`) and the buffer/candidates
  logic get real TDD coverage. Verify iOS-only code only via the regression
  `xcodebuild build -scheme RememberTheMoment -destination 'generic/platform=iOS
  Simulator' -quiet` (exit code 0 with `-quiet`; no stdout on success).
- `.superpowers/sdd/task-N-report.md` filenames are reused ACROSS DIFFERENT
  plans (task numbering resets per plan, e.g. scaffold-and-spikes Task 3 vs
  call-recovery Task 3) — a task brief instructing you to write to
  `task-3-report.md` means overwrite whatever's there from an earlier plan;
  note the overwrite explicitly at the top of the new report rather than
  silently clobbering. Check `.superpowers/sdd/progress.md` for the ledger of
  which plan/branch is currently active before assuming a stale report file
  is an error.
- Call-recovery plan (2026-07-18, branch `feature/call-recovery`): 3 tasks —
  (1) restartable `PhoneMicSource` (fresh `AsyncStream` per `start()`), (2)
  `CaptureCoordinator` wires `AudioWatchdog` (silent-mic-after-arm →
  disarm+probe), (3) `AppEnvironment` observes
  `AVAudioSession.interruptionNotification` (`.began`→disarm, `.ended`→
  re-arm via `start()`). Gate counts: AppCore 48/7, CaptureKit 58/13,
  MemoryKit 30. See gotcha #6 in `swift6_concurrency_gotchas.md` for why the
  `notifications(named:)` async-sequence observer needed no Swift 6
  workaround.
- Call-recovery final-review fix wave (2026-07-18, commit f3748b7): whole-branch
  review found `CaptureCoordinator.arm()`/`disarm()` were reentrancy-unsafe —
  concurrent scenePhase-arm and interruption-disarm could interleave their
  `source.start()`/`source.stop()` calls, invalidating `PhoneMicSource`'s
  `@unchecked Sendable` justification. Fixed with a FIFO `transition: Task<Void,
  Never>?` chain (arm/disarm bodies moved to `performArm`/`performDisarm`,
  callable only via the chain) — see gotcha #5 in `swift6_concurrency_gotchas.md`
  for the reusable pattern (incl. the error-box trick to preserve `arm()`'s
  `throws` through the chain, and the gated-fake test pattern that catches the
  race deterministically). AppCore 49/7, CaptureKit 58/13 unchanged.
- Task 13 (finalize, 2026-07-15): full-suite authoritative counts as of the
  last review fix wave — MemoryKit 30/0-fail, CaptureKit 56 tests/13 suites,
  AppCore 45 tests/7 suites, GlassesKit 31 tests/6 suites (xcodebuild),
  GlassesKitSmoke 2 tests/1 skipped (xcodebuild), DAT-import grep exactly 3
  files (`DATGlassesSession.swift`, `MockDeviceSmokeTests.swift`,
  `MockGlassesBootstrap.swift`). All matched on first run, no `.build` wipe
  needed. `.superpowers/sdd/*.md` briefs/reports are gitignored (`*` rule) —
  writing a report there never shows up in `git status`/`git add`, that's
  expected, not a bug. When the working tree is already clean at finalize
  time (all task work committed earlier), use
  `git commit --allow-empty -m "..."` to still record the finalize marker
  commit.

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

## Scoring headDrop = ear-carriage (neckHeight) smoothing (2026-07-02)
- SCORED metric `RawMetrics.headDrop = baseline.neckHeight − sample.neckHeight` (ear-midpoint carriage, `MetricsEngine`). Small amplitude + keypoint jitter → flickers ±0.01 even after the shared EMA.
- `MetricsSmoother` (Engines/): `headDrop` now bypasses the shared `alpha`(=0.3) EMA and rides a DEDICATED `OneEuroFilter` keyed on `sample.timestamp` (minCutoff 0.15 Hz → τ≈1.06 s stationary; beta 6.0 — must be LARGE, posture speeds are hundredths/s). Other 4 fields keep the EMA. `reset()` also resets the filter. Constants `MetricsSmoother.headDropMinCutoff/headDropBeta` (static). Provisional — retune on device.
- One-Euro is IDENTITY when dt≤0 (seed + non-advancing-timestamp contract) → constant-timestamp unit tests (and single-sample seed) pass through raw, so exact numeric assertions hold. But MetricsSmoother/PipelineIntegration tests that ADVANCE time (dt=0.1) do NOT get identity — a single hard 0→1 step SNAPS to ~0.936 (huge speed lifts cutoff), so "heavier than EMA" only shows on SLOW posture-speed ramps. Verify tuning numerics with a standalone `swift` sim before writing exact-value test assertions.
- `PostureThresholds.headDropThreshold`: 0.06 → 0.018 (device: bad≈0.025, mild≈0.012). Ripples: two `==0.06` default-value asserts (ConfigAndDecisionModelTests, CoreModelCodableTests); MetricsEngineTests straddle deficits 0.05/0.07→0.012/0.025; NudgeEngine ratio tests (dominantReason = value/threshold, tie→sustainedSlouch) — rescale headDrop inputs so ratios keep their intent (0.036 for a 2.0 tie; <0.018 for "neither exceeds"). NudgeEngineTests call the engine DIRECTLY (no MetricsSmoother) so only the threshold, not the filter, touches them.
- Note: `PoseSample`/`Baseline` Codable is now HAND-WRITTEN (`init(from:)`/`encode` with `decodeIfPresent` for additive fields headPitch/Yaw/Roll/headOrientation/neckHeight) — the older "fully compiler-synthesized" note above is stale.
- Full PostureLogic suite after this change: 556 tests green (was 552).
