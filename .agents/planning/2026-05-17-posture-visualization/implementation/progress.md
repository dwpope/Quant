# Progress: Posture Visualization

> Mutable loop state. Every iteration reads this first and appends to it before
> stopping. This file + `plan.md`'s checklist + `git log` are the **only**
> memory that survives a cold iteration.

## Current Step

**Step 5 — Integration & polish**
_(Steps 0–4 complete; Step 3F = N/A — RealityKit shipped)_

> ✅ RealityKit path **shipped**. Steps 3 (scaffold) and 4 (binding) both
> ended with a clean app build + done-criteria progress, so the Attempt
> Ledger counter never incremented (`attempts: 0/2`, `status: shipped`).
> Step 3F (SwiftUI fallback) is therefore `[N/A — RealityKit shipped]` in
> both `plan.md` and this file — its trigger condition (Ledger exhausted)
> never fired. The next iteration's first unchecked box is **Step 5**, a
> SwiftUI/RealityKit *polish* step (not budget-gated): wire the
> visualization into navigation alongside `DebugOverlayView`, state-driven
> colour transitions (calibrating pulse / good / drifting / bad), baseline
> "ghost" duplicates, and ~0.3s eased transforms (`content.animate`). The
> Step 4 binding (`PostureVisualizationBinding.apply`) and the named-entity
> contract are the seam Step 5 builds on.

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
status: shipped   # not-yet-engaged | in-progress | shipped | exhausted
```

Attempt log:
- **2026-05-17 — Step 3 (scaffold).** Result: **clean build + progress** →
  counter NOT incremented (per ledger rule: clean scene build AND
  done-criteria progress does not burn budget). RealityKit API surface
  verified against Apple docs (Context7) *before* coding so a guessed API
  could not cause a budget-burning compile failure. No blocking error.
  `attempts` stays 0; 2 attempts remain for Step 4.
- **2026-05-17 — Step 4 (binding).** Result: **clean build + progress** →
  counter NOT incremented. Same discipline: the full Step-4 RealityKit
  surface (`RealityView update:`, `content.entities`,
  `Entity.findEntity(named:)`, `entity.orientation/position/scale`,
  `simd_quatf(angle:axis:)`, `OpacityComponent`, `UnlitMaterial(color:)`)
  was verified against Apple docs (Context7) *before* coding. App build
  `** BUILD SUCCEEDED **` (exit 0, 0 errors); 8 new binding tests + 17
  ViewModel tests `** TEST SUCCEEDED **`. No blocking error. `attempts`
  stays **0/2**. **RealityKit is the shipped renderer** → Step 3F N/A; the
  budget mechanism is now closed out (status: shipped).

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

### Step 4 — Bind ViewModel → entity transforms (2026-05-17)

- **Added:** `Quant/Views/Visualization/PostureVisualizationBinding.swift` —
  value-type `enum` (no class → no `@MainActor` isolated-deinit hazard) split
  into a **pure `resolve`** (ViewModel display scalars → `Equatable`
  `ResolvedPostureTransforms`; RealityKit-free, unit-tested) and a thin
  `@MainActor apply` (builds quaternions, pokes named entities — not
  unit-tested, only forwards into Apple setters). `headOrientation` composes
  yaw·pitch·roll (Y·X·Z).
- **Wired:** `PostureVisualizationView` now owns a `@StateObject`
  `PostureVisualizationViewModel`, binds it to `AppModel` once on appear
  (guarded — `bind(to:)` stacks Combine subscriptions), and re-applies in the
  `RealityView` `update:` closure (re-runs on every `@Published` change).
- **Scene-contract tweaks (DEC-003, confidence 80):** `shoulderTick`
  reparented under `shoulderDisc` so one `disc.orientation` carries the
  direction tick with twist; head rest-Y promoted to shared
  `PostureVisualizationScene.Layout.headCenterY` (sibling of the `EntityName`
  contract; single source, `private Metric` duplicate removed). State colour
  fully retints disc + head fills; dark accents (band, both ticks) untouched
  — richer transitions are Step 5 (DEC-002 still governs the hemisphere).
- **Variable Mapping coverage (design table):** twist→disc Y-rotation,
  lateralLean→head X, headForwardOffset→head Z, forwardCreep→assembly uniform
  scale, yaw/pitch/roll→head Euler quaternion, trackingQuality→
  `OpacityComponent` on the assembly, postureState→`UnlitMaterial` tint. New
  binding constant `metersPerPoint = 0.001` (≤±100 pt → ±0.10 m, inside the
  0.20 m disc radius; tunable per design "tune by eye").
- **API safety:** entire Step-4 RealityKit surface verified against Apple
  docs (Context7) *before* coding — protected the Attempt Ledger from a
  guessed-API compile failure (same discipline as Step 3).
- **Verification:** `xcodebuild build … -scheme Quant -destination
  id=AFD03DDC-…` → **`** BUILD SUCCEEDED **`, exit 0, 0 `error:` lines**
  (Ledger gate; the SourceKit "No such module 'UIKit'/'XCTest'" and "Cannot
  find … in scope" diagnostics were the documented stale-index false
  positive — `mem-1779012223-1e1f` — the compiler resolved everything).
  Focused `xcodebuild test … QuantNoWatchTests
  -only-testing:QuantTests/PostureVisualizationBindingTests
  -only-testing:QuantTests/PostureVisualizationViewModelTests` →
  **`** TEST SUCCEEDED **`, exit 0**: all **8** new binding tests + all
  **17** Step-1 ViewModel tests passed, 0 failures/crashes. `swift test
  --package-path PostureLogic` → **460 / 0** (package untouched).
- **RealityKit Attempt Ledger:** clean scene build **and** done-criteria
  progress ⇒ `attempts` NOT incremented (stays **0/2**); `status: shipped`.
  RealityKit is the shipped renderer → **Step 3F = N/A**.
- **Regressions:** none (additive; only the scaffold↔binding contract Step 4
  owns was touched; no pose-detection / public-API edits — anti-goals
  respected; PostureLogic 460/0 unchanged).
- **Commit:** `feat: bind PostureVisualizationViewModel to RealityKit scene`.

### Step 3 — RealityKit scene scaffold (2026-05-17)

- **Added (2 files, `Quant/Views/Visualization/`):**
  - `PostureVisualizationScene.swift` — value-type-only (`enum` namespace, no
    class → no `@MainActor` isolated-deinit hazard). `@MainActor` static
    factories `makeAssembly()` (shoulder disc cylinder + front tick box;
    head sphere + dark equator band + dark "nose" tick, all named children)
    and `makeCamera()` (`PerspectiveCamera` at ~80° from horizontal via
    `look(at:from:relativeTo:)`). `EntityName` constants are the shared
    scene-graph contract Step 4 will resolve with `findEntity(named:)`.
  - `PostureVisualizationView.swift` — `struct: View` hosting a `RealityView`
    that adds the static assembly + camera. **No ViewModel binding** (Step 4
    owns that — Step 3 kept strictly static per plan).
- **API safety:** RealityKit surface verified against Apple docs via Context7
  *before* writing code: `RealityView { content in }`,
  `MeshResource.generateCylinder(height:radius:)` confirmed **iOS 18.0+**
  (== `IPHONEOS_DEPLOYMENT_TARGET`), `generateSphere`,
  `generateBox(width:height:depth:)`, `UnlitMaterial` via
  `.color = .init(tint:)`, `PerspectiveCamera()` +
  `Entity.look(at:from:relativeTo:)`. This protected the tight Attempt Ledger
  budget from a guessed-API compile failure.
- **Decision DEC-002 (confidence 75, recorded in `.ralph/agent/decisions.md`):**
  true two-tone hemisphere reveal deferred to Step 5 polish — a single-submesh
  generated sphere ignores a 2nd material, so a faithful split needs custom
  mesh/UV work, out of scope for a build-only scaffold. Approximated now with
  a dark equator band + dark nose tick; entities are named so Step 4/5 can
  swap the head's mesh/materials without touching disc/camera/container.
- **Verification:** `xcodebuild build -project Quant.xcodeproj -scheme Quant
  -destination id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5 -quiet` →
  **exit 0, 0 `error:` lines** (the plan's explicit Step 3 gate; both new
  files compiled — synced-folder auto-discovery confirmed). The SourceKit
  "Cannot find 'PostureVisualizationScene'" / "No such module 'UIKit'"
  editor diagnostics were the documented stale-index false positive
  (`mem-1779012223-1e1f`); the compiler resolved everything. `swift test
  --package-path PostureLogic` → **460 / 0** (package untouched).
- **RealityKit Attempt Ledger:** clean scene build **and** done-criteria
  progress ⇒ `attempts` NOT incremented (stays 0/2); `status: in-progress`.
- **Regressions:** none (additive view-only; logic suites unaffected; no
  pose-detection / public-API edits — anti-goals respected).
- **Commit:** `feat: scaffold RealityKit posture visualization scene (static)`.

### Step 2 — Debug harness: `VisualizationDebugView` (2026-05-17)

- **Added:** `Quant/Views/Visualization/VisualizationDebugView.swift` — pure
  SwiftUI throwaway (top comment `// THROWAWAY — delete in Step 6 (plan.md).`).
  Sliders for every input the VM's `ingest(metrics:pose:state:quality:)`
  actually consumes (twist, lateralLean, forwardCreep, headForwardOffset,
  shoulderTwist, shoulder-line-tilt→roll), `PostureState`/`TrackingQuality`
  pickers, a "use live data" toggle, and numeric readouts of **all 10**
  `@Published` outputs (incl. `stateColor` as a swatch, `isCalibrating` glyph).
- **Design decisions (no VM/public-API change — constraint respected):**
  1. Both synthetic and live inputs route through the **same** camera-free
     `ingest(...)` seam (the Step 1 test entry point), so the harness and the
     unit tests validate identical logic; "use live data" only swaps the
     source. Avoids needing a VM `unbind` (no public-API churn / no unrelated
     refactor). Live mode re-pushes via `.onReceive` of AppModel's 4 publishers.
  2. Roll is driven by reconstructing a shoulder pair on the unit circle
     (`left=.zero`, `right=(cosθ,sinθ,0)`) so one slider maps 1:1 to the VM's
     `atan2`-derived roll input (pre 1.5× amplify / ±45 clamp). Exercises the
     heuristic rather than bypassing it.
  3. One Equatable `inputSignature` array → a single `.onChange` re-push,
     instead of ~9 stacked per-control modifiers.
  - `@EnvironmentObject var appModel: AppModel` + `#Preview … .environmentObject`
    follows the repo convention (ContentView/CalibrationSettingsView/etc.).
- **Verification:** app build (plan's explicit Step 2 gate) **SUCCEEDED** —
  `xcodebuild build -scheme Quant -destination
  id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5`, exit 0, 0 `error:` lines. The
  SourceKit "No such module 'PostureLogic'" was a stale-index false positive
  (identical `import PostureLogic` already compiles in Step 1's VM; the actual
  compiler build is clean). `swift test --package-path PostureLogic` →
  **460 / 0 failures** (package untouched, as expected for an app-target-only
  view). No pose-detection / public-API edits.
- **Regressions:** none (UI-only addition; logic suites unaffected).
- **Commit:** `feat: add throwaway VisualizationDebugView for ViewModel validation`.

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
- **Step 2** — Throwaway `VisualizationDebugView` SwiftUI harness (commit
  `feat: add throwaway VisualizationDebugView for ViewModel validation`).
  Verified: app build SUCCEEDED, PostureLogic 460/460, no regression. To be
  deleted in Step 6.
- **Step 3** — RealityKit static scene scaffold: `PostureVisualizationScene`
  (named entity factory) + `PostureVisualizationView` (RealityView + camera),
  static placeholders, no binding (commit `feat: scaffold RealityKit posture
  visualization scene (static)`). Verified: app build exit 0, PostureLogic
  460/460, no regression. Attempt Ledger NOT burned (clean build + progress).
- **Step 4** — `PostureVisualizationBinding` (pure `resolve` + thin `apply`)
  drives the named scene entities from the ViewModel via the `RealityView`
  `update:` closure; view binds the VM to `AppModel`; DEC-003 scene-contract
  tweaks (commit `feat: bind PostureVisualizationViewModel to RealityKit
  scene`). Verified: app build exit 0, 8 new binding tests + 17 ViewModel
  tests pass, PostureLogic 460/460, no regression. Attempt Ledger NOT burned
  (stays 0/2; `status: shipped`).
- **Step 3F** — **N/A — RealityKit shipped.** Trigger condition (Attempt
  Ledger exhausted) never fired: Steps 3 + 4 both clean. SwiftUI fallback
  not built (plan Step 3F status rule: mark N/A and skip). DEC-003.
