# Progress: Posture Visualization

> Mutable loop state. Every iteration reads this first and appends to it before
> stopping. This file + `plan.md`'s checklist + `git log` are the **only**
> memory that survives a cold iteration.

## Current Step

**Step 1 — Data layer: `PostureVisualizationViewModel` (TDD)** _(not started; Step 0 complete)_

## Working environment (fill in during Step 0, reuse thereafter)

- Verified simulator destination: _(TBD — resolve in Step 1; plan default
  `platform=iOS Simulator,id=AFD03DDC-D5CC-4B24-97A8-94889AB854A5`, else
  `xcrun simctl list devices available | grep 'iPhone 16'`)_
- Branch confirmed: `feature/posture-visualization` (already existed + checked
  out at HEAD `01c0aa7`; never committed to `main`).

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

## Verification Notes

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
