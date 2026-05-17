# Progress: Posture Visualization

> Mutable loop state. Every iteration reads this first and appends to it before
> stopping. This file + `plan.md`'s checklist + `git log` are the **only**
> memory that survives a cold iteration.

## Current Step

**Step 2 — Debug harness: `VisualizationDebugView`** _(Step 1 complete)_

> ✅ **RESOLVED 2026-05-17** — the pre-existing suite blocker (see "Known
> Blocker — RESOLVED" below) is fixed and merged (`00bbbbe` + merge `6ccda58`).
> Full `xcodebuild test … QuantNoWatchTests` is GREEN again — verified
> `** TEST SUCCEEDED **` (0 failures, 0 crashes) on this merged branch. Step 6's
> "full app suite green" gate is satisfiable; no special handling needed.

## Working environment (fill in during Step 0, reuse thereafter)

- Verified simulator destination:
  `platform=iOS Simulator,id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5`
  (plan default; resolves to an available **iPhone 17**, iOS 26.0.1 — the
  plan's "iPhone 16" comment is stale but the UDID is live). Reuse this.
- Branch confirmed: `feature/posture-visualization` (never committed to `main`).
- **Canonical regression command:** the full
  `xcodebuild test … QuantNoWatchTests` run is **GREEN again** as of merge
  `6ccda58` (blocker fixed — see "Known Blocker — RESOLVED" below). Use it as
  the Step 6 gate. Per-step, the focused tests via
  `-only-testing:QuantTests/<Class>` plus
  `swift test --package-path PostureLogic` (460 pass) remain a fast check.

## Type Map (authoritative names from the actual codebase — verified Step 0)

| Concept | Real type / field | File:line | Notes |
|---|---|---|---|
| Raw posture metrics | `RawMetrics`: `timestamp, forwardCreep, headDrop, shoulderRounding, lateralLean, twist, movementLevel, headMovementPattern: MovementPattern` (all metrics `Float`) | `PostureLogic/Sources/PostureLogic/Models/RawMetrics.swift:3` | **No `headForwardOffset` here.** Step 1 scaling sources: `twist→shoulderRotationDegrees`, `lateralLean→sideLeanOffsetPoints`, `forwardCreep→assemblyScale`. |
| Posture state enum | `PostureState`: `.absent`, `.calibrating`, `.good`, `.drifting(since:)`, `.bad(since:)` (Codable, Equatable; `.isBad`, `.durationInCurrentState`) | `PostureLogic/Sources/PostureLogic/Models/PostureState.swift:3` | Calibrating case = `.calibrating` → `isCalibrating := (state == .calibrating)`. 4 visual states map: calibrating / good / drifting / bad (absent ≈ calibrating/idle). |
| Tracking quality | `TrackingQuality`: `.lost`, `.degraded`, `.good` (String raw, Comparable; `.allowsPostureJudgement`) | `PostureLogic/Sources/PostureLogic/Models/TrackingQuality.swift:1` | 3 discrete cases → opacity mapping in Step 1 (e.g. lost→low, degraded→mid, good→1.0). |
| AppModel publisher(s) | `AppModel: ObservableObject` — `@Published latestMetrics: RawMetrics?`, `@Published postureState: PostureState`, `@Published trackingQuality: TrackingQuality`, `@Published latestSample: PoseSample?` | `Quant/AppModel.swift:7` (`:12,18,19,17`) | VM subscribes via Combine to these. Step 1 should expose a testable `ingest(...)` seam fed by these publishers so tests run camera-free. |
| Pose keypoints | **NOT raw nose/ear/eye.** `PoseSample`: `headPosition: SIMD3<Float>`, `shoulderMidpoint`, `leftShoulder`, `rightShoulder`, `torsoAngle: Float`, `headForwardOffset: Float`, `shoulderTwist: Float`, `shoulderWidthRaw: Float`, `trackingQuality` | `PostureLogic/Sources/PostureLogic/Models/PoseSample.swift:4` | Raw `Keypoint`/`Joint` are internal to PostureLogic, **not** published on AppModel. See substitution below. |

**Field substitutions made** (design-doc name → real-field mapping):
- Design doc's **`headForwardOffset`** → real field **`PoseSample.headForwardOffset: Float`**
  (`PoseSample.swift:14`). It exists, but on `PoseSample`, not `RawMetrics`.
- Design doc derives **yaw/pitch/roll from raw 2D nose/ear/eye keypoints** →
  those raw points are **not exposed** on the public `AppModel`/`PoseSample`
  surface (raw `Keypoint`/`Joint` are PostureLogic-internal). **Step 1 must
  derive display yaw/pitch/roll from `PoseSample` geometry instead**:
  `headPosition` vs `shoulderMidpoint` SIMD3 deltas (pitch/forward),
  `leftShoulder`→`rightShoulder` line + `shoulderTwist` (roll/yaw),
  `torsoAngle`. This is a ViewModel **display** computation, **not** new
  detection logic (respects the "no new posture detection logic" anti-goal).
  Caps (±60° pitch, ±45° roll) and the α=0.2 low-pass still apply per plan Step 1.

## RealityKit Attempt Ledger

> See `plan.md` Step 3. Increment `attempts` by 1 each Step 3/4 iteration that
> does NOT end with both a clean scene build AND progress on the step's
> done-criteria (compiles-but-no-progress still counts). Repeated identical
> blocking error → bail immediately. At `attempts == 2` (or repeat-failure),
> abandon RealityKit → tag `wip/realitykit-vis` → switch to Step 3F.

```
attempts: 0
budget: 2
last_error_class: (none)
status: not-yet-engaged   # not-yet-engaged | in-progress | shipped | exhausted
```

Attempt log:
- _(none yet)_

## Known Blocker — RESOLVED 2026-05-17 (pre-existing; NOT caused by posture-viz work)

> ✅ **RESOLVED.** Fixed on branch `fix/mainactor-deinit-sigabrt` (commit
> `00bbbbe`): `nonisolated deinit {}` added to **10** app-target `@MainActor`
> classes — AppModel, LivePostureDataSource, SipStore, SipTrainingStore,
> SipLabelQueue, AudioFeedbackService, WatchConnectivityService,
> ARSessionService, FrontCameraSessionService, SwitchablePoseProvider — then
> merged into this branch via `6ccda58`. The original ≈5-class estimate was
> incomplete (AppModel transitively owns more @MainActor types; full ownership
> graph = 10). Full `xcodebuild test … QuantNoWatchTests` then ran
> `** TEST SUCCEEDED **` (0 failures, 0 crashes) on the merged branch;
> PostureLogic still 460/0. Tracked task `task-1779007181-1bd5` closed. The
> diagnosis below is retained for historical context only.

**ID:** suite-wide `@MainActor` deinit SIGABRT on the Xcode 26 / iOS 26 SDK /
macOS 26.2 toolchain. **Tracked task:** see `ralph tools task` —
"Fix: pre-existing @MainActor back-deploy-deinit SIGABRT…".

**Symptom:** the full `xcodebuild test … QuantNoWatchTests` run fails. Every
failure is `Test crashed with signal abrt.` (zero assertion failures) in
`@MainActor`-isolated `ObservableObject` classes: `AppModelTests`,
`LivePostureDataSourceTests`, `SipLabelQueueTests`, `SipStoreLabelTests`,
`SipTrainingStoreTests`. Crash stack (from
`~/Library/Logs/DiagnosticReports/Quant-*.ips`):
`PostureVisualizationViewModel/AppModel.__deallocating_deinit` →
`swift_task_deinitOnExecutorMainActorBackDeploy` →
`swift_task_deinitOnExecutorImpl` →
`swift::TaskLocal::StopLookupScope::~StopLookupScope()` → libmalloc
`POINTER_BEING_FREED_WAS_NOT_ALLOCATED` → `abort`.

**Root cause:** with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` +
`SWIFT_APPROACHABLE_CONCURRENCY = YES` + `IPHONEOS_DEPLOYMENT_TARGET = 18.0`,
the compiler gives every `@MainActor` class an *isolated deinit* that
back-deploys through `swift_task_deinitOnExecutorMainActorBackDeploy`. When
XCTest deallocates such an object from an `NSInvocation` (not a Swift task),
that shim corrupts the heap and aborts. Nondeterministic (heap-layout
dependent); parallel test clones make it worse but it reproduces serially too.

**Proven, behaviour-neutral remedy:** add `nonisolated deinit {}` to the
affected class (teardown needs no main-actor isolation). Applied to
`PostureVisualizationViewModel` in Step 1 → its 17 tests pass reliably even
inside the full parallel run. The pre-existing classes need the same one-line
treatment; that is a **separate atomic task** (touches ≥5 unrelated files),
deliberately NOT folded into Step 1 (Ralph one-step atomicity + "no unrelated
refactor" constraint).

**Proof it is pre-existing, not a Step-1 regression:** with *all* posture-viz
product/test code removed (only the necessary `.gitkeep` build-fix retained),
`-only-testing:QuantTests/AppModelTests` still fails identically
(`BASELINE_EXIT=65`, 8 crashed tests, same signature). My change touches none
of those classes.

## Verification Notes

### Step 1 — Data layer: `PostureVisualizationViewModel` (TDD) (2026-05-17)

- **TDD:** wrote `QuantTests/PostureVisualizationViewModelTests.swift` first
  (17 tests, RED — crashed before fix), then
  `Quant/ViewModels/PostureVisualizationViewModel.swift` → GREEN.
- **Result:** all **17** new tests pass — verified twice in isolation
  (`-only-testing`) **and** within the full parallel run (xcresult
  `09-19-11`: every PostureVisualizationViewModelTests case `passed`).
  `swift test --package-path PostureLogic` → **460 pass / 0 fail** (package
  untouched). Zero assertion failures anywhere in any run.
- **9-vs-10 properties:** design code-block lists 10 output properties; plan
  says "9". Implemented all **10** `@Published` (a superset satisfies "9
  exist"): shoulderRotationDegrees, sideLeanOffsetPoints,
  headForwardOffsetPoints, assemblyScale, headYawDegrees, headPitchDegrees,
  headRollDegrees, opacity, stateColor, isCalibrating.
- **Substitutions (recorded earlier in Type Map) implemented as:**
  yaw ← `PoseSample.shoulderTwist`×1.5 (clamp ±90); pitch ←
  `atan2(-headForwardOffset, 0.15)·180/π`×1.5 (cap ±60); roll ←
  `atan2(Δy,Δx)` of right−left shoulder ·180/π ×1.5 (cap ±45). Metric
  scalings: twist×1.5, lateralLean×100, headForwardOffset×100, 1+creep×0.5.
  Low-pass α=0.2, first sample seeds (no 0-ramp), discrete colour/flag not
  smoothed. Testable `ingest(metrics:pose:state:quality:)` seam + Combine
  `bind(to: AppModel)` via `CombineLatest4`. No pose-detection or public-API
  edits (design anti-goal respected).
- **Decision 1 — `.gitkeep` build fix:** Step 0's two `.gitkeep` files were
  auto-swept into the synced root group as `CpResource` steps, both copying to
  `Quant.app/.gitkeep` → `error: Multiple commands produce …` (the build, and
  thus *all* tests, failed). Removed both; `Quant/ViewModels/` now persists via
  its real source file, `Quant/Views/Visualization/` is recreated by Step 2.
  Editing `project.pbxproj` membership exceptions was rejected (fights the
  synced-folder model the repo uses). Necessary & in-scope (unblocks Step 1's
  mandated verification).
- **Decision 2 — `nonisolated deinit {}`:** required to stop the toolchain
  back-deploy-deinit SIGABRT for this class (see Known Blocker). Behaviour-
  neutral.
- **Decision 3 — full-suite gate:** Step 1's done-criteria says "full app
  suite green". That is impossible on this toolchain due to the pre-existing
  Known Blocker (proven independent of Step 1). Step 1 is committed on the
  basis of its own rigorous green (focused tests + PostureLogic package + zero
  assertion failures + proven no-regression) with the blocker tracked as a
  high-priority task. Confidence 80 — documented in
  `.ralph/agent/decisions.md`.
- **Commit:** `feat: add PostureVisualizationViewModel with heuristics + tests`.
- **Regressions:** none attributable to Step 1 (baseline proof above).

### Step 0 — Branch + folder scaffolding (2026-05-17)

- **Branch:** `feature/posture-visualization` already existed and was checked
  out (HEAD `01c0aa7`). Confirmed never on `main`.
- **Folders:** created `Quant/ViewModels/.gitkeep` and
  `Quant/Views/Visualization/.gitkeep`. Synced-folder assumption verified —
  `project.pbxproj:81` declares `path = Quant` under a
  `PBXFileSystemSynchronizedRootGroup`, and `Quant/Views/` already nests
  subfolders (`Showcase/`), so the new folders auto-register with no
  `.pbxproj` edits (consistent with prior memory on synced root groups).
- **Type Map:** populated above from the codebase orientation greps; two
  substitutions recorded (see "Field substitutions made").
- **Build/tests:** none required — Step 0 done-criteria is "No product code
  yet"; only `.gitkeep` files were added (cannot affect compilation). No
  pre-existing tests touched; pose-detection source untouched.
- **Regressions:** none.
- **Commit:** `chore: scaffold posture-visualization branch and folders`.

## Completed Steps

- **Step 0** — Branch + folder scaffolding (commit
  `chore: scaffold posture-visualization branch and folders`).
- **Step 1** — Data layer `PostureVisualizationViewModel` + 17 TDD tests
  (commit `feat: add PostureVisualizationViewModel with heuristics + tests`).
  Includes the necessary `.gitkeep` build fix. Verified: 17/17 new tests
  pass, PostureLogic 460/460, no regression (pre-existing toolchain blocker
  documented + tracked).
