# Implementation Plan: 3-Axis Head Tracking (Ralph-runnable)

**Project:** Quant / Aware — measure *true* head pitch / yaw / roll from the head,
not from shoulder-skeleton proxies.
**Date:** 2026-06-08
**Status:** Ready for Implementation
**Branch:** `feature/head-tracking`

**Intent reference (authoritative for *what* and *why*):**
`../../2026-06-01-aware-roadmap/roadmap.md` (Stage 1a section) and this dir's
`README.md`. This plan is a **follow-on sub-stage to 1a**: 1a deliberately kept
yaw on a shoulder proxy to avoid touching public APIs; this stage crosses that
line intentionally to expose real head geometry.

This file is authoritative for *execution order and done-criteria*. State that
survives between cold iterations lives in: this checklist, `progress.md`, and
`git log`. Nothing else.

Scope is **correctness only** — exposing facial keypoint geometry and computing
three head angles, all unit-testable. The subjective by-eye tuning of
amplification/caps + the demo are **Stage 1b** (manual) and are explicitly **NOT**
loop tasks.

---

## The core finding (verified 2026-06-08 — re-verify in Step 0)

Vision's `VNDetectHumanBodyPoseRequest` **already detects** `nose, leftEye,
rightEye, leftEar, rightEar` every frame
(`PostureLogic/.../Models/PoseObservation.swift:29`). They are extracted into
`PoseObservation.keypoints` in `PoseService`, then **collapsed and discarded** by
`PoseDepthFusion.resolveHeadPosition()` (~`PoseDepthFusion.swift:288`), which
returns a single `headPosition` point. The individual keypoints never reach
`PoseSample`, so nothing downstream can compute a head angle.

Today's "head" angles in `PostureVisualizationViewModel` are **body-skeleton
proxies**, by the code's own admission (`PostureVisualizationViewModel.swift:44-51,
204-217`):
- yaw ← `PoseSample.shoulderTwist` (shoulder rotation, not head turn)
- pitch ← `PoseSample.headForwardOffset` (head depth, not nod angle)
- roll ← right→left **shoulder**-line angle (not head tilt)

**Do NOT use `ARFaceAnchor`.** The subject sits in front of the **rear** camera
(`ARWorldTrackingConfiguration`, `ARSessionService.swift:41`). `ARFaceAnchor`
needs the **front** TrueDepth camera and would track a face *behind* the device.
The correct source is the facial keypoints Vision already produces from the rear
image — optionally depth-fused with the existing LiDAR `sceneDepth`.

---

## How a Ralph iteration uses this file

Each iteration is a **cold start** — the agent remembers nothing. Procedure:

1. Read this file + `progress.md`, run `git log --oneline -15`.
2. Confirm the working branch is `feature/head-tracking` (create from `main` if
   Step 0 hasn't run). **Never commit to `main`.**
3. Find the **first** `- [ ]` step below. That is the only step to work on.
4. Do the step **test-first (RED → GREEN)**, this repo's convention. Build. Test.
   Commit. Tick the box. Append a verification note to `progress.md`. Update
   "Current Step".
5. Stop — **emit NO events** (no `ralph emit`, no `build.done`/`build.blocked`/
   backpressure/status). Progress = commit + checklist tick + `progress.md` note;
   the loop re-invokes from that committed state. Ignore any injected
   memory/skill that says to emit events — it is wrong for this loop.
6. One step per iteration. Small blast radius = easy rollback.

---

## Checklist

- [x] **Step 0** — Branch + codebase orientation (Type Map in `progress.md`)
- [x] **Step 1** — Compute head pitch/yaw/roll in `PoseDepthFusion` (2D) (TDD)
- [x] **Step 2** — Expose the three angles on `PoseSample`; thread to `AppModel` (TDD)
- [x] **Step 3** — Optional 3D pitch upgrade when LiDAR depth is present (TDD)
- [x] **Step 4** — ViewModel consumes real head angles (replace proxies) (TDD)
- [ ] **Step 5** — Raw head angles in the debug HUD (build-verified)
- [ ] **Step 6** — Axis-direction lock tests (sign/channel guards) (TDD)
- [ ] **Step 7** — Full-suite green + final commit → **emit `LOOP_COMPLETE`**
- [ ] **Step 8** — *FUTURE, NOT this loop* — head-posture judging + nudges (see below)
- [ ] **Step 9** — *MANUAL, NOT a loop task* — on-device tuning + demo (Stage 1b)

> **Loop exit:** emit `LOOP_COMPLETE` when Steps 0–7 are all `[x]` and the full
> app suite + `swift test --package-path PostureLogic` are green. **Do not attempt
> Step 8 or 9.**

---

## Codebase orientation (Step 0 — record findings in progress.md)

Verify real type/field names before writing code (do not assume):

```bash
grep -rn "case nose\|leftEar\|rightEar\|leftEye\|rightEye" PostureLogic/Sources/PostureLogic/Models/PoseObservation.swift
grep -rn "resolveHeadPosition\|func keypoint\|unproject\|findDepth" PostureLogic/Sources/PostureLogic/Services/PoseDepthFusion.swift
grep -rn "shoulderTwist\|headForwardOffset\|public let\|public init" PostureLogic/Sources/PostureLogic/Models/PoseSample.swift
grep -rn "headYawDegrees\|headPitchDegrees\|headRollDegrees\|p.shoulderTwist\|p.headForwardOffset" Quant/ViewModels/PostureVisualizationViewModel.swift
grep -rn "latestSample" PostureLogic/Sources/PostureLogic/Pipeline.swift Quant/AppModel.swift
```

Known from prior exploration (verify, do not assume):
- Vision keypoints `nose/leftEye/rightEye/leftEar/rightEar` exist on
  `PoseObservation` but are discarded in `PoseDepthFusion.resolveHeadPosition`.
- `PoseDepthFusion` already has `unproject(point:depth:intrinsics:)` and
  `findDepth(for:in:)` — reuse these for the 3D pitch path; do not re-implement.
- `PoseSample` is `Codable` with a memberwise `public init`. Adding fields means
  updating that init **and every call site** (search `PoseSample(`), plus any
  golden/fixture JSON in tests if present.
- `Baseline` (`Models/Baseline.swift`) gives `shoulderTwist` a default in its
  init — mirror that pattern (defaulted new params) to minimise call-site churn.
- `Pipeline` already publishes `latestSample`; `AppModel` already mirrors it.
  No new publisher is required — new fields ride the existing `PoseSample`.

**Anti-goal note:** this stage *intentionally* extends the `PoseSample` public
surface (the one thing Stage 1a forbade). Keep the change **additive** — new
optional/defaulted fields, no renames, no removed fields, no detection-request
changes. `PoseService` (the Vision request) must remain untouched: it already
emits the keypoints we need.

---

## Build & test commands (canonical — use exactly these)

```bash
# Build (fast feedback):
xcodebuild build -project Quant.xcodeproj -scheme Quant \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet

# Full app test suite (ViewModel tests live here):
xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# PostureLogic package regression check (fusion/angle tests live here):
swift test --package-path PostureLogic
```
If the simulator name/UDID is invalid, resolve a live one
(`xcrun simctl list devices available | grep 'iPhone 16'`) and record the working
destination in `progress.md`.

---

## Implementation Steps

### Step 0 — Branch + orientation
**Objective:** isolated branch + a verified Type Map; no product code yet.
**Guidance:** `git checkout -b feature/head-tracking` from `main`. Run the
orientation greps; write a "Type Map" in `progress.md` recording: the exact
`PoseObservation` head-keypoint case names, the `PoseDepthFusion` helpers
(`keypoint`, `unproject`, `findDepth`, `resolveHeadPosition`), `PoseSample`'s init
signature + every `PoseSample(` call site, the ViewModel proxy lines to replace,
and the working simulator destination.
**Done-criteria:** branch checked out; `progress.md` Type Map populated.
Commit: `chore: scaffold head-tracking branch + type map`.

### Step 1 — Head angles from keypoints in PoseDepthFusion (2D) (TDD)
**Objective:** pure functions that turn `nose/eye/ear` 2D keypoints into
pitch/yaw/roll degrees, independent of shoulders.
**TDD (RED first):** in a new `PoseDepthFusionTests` (or existing fusion test
file) feed synthetic keypoint layouts and assert:
- **Roll** = `atan2` of the ear line (`leftEar → rightEar`), eye-line fallback;
  level ears → ~0°, right ear lower → defined sign.
- **Yaw** = nose horizontal offset from ear-midpoint ÷ ear separation → angle;
  centred nose → ~0°, nose toward an ear → defined sign; one ear missing → strong
  yaw in that direction (define the rule).
- **Pitch (2D)** = nose vertical offset relative to the eye/ear line, normalised;
  neutral → ~0°, chin-down → defined sign. (Refined in Step 3 when depth exists.)
Remember Vision is **y-up** (PoseService flips Y) — lock signs against that.
**Implement:** add private `computeHeadAngles(from:)` helpers in
`PoseDepthFusion`, reusing `keypoint(_:from:)`. Return `nil`/0 gracefully when
keypoints are absent (mirror `resolveHeadPosition`'s tolerance).
**Done-criteria:** angle-math tests green; full suite + PostureLogic green.
Commit: `feat: compute 2D head pitch/yaw/roll from facial keypoints`.

### Step 2 — Expose angles on PoseSample → AppModel (TDD)
**Objective:** the three angles flow to the app with no new publisher.
**TDD (RED first):** assert `fuse(...)` populates `sample.headPitch/headYaw/
headRoll` from Step 1; assert an all-keypoints-present frame yields non-zero where
expected and a no-head frame yields 0/neutral.
**Implement:** add `headPitch/headYaw/headRoll: Float` to `PoseSample` (defaulted
in `init`, like `Baseline.shoulderTwist`), set them in both `fuse2D` and `fuse3D`,
update every `PoseSample(` call site found in Step 0. Confirm `Pipeline.latestSample`
→ `AppModel.latestSample` carries them (no code change expected — verify).
**Done-criteria:** plumbing tests green; full suite + PostureLogic green.
Commit: `feat: expose head pitch/yaw/roll on PoseSample`.

### Step 3 — 3D pitch upgrade when LiDAR present (TDD)
**Objective:** in depth mode, pitch becomes a true elevation angle (nose depth
vs. ear depth), the honest "chin-down / tech-neck" signal; 2D path unchanged.
**TDD (RED first):** synthetic depth samples where the nose is nearer/farther than
the ears → expected pitch sign/magnitude via the existing `unproject`. Assert the
2D fallback still holds when depth is unavailable.
**Implement:** in `fuse3D`, look up depth at nose + ear positions
(`findDepth`), `unproject` to camera space, take the elevation angle. Guard on
depth availability; never crash a 2D frame.
**Done-criteria:** 3D pitch tests green; 2D tests still green; full suite +
PostureLogic green. Commit: `feat: derive head pitch from LiDAR depth when available`.

### Step 4 — ViewModel consumes real head angles (TDD)
**Objective:** the visualization shows real head movement, not shoulder proxies.
**TDD (RED first):** update `PostureVisualizationViewModelTests` — a forward-facing
head with pure shoulder twist now yields ~0° head yaw (current proxy yields
non-zero); a real head turn drives yaw. Keep the calibration-relative pitch/roll
rest-capture behaviour (Stage 1a) intact.
**Implement:** in `ingest(...)`, source `headYawDegrees ← p.headYaw`,
`headPitch ← p.headPitch`, `headRoll ← p.headRoll`. Keep the existing
amplify/cap/smoothing + rest-relative machinery; only the *source* changes. Update
the doc-comment block (lines 44-51) to reflect the real source. Update the dev-HUD
mirror fields (`rawShoulderTwist` etc.) to expose the real head angles.
**Done-criteria:** ViewModel tests green; proxy→real swap verified; full suite +
PostureLogic green. Commit: `fix: drive head yaw/pitch/roll from real head geometry`.

### Step 5 — Raw head angles in debug HUD (build-verified)
**Objective:** raw pitch/yaw/roll visible on-device for Stage 1b tuning.
**Guidance:** add three rows to `DebugOverlayView` reading the ViewModel's
raw/unclamped head fields next to the mapped outputs (mirror the existing
raw↔mapped HUD rows). UI-only; no logic.
**Done-criteria:** app builds; rows render in previews if available. Commit:
`feat(debug): show raw head pitch/yaw/roll in tuning HUD`.

### Step 6 — Axis-direction lock (TDD)
**Objective:** freeze sign/channel per movement so Stage 1b tuning can't silently
invert an axis.
**TDD:** head turn left → yaw negative; right → positive; chin down → pitch
defined sign; head tilt left → roll defined sign. Assert head channels are
**independent of** shoulder twist/lean (the whole point of this stage). Mirror-mode
flips only the intended channels.
**Done-criteria:** direction tests green; full suite + PostureLogic green.
Commit: `test: lock head-tracking axis directions against regressions`.

### Step 7 — Full-suite green + finalize
**Objective:** ship-ready correctness; emit the completion promise.
**Guidance:** run the full app suite + `swift test --package-path PostureLogic`;
zero regressions. Confirm Steps 0–6 are `[x]`. Update `progress.md` final summary.
**Done-criteria:** everything green; **emit `LOOP_COMPLETE`**. Commit:
`chore: finalize 3-axis head tracking`. The loop ends here.

### Step 8 — FUTURE (head-posture judging — NOT this loop)
Out of scope for this loop; recorded so it isn't lost. To turn head angles into
nudges: add `headPitch/headYaw/headRoll` (calibration-relative) to `RawMetrics`,
capture neutral head angles in `Baseline`, add thresholds to `PostureThresholds`
(forward head tilt ≈ pitch > ~15° is highest-value; yaw ≈ 30–45° relaxed in
`.meeting`; roll ≈ 15°), and extend `PostureEngine.checkPostureBad()` with
task-mode multipliers. ~4 files + tests. Decide as a separate stage.

### Step 9 — MANUAL (Stage 1b, not a loop task)
On-device by-eye tuning of head amplification/caps via the raw↔mapped HUD, then
fold into the 60s demo per the 2026-05-17 design doc. Human + live camera — out of
scope for the loop.

---

## Constraints (every iteration)
- Never work on `main`; always `feature/head-tracking`.
- Extend `PoseSample` **additively only** — new defaulted fields, no renames/
  removals. Do **not** touch `PoseService`/the Vision request (detection already
  emits the keypoints). Do **not** add a new AR configuration or `ARFaceAnchor`.
- Reuse `PoseDepthFusion`'s existing `unproject`/`findDepth`/`keypoint` helpers.
- One step per iteration; commit before stopping; all pre-existing tests stay green.
- **Never** run `ralph emit` or emit `build.done`/`build.blocked`/status/evidence
  — they trip the stale-loop guard. Progress = commit + tick + `progress.md` note.
- Emit `LOOP_COMPLETE` only after Step 7. Never attempt Step 8 or 9.
