# Head Quaternion Passthrough — faithful Front (Face) head playback

**Goal.** Remove the figure head's two symptoms — "snaps to extremes" and "dips
twice on a level left↔right turn" — at the root, by driving the head from
ARKit's **quaternion** end-to-end instead of decomposing it into three Euler
angles and re-amplifying one of them per-axis.

**Why.** On a real seated Front (Face) turn, the device measures
`rawPitch` swinging `0 → −15°` (even, both extremes, phone-tilt-independent):
the `taitBryanZYXDegrees` decomposition leaks yaw→pitch, and the ×−6 pitch gain
(applied past the cap, see "Already landed") magnifies it. A quaternion carried
through with a single uniform gain + one clamp has no per-axis channel to leak
into, so the dip is gone *by construction*.

This plan is chunked so **each task is one agent, one small file-set, low
context**. Read the **Common brief** once, then a single task — that is all an
agent needs.

---

## Common brief (paste into every task agent)

- **Repo:** `/Users/learning/Developer/Quant`. Branch `usdz-figure-pipeline`.
  Remote `dwpope`. The nightly automated-build agent also pushes this branch —
  `git fetch origin usdz-figure-pipeline` before any push; **commit/push only
  when the human asks.**
- **Authoritative checks:** PostureLogic package → `swift test` (run in
  `PostureLogic/`). App → `xcodebuild -scheme Quant -destination
  'generic/platform=iOS Simulator' build`. **SourceKit is unreliable here**
  (false "No such module" errors) — ignore in-editor diagnostics; trust the CLI.
  Pipe build output through `grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"` to
  stay lean.
- **Hard invariant:** head angles/orientation are **viz-only** — they must
  **never** feed `PostureEngine` scoring (scoring is fully 2D:
  forwardCreep/twist/lateralLean/headDrop/shoulderRounding). Do not touch
  metrics/scoring.
- **Figure frame is Blender Z-up** (the USDZ Y-up conversion sits on `/root`, so
  head/torso entities below are Z-up): **yaw=+Z (up), pitch=+X (left-right),
  roll=+Y (front)**. Not the RealityKit Y-up default.
- **Don't stage** `.claude/agent-memory/**` into any commit.
- **The data flow today (Front Face, Tier 1):**
  `ARFaceAnchor.transform` → `HeadOrientationDecomposition.taitBryanZYXDegrees`
  → `HeadAngles(pitch,yaw,roll)` → `InputFrame.externalHeadAngles`
  → `PoseService` → `PoseObservation.externalHeadAngles`
  → `PoseDepthFusion.computeHeadAngles` (Tier 1 returns it verbatim)
  → `PoseSample.headPitch/Yaw/Roll: Float` (degrees)
  → `PostureVisualizationViewModel.ingest` (One Euro + ×1.5 amp + ±cap)
  → `PostureVisualizationBinding.resolve/apply` (deadzone+scale+fade+×−6/−3/−0.6
  gains + `headOrientation()` Euler→quat recompose) → `DampedOrientation` follow.
- **Key files:**
  - `PostureLogic/Sources/PostureLogic/Models/{InputFrame,PoseObservation,PoseSample}.swift`
  - `PostureLogic/Sources/PostureLogic/Services/{HeadOrientationDecomposition,PoseDepthFusion,DampedOrientation}.swift`
  - `Quant/Services/{ARFaceTrackingService,PoseService… (PoseService is in PostureLogic)}`
  - `Quant/ViewModels/PostureVisualizationViewModel.swift`
  - `Quant/Views/Visualization/PostureVisualizationBinding.swift`
  - `Quant/Views/Visualization/PostureVisualizationCalibrationOverlay.swift`
  - `Quant/Views/Visualization/PostureVisualizationDevNotes.swift`
- **Design rule:** the new quaternion path is **additive and gated on quaternion
  presence** (= Front Face). When the quaternion is nil (non-TrueDepth / 2D /
  dropout) the existing Euler path is unchanged — zero regression for that mode.

### Already landed (baseline, uncommitted)
`PostureVisualizationBinding.swift` has a **post-gain render clamp**
(`headRenderPitchCapRadians=55°`, `headRenderRollCapRadians=35°`, applied to the
gained pitch/roll right before `headOrientation()`). It fixes the *snap*. Leave
it in place; the quaternion path will supersede the Euler gains but the clamp
concept carries over (Task R3 has its own angle clamp).

---

## Two tracks

- **Track B — Structural (R1→R6): THE PRIORITY — the actual fix.** The quaternion
  passthrough. Ordered; R2 and R3 run in parallel after R1.
- **Track A — Optional, do SECOND (1 task):** bakes today's live-dialed slider
  values into the *legacy Euler / fallback* path. Independent of B and **largely
  moot once R4 ships** (B supersedes those gains for Front Face) — skip unless you
  want a better stopgap before B lands, or the non-TrueDepth fallback tuned.

Dependency graph:
```
A1  (optional — independent; run SECOND, or skip once R4 lands)
R1 ──┬── R2 ──┐
     └── R3 ──┴── R4 ── R5 ── (R6 commit, human-gated)
```

---

## TRACK B (priority)

### R1 — Model: add the quaternion channel (PostureLogic, pure)
- **Context:** Common brief + the three model files + `HeadOrientationDecomposition.swift` + their tests.
- **Change:**
  1. `InputFrame`: add `externalHeadOrientation: simd_quatf?` (default nil),
     parallel to `externalHeadAngles` (non-Codable, app→pipeline channel).
  2. `PoseObservation`: same optional field, threaded the same way as
     `externalHeadAngles`.
  3. `PoseSample`: add `headOrientation: SIMD4<Float>?` (xyzw, default nil).
     **Codable-safe** (`SIMD4<Float>` is Codable) — this is the recorded/replay
     boundary, so verify encode/decode round-trips. Keep the existing
     `headPitch/Yaw/Roll` fields untouched (fallback + scoring-irrelevant compat).
  4. `HeadOrientationDecomposition`: add a pure helper that returns the
     **orthonormalized screen-frame rotation as `simd_quatf`** (the same
     `portraitFixUp * orthonormalUpperLeft(inverse(camera)*head)` matrix the
     Euler version decomposes) so the source can stamp the quaternion without
     re-deriving it. Do **not** change `taitBryanZYXDegrees`.
- **Contract:** new fields default nil ⇒ every existing test and the 2D path are
  unaffected.
- **Accept:** `swift test` green; add (a) a Codable round-trip test for
  `PoseSample.headOrientation`, (b) a test that the new quat helper agrees with
  `taitBryanZYXDegrees` (decompose the quat → same yaw/pitch/roll).
- **Don't:** touch metrics/scoring, fusion math, or the Euler fields' meaning.

### R2 — Source: stamp the quaternion (app + PoseService)
- **Depends on:** R1. **Context:** Common brief + `ARFaceTrackingService.swift` +
  `PoseService.swift` + `PoseDepthFusion.swift`.
- **Change:**
  1. `ARFaceTrackingService`: alongside the existing `HeadAngles`, compute the
     screen-frame quaternion via R1's helper and set
     `InputFrame.externalHeadOrientation`.
  2. `PoseService`: thread `externalHeadOrientation` → `PoseObservation`.
  3. `PoseDepthFusion`: when `externalHeadOrientation` is present (Tier 1), pass
     it onto `PoseSample.headOrientation` (as `SIMD4`); leave nil otherwise
     (2D/dropout → Euler fallback path stays as-is).
- **Contract:** Face mode ⇒ `PoseSample.headOrientation` non-nil; all other modes
  nil. No change to `headPitch/Yaw/Roll`.
- **Accept:** `swift test` green (fusion tests); `xcodebuild … build` SUCCEEDED.
  App-layer stamping isn't unit-tested — rely on R1's pure helper test + build.
- **Don't:** let any `ARFrame`/`ARFaceAnchor` escape `ARFaceTrackingService`
  (existing rule); don't alter the Euler stamping.

### R3 — Pure render math: remap + uniform gain + rest-relative + clamp (PostureLogic, pure)
- **Depends on:** R1 (uses the quat type). Can run **parallel to R2**.
  **Context:** Common brief + one new file + its test file. No app code.
- **Change:** new pure value type `HeadOrientationRender` (PostureLogic/Services)
  composing, in order:
  1. **Rest-relative:** `qRel = qRest.inverse * qHead` (neutral → identity).
  2. **Uniform gain:** scale the rotation angle via axis-angle / log-map:
     `qGained = rot(axis(qRel), gain * angle(qRel))`. `gain=1` ⇒ faithful.
     One scalar replaces the per-axis ×−6/−3/−0.6 anisotropy (that anisotropy was
     the bug).
  3. **Clamp:** cap `angle(qGained)` to `maxAngle` (axis preserved). One angle
     ceiling instead of three Euler caps.
  4. **Basis remap to the figure Z-up frame:** conjugation by a **fixed** basis
     `B`: `qFigure = B * qGained * B.inverse`. Expose `B` (or an axis-map +
     3 sign flags) as parameters — these are **DEVICE-CONFIRM**, mirroring the
     Euler `portraitFixUp` + 3 gain signs. Provide a sensible default to be
     dialed in R5.
- **THE invariant test (the proof the dip is gone):** for any fixed `B` and a
  swept single-axis input `q(θ)=rot(a, θ)` (θ over a turn range, with a fixed
  head-vs-camera offset baked into `qRest`/`a`), assert the **output rotations
  are all about ONE fixed axis** — i.e. decomposing `qFigure(θ)` to Euler yields
  `|pitch|,|roll| < 1e-3°` for every θ. Conjugation preserves single-axis ⇒ this
  passes exactly. Also test: `gain=1` ⇒ output angle == input angle;
  `maxAngle` clamps; `qRest` ⇒ neutral renders identity.
- **Accept:** `swift test` green incl. the invariant test.
- **Don't:** import RealityKit/UIKit/ARKit (must stay headless-pure).

### R4 — Binding + ViewModel: use the quaternion path in `apply`
- **Depends on:** R2 + R3. **Context:** Common brief +
  `PostureVisualizationViewModel.swift` + `PostureVisualizationBinding.swift`
  (+ R3's type signature).
- **Change:**
  1. `PostureVisualizationViewModel`: publish the head quaternion (read
     `PoseSample.headOrientation`), and do the **rest-pose capture in quaternion
     form** (snapshot `qRest` on the calibrating→judged transition, mirroring the
     existing Euler rest capture). Gate like the Euler one; nil when absent.
  2. `PostureVisualizationBinding.apply`: **if** the VM exposes a head quaternion,
     build `headTarget` via R3 (`HeadOrientationRender`) — remap+gain+clamp — and
     feed the existing `DampedOrientation` follower. **Else** keep the current
     Euler shape/gain/clamp path verbatim (fallback).
  3. New tunables: `headRotationGain` (uniform, default ~1.0–1.3) and
     `headRotationMaxAngleDegrees` (default ~55). Replace the per-axis head gains
     **only on the quaternion branch**; leave `headYaw/Pitch/RollGain` for the
     Euler fallback.
- **Accept:** `xcodebuild … build` SUCCEEDED. Payoff on device: a level Front-Face
  turn no longer dips; a nod is proportional and bounded.
- **Don't:** route the quaternion anywhere near scoring; keep the One Euro on the
  Euler/2D path (quaternion path relies on DampedOrientation — a quaternion
  denoiser is out of scope for v1).

### R5 — Sliders + device-confirm notes
- **Depends on:** R4. **Context:** Common brief +
  `PostureVisualizationCalibrationOverlay.swift` + `PostureVisualizationDevNotes.swift`.
- **Change:** add DEBUG sliders for `headRotationGain` and
  `headRotationMaxAngleDegrees`; add a DevNotes `toAction` entry: **device-confirm
  the basis `B`** (does a turn drive figure yaw, a nod figure pitch, a tilt figure
  roll? flip a sign / swap an axis in `B` if not — do NOT pre-invert in R3's
  math, dial it here), recapture neutral, dial gain for legibility.
- **Accept:** `xcodebuild … build` SUCCEEDED.

### R6 — Bake + commit (human-gated)
- After device dialing: bake `B`/`headRotationGain`/`maxAngle` defaults; commit
  the Track B work (plus A1 only if you ran it) as one coherent change. `git
  fetch` first. End the
  commit message with the required `Co-Authored-By:` / `Claude-Session:` trailers.

---

## TRACK A (optional — do SECOND, or skip)

### A1 — Bake dialed gains into the legacy/fallback Euler path
- **Independent of Track B; largely moot once R4 ships** (the quaternion path
  supersedes these gains for Front Face). Worth doing only as a stopgap before B
  lands, or to tune the non-TrueDepth/dropout fallback.
- **Context:** Common brief + `PostureVisualizationBinding.swift` only.
- **Input you must get from the human first:** the values they settled on for
  the `turn↓tilt` (→ `faceTiltTurnFadePowerDefault`) and `nod` (→
  `headPitchGainDefault`) sliders (and optionally `tilt` → `headRollGainDefault`).
- **Change:** update those `*Default` constants to the dialed values. Nothing else.
- **Accept:** `xcodebuild … build` → BUILD SUCCEEDED.
- **Don't:** change the Euler math or the landed clamp; don't commit unless asked.

---

## Notes for the orchestrator
- **Start with R1** (root, pure, no deps). R2 and R3 each need only R1 and run in
  parallel; R4 is the join; then R5, then R6. **A1 is optional and independent —
  run it second, or skip it once R4 lands.** Keep each agent to **its named files
  + this brief** — that is the whole point of the split.
- The figure frame, the gating-on-nil rule, and the viz-only invariant are the
  three things every agent must respect; they're in the Common brief so no agent
  needs the others' context.
