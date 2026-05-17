# Progress: Posture Visualization

> Mutable loop state. Every iteration reads this first and appends to it before
> stopping. This file + `plan.md`'s checklist + `git log` are the **only**
> memory that survives a cold iteration.

## Current Step

**✅ COMPLETE — Steps 0–6 all `[x]` (Step 3F = N/A — RealityKit shipped).
`LOOP_COMPLETE` emitted. The loop ends here.**

> Step 6 (cleanup, full-suite green, final commit) **shipped** (commit
> `chore: remove debug harness; finalize posture visualization`). The Step 2
> throwaway `VisualizationDebugView.swift` is deleted; the full app suite
> (`** TEST SUCCEEDED **`, 377 cases, 0 fail / 0 crash / 0 error) and
> `swift test --package-path PostureLogic` (460/0) are green with no
> regressions. Plan checklist Steps 0–6 are `[x]`, Step 3F `[N/A]`. All loop
> scope (Steps 0–6) is satisfied.
>
> **Step 7 (device test + 60 s demo recording) is NOT a loop task** — it needs
> a physical device with a live camera + a human operator. It remains
> `[ ]` in the checklist by design and is verified manually after
> `LOOP_COMPLETE`, per the plan's Step 7 note.

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

### Recovery — terminal-state re-verification (2026-05-17)

- **Trigger:** `task.resume` recovery event — the prior iteration completed
  and committed Step 6 (`70a6de6 chore: remove debug harness; finalize posture
  visualization`) but the loop never received the `LOOP_COMPLETE` token. Per
  the recovery instruction, this iteration re-verifies the committed terminal
  state rather than redoing work (loop SoT = files + git).
- **Re-verified (cold start, no work redone):**
  - Branch `feature/posture-visualization`, `git status` clean, HEAD =
    `70a6de6` (the exact Step 6 commit: deletes the 218-line throwaway, ticks
    `plan.md` Step 6, appends the Step 6 note).
  - `plan.md:37–44` — Steps 0–5 `[x]`, Step 3F `[N/A — RealityKit shipped]`,
    Step 6 `[x]`; Step 7 `[ ]` by design (manual, out of loop scope).
  - Throwaway `VisualizationDebugView.swift` absent from tree; **0** `.swift`
    source references. Production `PostureVisualizationView` intact and wired
    at `ContentView.swift:155` (Step 5 entry — stays, per plan).
  - **`swift test --package-path PostureLogic` re-run live: 460 / 0** (package
    untouched ⇒ no regression — independent live confirmation).
  - Full app suite: committed Step 6 note records `** TEST SUCCEEDED **`
    377 / 0 / 0 / 0 at this exact (now-clean) commit; surviving
    `/tmp/quant_step6_fulltest.log` tail corroborates `** TEST SUCCEEDED **`.
    Tree is byte-identical to the verified SHA, so the result is unchanged by
    construction — no re-run needed.
- **Outcome:** every "## Completion" criterion satisfied and corroborated.
  `LOOP_COMPLETE` re-emitted. No product code touched (docs-only recovery
  note); Step 7 remains unattempted (physical device + human).

### Step 6 — Cleanup, full-suite green, final commit (2026-05-17)

- **Pre-flight (deletion safety):** `grep -rn VisualizationDebugView`
  matched **only** the 3 planning/design docs + the throwaway file itself —
  **no source file** imports or instantiates it. This confirms the Step 5
  note: the harness was never wired into navigation, so there is **no
  debug-only nav entry point to remove**. Step 5's *production*
  `PostureVisualizationView` entry in `ContentView` does **not** reference
  `VisualizationDebugView` and **stays** (verified: absent from the grep
  match set). File header reconfirmed `// THROWAWAY — delete in Step 6`.
- **Action:** `git rm Quant/Views/Visualization/VisualizationDebugView.swift`
  (the Step 2 throwaway; sole change this step besides plan/progress
  bookkeeping). No other debug-only entry points existed.
- **Full app suite (Step 6 gate — the *whole* suite, not focused):**
  `xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests
  -destination id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5` →
  **`** TEST SUCCEEDED **`**, exit 0. **377 cases passed, 0 failed,
  0 `Test crashed with signal`, 0 `error:`**. The pre-existing `@MainActor`
  back-deploy-deinit SIGABRT stays **resolved** with the harness removed
  (zero crash lines). All posture-viz tests pass *inside the full parallel
  run*: `PostureVisualizationViewModelTests` 17/17 +
  `PostureVisualizationBindingTests` 10/10 (7 resolve/binding + 3 Step-5
  `stateTint`). Full log: `/tmp/quant_step6_fulltest.log`.
- **PostureLogic regression:** `swift test --package-path PostureLogic` →
  **460 / 0** (package untouched, unchanged from every prior step).
- **Checklist:** Steps 0–5 all `[x]`, Step 3F `[N/A — RealityKit shipped]`,
  Step 6 now `[x]`. Step 7 intentionally left `[ ]` (manual, out of loop
  scope per plan).
- **Regressions:** none — the only product change is the deletion of a
  throwaway dev-only screen with zero references; full suite + PostureLogic
  green, no pose-detection / public-API edits (anti-goals respected).
- **Commit:** `chore: remove debug harness; finalize posture visualization`.
- **Loop terminus:** Steps 0–6 satisfied, full suite + package green, debug
  harness gone ⇒ `LOOP_COMPLETE` emitted. The loop ends here; **Step 7 is
  never attempted** (physical device + human).

### Step 5 — Integration & polish (2026-05-17)

- **Navigation (done-criterion 1):** `Quant/ContentView.swift` — added
  `@State showVisualization`, a `cube.transparent` button in the existing
  button row, and a `.fullScreenCover` presenting `PostureVisualizationView`.
  Mirrors the **proven** `VariantShowcaseView` precedent: `AppModel` is
  injected once at the `WindowGroup` root (`QuantApp.swift:17
  .environmentObject(appModel)`) and propagates into the cover, so
  `PostureVisualizationView`'s `@EnvironmentObject` resolves without
  re-injection (same pattern `VariantShowcaseView` already relies on). Added
  `@Environment(\.dismiss)` + a top-trailing `xmark.circle.fill` close button
  (full-screen covers carry no default chrome).
- **Calibrating pulse + continuous re-apply:** `PostureVisualizationView`
  wraps `RealityView` in `TimelineView(.animation)`. `RealityView` keeps its
  structural identity across timeline ticks → scene built **once** (`make`),
  only re-bound (`update`) per tick (Apple-documented SwiftUI↔RealityKit
  animation pattern; DEC-004, confidence 80). A pure wall-clock sine
  `pulse∈0…1` (period 1.6 s, no stored state) is threaded into
  `PostureVisualizationBinding.apply(_:to:pulse:)` (new defaulted param —
  source-compatible). The VM's α=0.2 low-pass, now applied every frame, is
  the "smooth ~0.3 s ease" mechanism (no risky RealityKit `move()` API
  introduced; `content.animate` from a prior memory note does **not** exist
  as an API — the TimelineView approach replaces it).
- **Testable colour polish (done-criterion 2):** new **pure**
  `PostureVisualizationBinding.stateTint(stateColor:isCalibrating:pulse:)` —
  judged states pass the VM hue straight through (unchanged: `.green` /
  `.orange` / `.red`); `calibrating` breathes grey *luminance* between
  `pulseGreyMin 0.35` and `pulseGreyMax 0.85` (hue fixed). The VM's discrete
  colour mapping is **not** modified (Step 1 tests assert `.green/.orange/.red`
  — `stateTint` *consumes* `stateColor`, never changes it). +3 headless
  `PostureVisualizationBindingTests`: four states pairwise-distinct, pulse
  modulates brightness-not-hue, non-calibrating ignores pulse. Added a private
  `rgba` helper mirroring the `PostureVisualizationViewModelTests` convention.
- **Baseline ghost:** `PostureVisualizationScene.makeGhost()` +
  `EntityName.ghost` — a faint (`OpacityComponent` 0.15) static disc+head at
  the calibrated rest pose, added as a **separate scene root**. `apply` only
  resolves entities under `EntityName.assembly`, so the ghost is never moved /
  scaled / retinted: live deviation reads against the fixed baseline. Reuses
  only already-shipped RealityKit API (`generateSphere/Cylinder`,
  `UnlitMaterial`, `OpacityComponent`) — no new surface, Step 5 isn't
  Attempt-Ledger-gated regardless.
- **Verification:** `xcodebuild build … -scheme Quant -destination
  id=AFD03DDC-…` → **`** BUILD SUCCEEDED **`, 0 `error:` lines** (every
  SourceKit "No such module 'UIKit'/'XCTest'/'PostureLogic'" / "Cannot find
  'AppModel' in scope" was the documented stale-index false positive
  `mem-1779012223-1e1f` — the compiler resolved all). Focused
  `xcodebuild test … QuantNoWatchTests
  -only-testing:QuantTests/PostureVisualizationBindingTests
  -only-testing:QuantTests/PostureVisualizationViewModelTests` →
  **`** TEST SUCCEEDED **`, 0 failures/crashes**: 3 new Step-5 tests + the 8
  Step-4 binding tests + 17 Step-1 ViewModel tests all passed. `swift test
  --package-path PostureLogic` → **460 / 0** (package untouched).
- **Regressions:** none (additive; only the posture-viz surface Step 5 owns —
  ContentView nav, the view, the scene factory, the binding tint — was
  touched; no pose-detection / public-API edits — anti-goals respected;
  PostureLogic 460/0 unchanged).
- **Commit:** `feat: integrate posture visualization with state polish`.

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
- **Step 5** — Integration & polish: `ContentView` nav entry +
  `.fullScreenCover`; `TimelineView`-driven calibrating pulse; pure
  `PostureVisualizationBinding.stateTint`; `PostureVisualizationScene.makeGhost`
  baseline; +3 headless tests (commit `feat: integrate posture visualization
  with state polish`). Verified: app build exit 0, focused QuantTests
  (3 new + 8 binding + 17 VM) `** TEST SUCCEEDED **` 0 fail, PostureLogic
  460/0, no regression. DEC-004.
- **Step 6** — Cleanup & finalize: deleted the Step 2 throwaway
  `VisualizationDebugView.swift` (zero source refs — never nav-wired; the
  Step 5 production `PostureVisualizationView` entry stays), ran the **full**
  app suite + PostureLogic (commit `chore: remove debug harness; finalize
  posture visualization`). Verified: `** TEST SUCCEEDED **` 377/0/0
  (0 fail / 0 crash / 0 error), PostureLogic 460/0, no regression. Steps 0–6
  `[x]`, 3F `[N/A]` ⇒ **`LOOP_COMPLETE`**. **Loop ends — Step 7 (device +
  human) intentionally not attempted.**
