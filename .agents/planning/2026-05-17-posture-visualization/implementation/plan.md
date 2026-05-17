# Implementation Plan: Posture Visualization (Ralph-runnable)

**Project:** Quant — 3D Posture Visualization for LinkedIn demo
**Date:** 2026-05-17
**Status:** Ready for Implementation
**Branch:** `feature/posture-visualization`

**Design / intent reference (authoritative for *what* and *why*):**
- `../design/build-plan.md`

This file is authoritative for *execution order and done-criteria*. The Ralph
loop driver is the repo-root `PROMPT.md`. State that survives between cold
iterations lives in: this checklist, `progress.md`, and `git log`. Nothing else.

---

## How a Ralph iteration uses this file

Each iteration is a **cold start** — the agent remembers nothing. Procedure:

1. Read this file + `progress.md`, run `git log --oneline -15`.
2. Confirm the working branch is `feature/posture-visualization`.
3. Find the **first** `- [ ]` step below. That is the only step to work on.
4. If that step is RealityKit (Step 3 or 4), first check the **RealityKit
   Attempt Ledger** in `progress.md` — see Step 3 for the budget rule.
5. Do the step. Build. Test. Commit. Tick the box. Append a verification note
   to `progress.md`. Stop (the loop re-invokes for the next step).
6. One step per iteration. Small blast radius = easy rollback.

---

## Checklist

- [x] **Step 0** — Branch + folder scaffolding
- [x] **Step 1** — Data layer: `PostureVisualizationViewModel` (TDD)
- [ ] **Step 2** — Debug harness: `VisualizationDebugView`
- [ ] **Step 3** — RealityKit scene scaffold (placeholder entities, build-only)
- [ ] **Step 4** — Bind ViewModel → entity transforms
- [ ] **Step 3F** — *Conditional* SwiftUI fallback (only if RealityKit budget blown — see Step 3)
- [ ] **Step 5** — Integration & polish (navigation, colour transitions, ghosts, animation)
- [ ] **Step 6** — Cleanup, full-suite green, final commit → **emit `LOOP_COMPLETE`**
- [ ] **Step 7** — *MANUAL, NOT a loop task* — device test + 60s demo recording

> **Loop exit:** emit `LOOP_COMPLETE` when Steps 0–6 are all `[x]` (Step 3F may
> be `[x]` *or* explicitly marked `[N/A]` in `progress.md`) **and** the full
> test suite is green. **Do not attempt Step 7** — it requires physical
> hardware with a live camera; a Mac CI loop cannot do it.

---

## Codebase orientation (do this once, in Step 0 — record findings in progress.md)

Cold-start agents do not know the layout. Before writing code, verify the real
type/field names (the design doc's names may not match the codebase exactly):

```bash
grep -rn "struct RawMetrics" Quant/ PostureLogic/
grep -rn "enum PostureState" Quant/ PostureLogic/
grep -rn "TrackingQuality" Quant/ PostureLogic/ | head
grep -rln "AppModel" Quant/ | head
grep -rn "VNHumanBodyPoseObservation\|PoseObservation" Quant/ | head
```

Known from prior work (verify, do not assume): `RawMetrics` has fields
`forwardCreep, headDrop, shoulderRounding, lateralLean, twist`. The design doc
references `headForwardOffset` — **if no such field exists, map the design's
`headForwardOffsetPoints` from the nearest real field (likely `headDrop` or
`forwardCreep`) and record the substitution in `progress.md`.** Do not invent
new detection logic (design anti-goal).

---

## Build & test commands (canonical — use exactly these)

```bash
# Build (fast feedback):
xcodebuild build -project Quant.xcodeproj -scheme Quant \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet

# Full app test suite (the new ViewModel tests live here):
xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests \
  -destination 'platform=iOS Simulator,id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5'

# PostureLogic package regression check:
swift test --package-path PostureLogic
```

If the simulator UDID is invalid, resolve a live one and use it:
`xcrun simctl list devices available | grep 'iPhone 16'`. Record the working
destination in `progress.md` so later iterations reuse it.

---

## Implementation Steps

### Step 0 — Branch + folder scaffolding

**Objective:** Establish an isolated branch and the directory skeleton so all
later steps have a home. No product code yet.

**Guidance:**
1. `git checkout -b feature/posture-visualization` (if it already exists,
   `git checkout` it; never work on `main`).
2. Create `Quant/ViewModels/` and `Quant/Views/Visualization/` with a
   `.gitkeep` in each (Xcode 16 synced folders pick up files automatically;
   no `.pbxproj` editing needed for new source files in synced groups —
   verify this assumption by checking how `Quant/PostureUI/` is referenced).
3. Run the **Codebase orientation** grep block above; write a "Type Map"
   section in `progress.md` recording the real names/fields of `RawMetrics`,
   `PostureState`, `TrackingQuality`, the `AppModel` publisher(s), and how
   pose keypoints (ears/nose/eyes) are exposed.

**Done-criteria:** branch exists and is checked out; both folders exist and are
committed; `progress.md` has a populated "Type Map". Commit:
`chore: scaffold posture-visualization branch and folders`.

---

### Step 1 — Data layer: `PostureVisualizationViewModel` (TDD)

**Objective:** Framework-agnostic ViewModel computing all display values. This
is the highest-value loop step — pure logic, fully unit-testable. **Do not
touch existing pose-detection code** (design anti-goal).

**TDD (RED → GREEN, matching this repo's convention):**
1. Write `QuantTests/PostureVisualizationViewModelTests.swift` **first**.
   Cover with synthetic inputs (no camera):
   - Yaw: nose offset from ear-midpoint / ear separation → expected degrees.
   - Pitch: nose-to-ear-midpoint vertical / eye-to-eye scale; assert cap ±60°.
   - Roll: angle of left-ear→right-ear line; assert cap ±45°.
   - Low-pass filter: feed a step input, assert α=0.2 exponential approach.
   - Scaling/clamping: `twist→shoulderRotationDegrees` (1.5×),
     `lateralLean→sideLeanOffsetPoints` (100pt/unit),
     `forwardCreep→assemblyScale` (1 + creep×0.5).
   - `PostureState → stateColor` discrete mapping (all 4 states distinct).
   - `isCalibrating` true iff state is the calibrating case.
   - `trackingQuality → opacity` mapping.
   Run tests, confirm they FAIL to compile/assert (RED).
2. Implement `Quant/ViewModels/PostureVisualizationViewModel.swift`:
   `@MainActor final class … : ObservableObject` with the **9 `@Published`
   properties** named exactly as in the design doc. Inject inputs via a
   testable seam (e.g. `func ingest(raw:pose:state:quality:)` plus a Combine
   subscription to `AppModel` behind it) so tests drive it without a camera.
3. Re-run focused tests → GREEN. Run full suite → no regressions.

**Done-criteria:** all 9 published properties exist and are covered by passing
tests; full app suite + `swift test --package-path PostureLogic` green; no
edits to pose-detection source. Commit:
`feat: add PostureVisualizationViewModel with heuristics + tests`.

---

### Step 2 — Debug harness: `VisualizationDebugView`

**Objective:** A throwaway SwiftUI screen proving the ViewModel behaves across
the full input range. Deleted in Step 6.

**Guidance:** `Quant/Views/Visualization/VisualizationDebugView.swift` — a
slider per input variable + a "use live data" toggle + numeric readouts of all
9 outputs. Pure SwiftUI; no RealityKit. Mark the file with a top comment:
`// THROWAWAY — delete in Step 6 (plan.md).`

**Done-criteria:** builds; readouts wired to a `PostureVisualizationViewModel`.
Commit: `feat: add throwaway VisualizationDebugView for ViewModel validation`.

---

### Step 3 — RealityKit scene scaffold (placeholder entities, build-only)

**Objective:** `PostureVisualizationView` (a `RealityView`) +
`PostureVisualizationScene` with shoulder disc, head sphere (two-tone
hemispheres), tick markers, camera at ~80° — **static placeholders, no live
binding yet**. Per design doc Phase 3.

**RealityKit Attempt Ledger (this replaces the human "6-hour" time-box):**
The original spec is emphatic — "Stop. Don't keep grinding." A cold-start loop
has no wall clock, so the budget is deliberately tight:

- `progress.md` holds a `### RealityKit Attempt Ledger` with `attempts:`
  (starts at 0), `budget: 2`, and `last_error_class:`.
- An iteration on Step 3 **or** Step 4 increments `attempts:` by 1 and logs
  the blocking error **unless** it ends with **both** (a) a clean build of the
  RealityKit scene **and** (b) demonstrable progress against that step's
  done-criteria. "Compiles but no functional progress" **still burns budget** —
  this closes the stall loophole where trivially-empty scaffolds never count.
- **Repeated identical failure = immediate bail.** Record each attempt's error
  class in `last_error_class:`. If this iteration's blocking error matches the
  previous attempt's `last_error_class:`, treat the budget as exhausted **now**,
  regardless of the counter — the loop is stuck and another pass won't help.
- **When `attempts:` reaches `budget` (2), OR the repeat-failure rule fires**,
  before Step 4 is `[x]`: stop pursuing RealityKit. Run
  `git tag wip/realitykit-vis`, mark Steps 3 and 4
  `[N/A — RealityKit budget exhausted]` in this checklist, set Step 3F as the
  active path, and record the decision in `progress.md`. Do **not** keep
  grinding RealityKit after the budget is spent.
- A clean build that **advances** the step does **not** increment the counter.

**Done-criteria:** RealityKit scene builds and renders static placeholder
entities (verified by a successful `xcodebuild build`). Commit:
`feat: scaffold RealityKit posture visualization scene (static)`.

---

### Step 4 — Bind ViewModel → entity transforms

**Objective:** In the `RealityView` `update` closure, drive entity transforms
from the ViewModel per the design doc's Variable Mapping table (disc rotation,
head position/Euler angles, anchor scale, material colour, opacity).

**Guidance:** Subject to the same Attempt Ledger as Step 3. Keep all mapping
constants in one place (mirror the ViewModel's scaling so they stay tunable).

**Done-criteria:** scene builds; transforms provably bound (a brief unit or
snapshot-free assertion that the mapping function returns expected transforms
for sample ViewModel values is acceptable — full visual proof is Step 7,
manual). Commit: `feat: bind PostureVisualizationViewModel to RealityKit scene`.

---

### Step 3F — Conditional SwiftUI fallback

**Status rule:** Work this step **only if** the Attempt Ledger triggered
(Steps 3/4 marked `[N/A]`). Otherwise mark this step
`[N/A — RealityKit shipped]` in the checklist + `progress.md` and skip it.

**Objective (if triggered):** `VisualizationFallbackView.swift` — SwiftUI-only:
`Ellipse()` shoulder w/ `.rotationEffect`, `Circle()` head, `Capsule()` tick
with `.rotationEffect` (roll) + `.offset` (yaw/pitch). No hemisphere reveal —
accepted trade-off. Wire to the **same** `PostureVisualizationViewModel`.

**Done-criteria:** builds; bound to the ViewModel. Commit:
`feat: add SwiftUI fallback visualization (RealityKit budget exhausted)`.

---

### Step 5 — Integration & polish

**Objective:** Make whichever renderer shipped (RealityKit *or* fallback)
demo-ready.

**Guidance:**
- Wire the visualization into app navigation (alongside `DebugOverlayView` —
  grep for it to find the navigation site).
- State-driven colour transitions: calibrating (pulsing grey), good (green),
  drifting (amber), bad (red).
- Baseline "ghost" duplicates at calibrated positions (faint).
- Smooth transforms (~0.3s ease) so motion reads well on video.

**Done-criteria:** visualization reachable from app navigation; four states
visibly distinct in code (colour values asserted in a small test if practical);
build green. Commit: `feat: integrate posture visualization with state polish`.

---

### Step 6 — Cleanup, full-suite green, final commit

**Objective:** Ship-ready tree; emit the loop-completion promise.

**Guidance:**
1. Delete `VisualizationDebugView.swift` (the Step 2 throwaway) and any
   debug-only navigation entry points.
2. Run the **full** app suite + `swift test --package-path PostureLogic`.
   Everything green, zero regressions.
3. Confirm every checklist item Step 0–5 is `[x]` (or Step 3F `[N/A]`).
4. Commit: `chore: remove debug harness; finalize posture visualization`.
5. Update `progress.md` final summary, then **emit `LOOP_COMPLETE`**.

**Done-criteria:** debug harness gone; full suite green; `LOOP_COMPLETE`
emitted. **The loop ends here.**

---

### Step 7 — MANUAL (not a loop task)

Device test + 60-second demo recording per the design doc's "Demo Recording
Notes". Requires a physical device with a live camera and a human operator —
**out of scope for the Ralph loop**, documented here only so it isn't lost.
Acceptance criteria in the design doc marked "on device" are verified here, by
a human, after `LOOP_COMPLETE`.

---

## Constraints (apply every iteration)

- Never work on `main`; always `feature/posture-visualization`.
- Do **not** modify existing pose-detection logic or public APIs (design
  anti-goal: "no new posture detection logic").
- One step per iteration; commit before stopping.
- All pre-existing tests must stay green.
- Respect the RealityKit Attempt Ledger — do not grind past the budget.
- Emit `LOOP_COMPLETE` only after Step 6. Never attempt Step 7.
