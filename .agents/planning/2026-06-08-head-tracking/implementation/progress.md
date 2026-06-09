# Head Tracking — Progress (mutable loop state)

**Single source of truth for "what's done" = this file + the `plan.md` checklist
+ `git log`.** Cold-start iterations read this first.

## Current Step
**Step 2 = DONE** ✅ — `headPitch/headYaw/headRoll: Float` exposed on `PoseSample`
(defaulted init), set in both `fuse2D` (:172) and `fuse3D` (:265) from
`computeHeadAngles(from:)`; ride `Pipeline.latestSample` → `AppModel` with no new
publisher. Steps 0–1 complete; Type Map populated below.
**Next: Step 3** — 3D pitch upgrade from LiDAR depth (nose vs. ear elevation in
`fuse3D`) with the 2D path as graceful fallback.

### Test-construction shape (for the angle unit tests)
`PoseObservation(timestamp:keypoints:confidence:)`, `Keypoint(joint:position:confidence:)`
(`position: CGPoint`, normalized 0…1). `PoseDepthFusionTests` builds poses via
private helpers `makeKeypoint(_:x:y:confidence:)` / `makePose(keypoints:…)` and
drives the **public `fuse()`**, asserting on the returned `PoseSample`.
- The new head-angle math is tested **directly** via the **internal** (not
  `private`) `computeHeadAngles(from:) -> HeadAngles` so it's reachable under
  `@testable import` before the angles are exposed on `PoseSample` (that's Step 2).
- **Sign convention is test-locked, not just commented:**
  `test_shoulderTwistPositiveWhenLeftHigher` places the "higher" shoulder at
  `y=0.55`, "lower" at `y=0.45` → inside the fusion **larger y = physically
  higher** (despite PoseService's `1.0 - y` flip at `PoseService.swift:122`).
  All head angles lock to this same y-up convention.

## Type Map
*(Verified 2026-06-09 via the 5 Step-0 greps + targeted file reads — real
names/line refs, not assumed.)*

### `PoseObservation` head-keypoint case names
`PostureLogic/Sources/PostureLogic/Models/PoseObservation.swift:29`
```swift
case nose, leftEye, rightEye, leftEar, rightEar   // on the `Joint` enum
```
- Already emitted by Vision every frame; reach `pose.keypoints: [Keypoint]`.
- Each `Keypoint`: `joint`, `position: CGPoint` (Vision-normalized 0…1),
  `confidence: Float`.
- **Vision is y-up** (0 = bottom, 1 = top); `PoseService` flips Y. Lock all
  angle signs against this (same convention as existing `computeShoulderTwist`).

### `PoseDepthFusion` helpers
`PostureLogic/Sources/PostureLogic/Services/PoseDepthFusion.swift`

| Symbol | Line | Role |
|---|---|---|
| `fuse(pose:depthSamples:confidence:intrinsics:trackingQuality:)` | 40 | `mutating`, entry; dispatches 3D→2D |
| `fuse2D(pose:leftShoulder:rightShoulder:headPos:shoulderWidth:trackingQuality:)` | 103 | private 2D path — builds `PoseSample` at **:143** |
| `fuse3D(…depthSamples:intrinsics:…)` | 160 | private depth path — builds `PoseSample` at **:230** |
| `resolveHeadPosition(from:)` | 289 | collapses nose→eye→ear into ONE `CGPoint`, **discarding the geometry** (the gap this stage fixes) |
| `keypoint(_:from:)` | 375 | `(Joint, PoseObservation) -> Keypoint?`, confidence-filtered. **Reuse for new angle helpers.** |
| `findDepth(for:in:)` | 249 | `(CGPoint, [DepthAtPoint]) -> Float?`, edge/confidence guarded. **Reuse for 3D pitch (Step 3).** |
| `computeShoulderTwist(…)` | 361 | sign reference: `asin(yDiff/width)·180/π`, +ve = left shoulder higher |
| `computeTorsoAngle(…)` | 330 | y-up handling reference |

**`unproject` is a FREE function, NOT a method** —
`PostureLogic/Sources/PostureLogic/Services/Unproject.swift:15`
```swift
func unproject(point: SIMD2<Float>, depth: Float, intrinsics: simd_float3x3) -> SIMD3<Float>
```
Called directly (no `self.`) 3× in `fuse3D` (:179/:184/:189).

### `PoseSample` init signature + call sites
`PostureLogic/Sources/PostureLogic/Models/PoseSample.swift` — `Codable`, memberwise `public init` at :23.
Stored `public let` fields:
```
timestamp: TimeInterval      depthMode: DepthMode
headPosition: SIMD3<Float>   shoulderMidpoint: SIMD3<Float>
leftShoulder: SIMD3<Float>   rightShoulder: SIMD3<Float>
torsoAngle: Float            headForwardOffset: Float
shoulderTwist: Float         shoulderWidthRaw: Float
trackingQuality: TrackingQuality
```
- **Step 2 adds** `headPitch / headYaw / headRoll: Float`, **defaulted in init**
  (mirror `Baseline.shoulderTwist`) to minimize churn.
- **33 `PoseSample(` call sites total:**
  - **Production: 2** — `PoseDepthFusion.swift:143` (fuse2D) & `:230` (fuse3D).
    The only two that must *set* the new angles.
  - **Tests: 31** — PostureLogic `Tests/`: MetricsEngine, PipelineThermal,
    MetricsSmoother, CoreModelCodable ×3, PipelineTaskMode, LongRunStability ×6,
    RecorderService, CalibrationEngine ×2, GoldenRecordings ×7, ReplayService,
    SetupValidator, StaleBaselineDetector, PipelineIntegration ×3; Quant
    `QuantTests/`: PostureSessionSummaryTests:24, PostureVisualizationViewModelTests:28.
  - With **defaulted** params none require edits; they are the regression net.
  - `CoreModelCodableTests` round-trips `PoseSample` (:172/:201/:286) — defaulted
    init keeps decode-from-old-JSON working; watch for hard-coded golden keys.

### ViewModel proxy lines to replace (Step 4)
`Quant/ViewModels/PostureVisualizationViewModel.swift`
- Published head channels: `:64 headYawDegrees` (← `shoulderTwist`),
  `:65 headPitchDegrees` (← `headForwardOffset`), `:66 headRollDegrees`
  (← shoulder-line angle).
- `ingest(...)` proxy math to repoint (keep amplify/cap/rest-relative):
  - `:205` `yawRaw = p.shoulderTwist * amp`            → source becomes `p.headYaw`
  - `:210` `pitchAbs = atan2(-p.headForwardOffset, …)` → source becomes `p.headPitch`
  - `:215-217` `rollAbs = atan2(shoulder dy, dx)`      → source becomes `p.headRoll`
  - `:202` `forwardTarget ← p.headForwardOffset` is the visualization forward
    offset (NOT a head angle) — **leave alone**.
  - `:222-234` rest-relative snapshot + clamp (Stage 1a) — **KEEP**.
  - `:238-240` dev-HUD mirrors (`unclampedYaw/Pitch/RollDegrees`) — update (Step 4/5).
  - `:261-263` filtered assignment — unchanged.
  - Doc block `:44-51` describes the proxy substitution — **update** to cite the
    real keypoint source.

### `latestSample` path Pipeline → AppModel (no new publisher needed)
- `Pipeline.swift:18` `@Published public var latestSample: PoseSample?`; set at :287 & :378.
- `AppModel.swift:23` `@Published var latestSample: PoseSample?`; mirrored via
  `pipeline.$latestSample.assign(to: &$latestSample)` (:353-354).
- New `PoseSample` fields ride this existing publisher automatically. **Verify only.**

### Working simulator destination
- Canonical (per plan): `platform=iOS Simulator,name=iPhone 16 Pro`.
- ⚠️ `xcrun simctl list devices available` was **unresponsive / returned empty**
  in this environment (consistent with the known note: simctl enumeration
  unreliable here; xcodebuild is authoritative). **Confirm a live destination at
  the first Step-1 build**; if `iPhone 16 Pro` is invalid, resolve from
  xcodebuild's destination error and record the working value here.

## Verification Notes
- **2026-06-09 — Step 2 (expose on PoseSample, TDD):** RED → added 2 end-to-end
  tests to `PoseDepthFusionTests` driving the **public `fuse()`** and asserting on
  the returned `PoseSample`: `test_fuse_populatesHeadAnglesWhenFacialKeypointsPresent`
  (left ear lower ⇒ +roll, nose toward right ear ⇒ +yaw, nose below ear line ⇒
  +pitch) and `test_fuse_headAnglesNeutralWhenNoFacialGeometry` (all three == 0).
  These failed to compile before the fields existed. GREEN → added
  `headPitch/headYaw/headRoll: Float` to `PoseSample` as **defaulted (`= 0`) init
  params** (mirrors `Baseline.shoulderTwist`), wired both `fuse2D` (:172) and
  `fuse3D` (:265) from `computeHeadAngles(from:)`. `Pipeline.latestSample` →
  `AppModel.latestSample` carries them with **no publisher change** (verify-only,
  confirmed). Defaulted params meant **0 edits** to the 31 test call sites and old
  Codable JSON. Tests: **full PostureLogic suite 480/480 green** (was 478 +2), no
  regressions. App suite unaffected (additive public surface, defaulted).
  Commit: `feat: expose head pitch/yaw/roll on PoseSample`.
  Next: **Step 3** (3D pitch from LiDAR depth).
- **2026-06-09 — Step 1 (YAW + PITCH, TDD):** RED → added 7 `test_headYaw_*` and
  6 `test_headPitch_*` to `PoseDepthFusionTests` driving `computeHeadAngles(from:)`
  → 7 directional assertions failed (zero/centred cases already passed since the
  fn returned 0). GREEN → implemented `computeHeadYaw` + `computeHeadPitch`,
  wired both into `computeHeadAngles`.
  **Yaw formula:** `asin(clamp((nose.x − earMidX) / |earSep|, −1, 1))·180/π`;
  centred nose → ~0°, nose toward `.rightEar` (larger image-x) → **positive**.
  **One-ear-missing rule** (tuple `switch` on `(leftEar, rightEar)` optionals): a
  strong turn occludes the far ear, so exactly one ear present → strong yaw
  **toward the missing side** = `±60°` (`Self.oneEarMissingYawDegrees`); missing
  `.rightEar` → +, missing `.leftEar` → −. Both ears + no nose, or no ears → 0.
  **Pitch (2D) formula:** `atan2(lineY − nose.y, |Δx|)·180/π` where `lineY` =
  ear-midpoint y (eye-line fallback, mirrors roll), `|Δx|` = that line's
  separation. Nose **below** line (chin-down / forward-head, y-up ⇒ `nose.y <
  lineY`) → **positive** (aligns with Step 8's "forward head tilt ≈ pitch > 15°").
  Raw zero = geometric on-the-line case, NOT physiological neutral — the
  ViewModel's rest-relative calibration re-zeros it (Step 4). No nose / no
  reference pair → 0.
  **One bug caught + fixed:** initial pitch used `nose.y` (a `Keypoint` has no
  `.y`) → `nose.position.y`. SourceKit flagged it; `swift test` is authoritative
  and confirmed after fix.
  Tests: 13/13 new green; **full PostureLogic suite 478/478 green** (was 465 +13),
  no regressions. App suite (`QuantNoWatchTests`) intentionally **not** run this
  step: `computeHeadAngles`/`HeadAngles` are `internal` with no public-surface
  change, so the app target is unaffected until Step 2 plumbs `PoseSample` — same
  regression-gate precedent as the roll commit.
  Commit: `feat: compute head yaw + pitch from facial keypoints` (f79f9a8).
  Next: **Step 2** (expose angles on `PoseSample` → `AppModel`).
- **2026-06-09 — Step 1 (ROLL, TDD):** RED → added 5 `test_headRoll_*` to
  `PoseDepthFusionTests` calling `computeHeadAngles(from:)` (level→~0,
  right-ear-lower→<0, left-ear-lower→>0, eye-line fallback, no-keypoints→0) →
  build failed ("no member 'computeHeadAngles'"). GREEN → added `HeadAngles`
  struct + internal `computeHeadAngles` + private `computeHeadRoll` to
  `PoseDepthFusion.swift`. **Roll formula:** `atan2(rightEar.y - leftEar.y,
  |rightEar.x - leftEar.x|)·180/π`; ear line primary, eye line fallback, neutral 0
  otherwise. **|Δx| denominator** (not literal `atan2(Δy,Δx)`) so a level head
  reads ~0° regardless of ear x-ordering — literal atan2 would read 180° on a
  front-facing subject (anatomical leftEar at larger image-x). **Sign locked:**
  right ear physically lower → negative roll (y-up, matches `computeShoulderTwist`).
  Tests: 5/5 roll green; **full PostureLogic suite 465/465 green**, no regressions.
  Commit: `feat: compute head roll from facial ear/eye line (2D)`.
  Next: yaw (nose-vs-ear-midpoint ÷ ear separation).
- **2026-06-09 — Step 0 (orientation):** created branch `feature/head-tracking`
  from `main`; ran the 5 orientation greps + targeted reads; Type Map above
  populated and verified against source. **No product code written.**
  Assessment: head tracking is **not yet implemented** — Vision detects the five
  facial keypoints but `resolveHeadPosition` (:289) collapses them to one point
  and discards the geometry; `PoseSample` has no head-angle fields; the ViewModel
  fabricates pitch/yaw/roll from shoulder-skeleton proxies (a shoulder shrug with
  a still head currently reads as head movement — the bug this stage removes).
  Build all of it across Steps 1-7. Next: **Step 1** (RED-first 2D angle math).

## Known blockers
- simctl device enumeration unresponsive in this environment → simulator
  destination unverified until first build (see Type Map). Not blocking Step 0.
