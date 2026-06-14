# USDZ Figure Pipeline — Implementation Plan

Date: 2026-06-14
Status: IMPLEMENTED + on-device tuning in progress (PR #13, branch usdz-figure-pipeline).
NEXT TASK for a fresh session: head-yaw proportionality (see "HANDOFF" below).

## HANDOFF 2026-06-14 — make head yaw proportional (open blocker)

**Symptom (validated on device):** turning the head reads "all or nothing" — the
figure's head snaps to a big turn rather than tracking the real angle. Direction
and the earlier downward-tilt bug are FIXED. Goal: head yaw should *roughly match
the user's real turn angle* — accuracy matters (an inaccurate head turn breaks
trust). User OK with editing detection provided it's revertible (it's on a branch).

**Root cause — upstream in PostureLogic, not the visualization:**
`PostureLogic/Sources/PostureLogic/Services/PoseDepthFusion.swift`
- `computeHeadYaw(from:)` lines **463–486**. Two regimes:
  - Both ears visible: `asin((nose.x − earMidX) / earSeparation)` in degrees —
    smooth & proportional. GOOD regime.
  - One ear occluded (full turn): returns the **constant** `±oneEarMissingYawDegrees`
    (= **60**, line **452**) and pins there → the discontinuous "all or nothing".
    Flicker = far ear toggling in/out of detection at the boundary.
- `computeHeadAngles` 415–421; roll 431–448; pitch-2D 499–519; pitch-3D 541–590.
- The viz already compensates as far as it can: `PostureVisualizationBinding.headYawGain
  = -0.6` (flip + tame). It can't add proportionality the raw signal lacks.

**Proposed fix (tune on device):** replace the flat ±60 one-ear branch with a
*monotonic, proportional* estimate that continues past ear occlusion, e.g. use the
**eyes** (still visible at large yaw — pitch already falls back to the eye line) as
the scale reference: ratio = (nose.x − eyeMidX) / eyeSeparation, with a calibration
factor so it joins the two-ear curve continuously and ramps toward ~90°. Keep the
sign rule (missing right ear → +, missing left → −). Add hysteresis/smoothing at the
two-ear↔one-ear boundary to kill flicker. Calibration factor MUST be tuned by eye on
device (turn to known angles); it can't be validated headlessly.

**Tests to update (CI-gated — TestFlight upload gates on PostureLogic tests):**
`PostureLogic/Tests/PostureLogicTests/PoseDepthFusionTests.swift`, head-yaw tests
**252–327** (one-ear tests 291–309 currently assert `>30` / `<−30`; integration 517).
Keep them green; add a monotonicity assertion (more turn → more yaw, no snap).

### IMPLEMENTED 2026-06-14 (3) — proportional one-ear yaw (pending on-device tuning)
`PoseDepthFusion.swift`:
- New `oneEarYaw(toward:from:)` replaces the flat ±60 branch. Scales the turn off
  the **eyes** (visible past ear occlusion): `θ = atan(k · |nose.x − eyeMidX| /
  eyeSeparation)`, sign forced by the missing ear. Monotonic, saturates → 90°,
  continuous-ish with the two-ear `asin` curve (so far-ear flicker no longer snaps).
- Kept the function **pure / non-mutating** (tests call it on a `let`; value-type
  `deinit` discipline). No stateful hysteresis — continuity de-flickers structurally;
  ViewModel low-pass handles residual. Eyes-missing → old flat `±60` fallback.
- **THE KNOB:** `HeadYawTuning.oneEarCalibration` (public, **device-tuned default
  `8.0`** as of 2026-06-14, confirmed mid-slider/not railed; anatomical ideal ≈2.7
  but Vision's nose/eye keypoints push the real value higher). ↑ k ⇒ a given offset
  reads as a bigger turn. `oneEarMaxYawDegrees` (90 ceiling) stays `private`.
- **ON-DEVICE SLIDER** (`PostureVisualizationCalibrationOverlay`, `#if DEBUG`):
  bottom-right ▭ button in `PostureVisualizationView` reveals a `k` slider (range
  1.0–12.0 — widened after the first pass railed at the old 6.0 max) + live `rawYaw`
  readout (turns green ≥45°) + reset. Tune without rebuild: turn until one ear hides,
  then nudge k until rawYaw matches the real angle. Stripped from Release.
- **STATUS: DONE.** k=8.0 confirmed good on device (mid-slider, settled), committed
  (be852eb) + pushed; PR #13 CI green against b696e64 (Swift Package / PostureLogic
  Tests pass — the TestFlight gate). Ghost hidden **by product decision**
  (`DebugChannels.hideGhost = true`, committed separately b696e64). The `#if DEBUG`
  calibration slider **stays** (decided 2026-06-14) — permanent tuning affordance,
  stripped from Release.
- Tests added (all 486 PostureLogic tests green via `swift test`): proportional +
  monotonic with eyes, sign-follows-missing-side, eyes-missing constant fallback.
  Existing one-ear tests (291–309, no eyes) still pass via the fallback path.
- NOT committed — left in working tree for on-device tuning of k first.

**Constraints/safety:** all on branch `usdz-figure-pipeline` (PR #13 → main). Revert =
drop the single PostureLogic commit. Don't touch `resolve()/mirror()/ViewModel`
(unit-tested). Test scheme is `QuantNoWatchTests`; sim id e.g. iPhone 16
`D78638EB-2FF6-4C9E-9260-9B9DB9473565`. Build scheme `Quant`. SourceKit shows false
"No such module" errors — xcodebuild is authoritative.

---

Status: IMPLEMENTED + on-device tuning in progress.
Decision inputs: build loader later; **rename entities in Blender, re-export** (no Swift naming adapter).
Scale handled in Swift (`Layout.figureScale`); materials forced unlit at load.

## STATUS UPDATE 2026-06-14 (2) — Swift implementation complete

Files changed (main checkout, uncommitted):
- `PostureVisualizationScene.swift`: added `Layout.figureScale = 0.08`,
  `loadAssembly() async` (loads `quant_person.usdz`, wraps in a `PostureAssembly`
  container with a constant-scale figure layer below the binding's per-frame root
  scale, forces unlit materials, falls back to procedural `makeAssembly()` on
  failure), recursive `applyUnlit`, and `makeGhost(from:)` (rest-pose clone).
- `PostureVisualizationBinding.swift`: `apply()` now drives **lean as torso
  rotation about the base** (reused `headTranslation.x/.z` as angles via
  `leanRadiansPerMeter`/`forwardLeanRadiansPerMeter = 2.0`) instead of head
  translation; head only gets look rotation (position left as authored neck);
  `retint` recurses so it tints the USD mesh prims under the named Xforms.
  `resolve()`/`mirror()`/ViewModel UNCHANGED → existing unit tests intact.
- `PostureVisualizationView.swift`: `RealityView` make closure is now `async`
  (awaits `loadAssembly`, builds ghost from it).

Verified: `xcodebuild -scheme Quant` BUILD SUCCEEDED; `quant_person.usdz` is in the
build manifest and bundles to `Quant.app/quant_person.usdz` (synced folder, no
pbxproj edit). Verify via explicit `-derivedDataPath` — worktrees fork DerivedData.

PENDING (needs the running app, can't be done headlessly):
- Tune `Layout.figureScale` (0.08 starting) to frame the figure in the camera.
- Tune lean gains + confirm **lean sign** (roll/pitch direction) by eye; mirror
  is on by default.
- Decide if the camera (`makeCamera`, target y=0.15, distance 0.85) needs
  re-deriving for the figure vs. just scaling.
- Cosmetic: relabel `PostureVisualizationValuesOverlay` (lean is now an angle, not
  a translation); refresh `PostureVisualizationDevNotes` open-actions.

## STATUS UPDATE 2026-06-14 — Blender renames + re-export complete

Done via Blender MCP against the live `Avatar.blend` scene:
- Live hierarchy was already `Figure → Body → Head` with real parent links, so
  **task 1 needed no change**. `Head.parent = Body`, `Body.parent = Figure`.
- **Origins were already correct** (the planned "move Body origin" step was unnecessary):
  - `Body` origin at world (0,0,0) = ground contact (local geom z 0→1.95) → lean/twist
    pivot about the base. ✓
  - `Head` origin at world z=2.09, local geom z 0→1.64 → origin at the neck. ✓
- **Renamed** for the `EntityName` contract: `Figure → PostureAssembly`, `Body → ShoulderDisc`.
  `Head` unchanged. No band geometry exists → **no `HeadBand`** (state-tint must fall back
  to the head material, or add a band later).
- **Front axis verified empirically** (exported temp USD, read back with pxr): the model's
  flatter front (Blender −Y, extent 1.246) lands on **+Z**; fuller back (1.507) on −Z.
  Matches the app's +Z-forward convention. ✓
- **Re-exported** to `Quant/Resources/quant_person.usdz` (717 KB, git-untracked/new).
  Export settings that produced correct orientation (these flag semantics are
  version-specific — verified on this Blender, not assumed):
  `convert_orientation=True, export_global_up_selection='Y',
  export_global_forward_selection='NEGATIVE_Z', convert_world_material=False,
  selected_objects_only=True` (figure hierarchy only).
- Verified written file: **upAxis=Y**, metersPerUnit=1.0, **no lights/cameras**,
  hierarchy `/root/PostureAssembly/ShoulderDisc/Head`.

### Facts the Swift phase must account for (changed/confirmed since original plan)
1. **`/root` wrapper prim**: the top entity RealityKit returns is named `root`, not
   `PostureAssembly`. Loader MUST set `loaded.name = EntityName.assembly` (already in §4a).
   `findEntity(named:)` finds `ShoulderDisc`/`Head` recursively beneath regardless.
2. **Mesh prim names** are `Sphere_015` (under ShoulderDisc) / `Sphere_013` (under Head) —
   irrelevant; binding matches the Xform names which carry transforms.
3. **Scale: figure is 3.733 m tall.** The procedural scene was ~0.2–0.3 m and the camera
   (`makeCamera`, distance 0.85 m) is tuned for that. The camera MUST be re-derived for a
   ~3.7 m figure, OR normalize scale. NOTE: do NOT normalize via the root entity's scale —
   the binding overwrites `assembly.scale` each frame (forward-creep). Normalize by baking
   scale into geometry in Blender, or move the camera. (Open decision.)
4. **Material is Principled BSDF (`FigureMat`), not unlit, and no light is shipped.** In
   RealityKit it will need an environment/IBL on the `RealityView`, or the loader should
   convert to `UnlitMaterial` to match the existing flat aesthetic. (Open decision.)

## 0. Why this plan exists (ground truth)

The app does **not** load a USDZ today. `Quant/Views/Visualization/PostureVisualizationScene.swift`
builds the figure procedurally from RealityKit primitives:

```
PostureAssembly            (empty root — uniform scale + opacity)
├── ShoulderDisc           generateCylinder (flat disc; gets Y-yaw "twist")
│   └── ShoulderTick       +Z marker, rides disc yaw
└── Head                   generateSphere at (0, 0.15, 0)  ← SIBLING of disc
    ├── HeadBand           equator cylinder (state-tint target)
    └── HeadTick           +Z "nose" marker
```

Your model (`Figure → Body → Head`, root at ground contact, head origin at neck,
front = −Y, Z-up, rounded rocking base) is a different, better-designed object that
has never been wired in. `~/Desktop/quant_person.usdz` exists (718 KB) and
`Avatar.blend` is in the repo but neither is referenced by any Swift.

Consequence for the original four tasks:
1. Head parented to torso? — **No.** Head is a sibling of the disc; there is no torso.
2. Lean about base / look about neck? — **No.** Lean = head X-translation; "look" pivots
   at the sphere center, not a neck.
3. Front matches −Y? — **Yes, after Y-up export.** Blender −Y maps to +Z in a Y-up USDZ,
   and the code treats +Z as front. (Verify visually; mirror is on by default.)
4. Re-export to "the path the code expects" — **no path exists yet.**

So this is a build, not a confirm-and-tweak.

## 1. Design principle (the crux)

**Move pivots into the asset; make the binding set orientations only.**

The model already encodes the two pivots the binding needs:
- Lean / twist pivot = **ground contact** → carried by the torso entity's origin.
- Head-look pivot = **neck** → already the Head origin (you set this).

If origins are authored correctly, the live binding collapses to:
- torso entity: `orientation = twist(yaw) ∘ lean(roll/pitch)` — rocks about base, and
  because Head is its child, **torso motion propagates to the head (task 1 + task 2)**.
- head entity: `orientation = look(pitch/yaw/roll)` — pivots at the neck (task 2).
- root entity: `scale` (forward-creep) + `OpacityComponent` (tracking quality) — unchanged.

No translations needed for lean/forward; the asset's authored transforms place everything.

## 2. Blender-side requirements (you do these, then re-export)

### 2a. Entity names — must match the binding's `EntityName` strings exactly
The binding resolves entities via `findEntity(named:)` (recursive). Rename so the
re-exported USDZ contains these names:

| Blender node | Rename to        | Role in binding                                |
|--------------|------------------|------------------------------------------------|
| Body (torso) | `ShoulderDisc`   | twist (Y) + lean (roll/pitch) about base       |
| Head         | `Head`           | look (pitch/yaw/roll) about neck               |
| head band*   | `HeadBand`       | optional — state-color tint target             |

\* If the model has no separate band geometry, skip it; the loader will treat
`HeadBand` as optional (state tint falls back to the head material). Do NOT invent a band.

The root (`Figure`) name does **not** matter — the loader sets the root's name to
`PostureAssembly` defensively (USD stage import can wrap/rename the root, so we can't
rely on the Blender name surviving). This is one assignment, not a naming adapter.

### 2b. Origins — this is what makes the pivots correct
- **Head origin = neck** — already done. Keep it. This makes head-look pivot at the neck.
- **Body ("ShoulderDisc") origin = the ground contact point** (same point as the Figure
  root). Move the Body object origin to the floor, NOT the torso centroid. This makes
  twist + lean rock about the contact point. Mesh stays visually in place; only the
  local origin moves.
- **Figure (root) origin = ground contact** — already done. Keep it.

### 2c. Axis / export settings
- Keep **Up = +Z in Blender → Y-up on export** (you already export Y-up).
- Confirm **front = −Y in Blender → +Z in the exported file** (Blender `(x,y,z)→(x,z,−y)`,
  so −Y → +Z). The code's front is +Z, so this aligns.
- Export selection: Figure + descendants only (no camera/lights). Single root.
- After export, sanity-check in Reality Composer Pro / Quick Look that the nose/front
  faces +Z and up is +Y.

### 2d. Deliverable
Re-export to the repo (not Desktop) — proposed path:
`Quant/Resources/quant_person.usdz` (new folder; see §3).

## 3. Asset staging + Xcode target

- Create `Quant/Resources/` and place `quant_person.usdz` there.
- Add to the **Quant app target** (Copy Bundle Resources). With Xcode 16 synced
  folders, dropping it in the synced folder should auto-add — verify membership.
- Do **not** add to the watch target (no RealityKit figure there).
- Loadable at runtime via `Bundle.main.url(forResource: "quant_person", withExtension: "usdz")`.

## 4. Swift changes

### 4a. New loader (keep the value-type / no-`deinit`-class discipline)
`PostureVisualizationScene.swift` is deliberately an `enum` namespace of static
factories to avoid the toolchain's isolated-`deinit` SIGABRT hazard (see file header).
**Keep that.** Add an async static factory; introduce no class with a custom `deinit`.

```swift
@MainActor
static func loadAssembly() async throws -> Entity {
    guard let url = Bundle.main.url(forResource: "quant_person", withExtension: "usdz")
    else { throw SceneError.assetMissing }
    let figure = try await Entity(contentsOf: url)
    figure.name = EntityName.assembly          // defensive: guarantee the root name
    return figure
}
```

- Keep `makeAssembly()` (procedural) temporarily as a fallback if the load fails, so a
  bad/missing asset degrades gracefully instead of showing an empty scene. Remove once
  the USDZ path is proven.
- `makeGhost()`: replace the procedural duplicate with `loadedFigure.clone(recursive: true)`,
  set `OpacityComponent(opacity: 0.15)`, add as a separate root (unchanged ghost contract:
  binding never touches it).
- `EntityName.shoulderTick` / `headTick` become unused (model has authored front geometry);
  remove the constants and any overlay references.

### 4b. RealityView make closure → async
`PostureVisualizationView.swift` currently adds entities synchronously. Switch to the
async `RealityView` make closure:
```swift
RealityView { content in
    if let figure = try? await PostureVisualizationScene.loadAssembly() {
        content.add(figure)
        if !PostureVisualizationBinding.debug.hideGhost {
            content.add(PostureVisualizationScene.makeGhost(from: figure))
        }
    }
    content.add(PostureVisualizationScene.makeCamera())
} update: { content in /* unchanged: find PostureAssembly, apply binding */ }
```
The `update` closure already finds the assembly by name and calls
`PostureVisualizationBinding.apply` — no change there beyond §4c.

### 4c. Binding rework (`PostureVisualizationBinding.swift`) — the behavioral change
Repurpose the existing channels so lean becomes rotation, not translation:

- **torso ("ShoulderDisc")**: set `orientation = twistYaw(Y) ∘ leanRollPitch`.
  - twist (yaw) stays as today's `discYawRadians` about Y.
  - **lean**: convert today's `sideLeanOffsetPoints` (head X translation) into a **roll**
    about Z (and/or forward pitch about X) applied here. Pivot is the base because the
    torso origin is at the contact point.
- **head ("Head")**: keep `orientation = headOrientation(pitch,yaw,roll)` for look.
  - **Remove** the `head.position` writes (X side-lean, Z forward) and the
    `Layout.headCenterY = 0.15` rest offset — the USDZ authors head placement now.
- **root ("PostureAssembly")**: keep uniform `scale` (forward-creep) + `OpacityComponent`.
- `RuntimeCache`: still caches `disc` / `head` / `band` by name — works unchanged
  (`band` becomes optional; guard the tint write).
- `mirror(_:)`: still valid — it negates horizontal-sense channels (twist, yaw, roll,
  and now lean-roll). Re-confirm signs after lean becomes a rotation.

### 4d. ViewModel retuning (`PostureVisualizationViewModel.swift`)
Mapping constants were tuned for translation/scale, not rotation:
- `sideLeanPointsPerUnit` (X-translation) → becomes a **degrees-per-unit** lean gain.
  Retune by eye; add a `leanCapDegrees`.
- `forwardCreepScaleFactor` (scale) → keep as scale, OR reinterpret forward-creep as a
  forward **pitch** about the base. Decision deferred — scale is the lower-risk default.
- `headForwardPointsPerUnit` (Z-translation) → likely drop, or fold into forward pitch.
- Smoothing/low-pass filters carry over unchanged.

### 4e. Cosmetic / docs
- `PostureVisualizationValuesOverlay.swift`: relabel rows (latLean/headFwd were
  translations; now lean is an angle). Low priority.
- `PostureVisualizationDevNotes.swift`: update the open-actions list; several items
  (mirror permanence, calibration-relative pitch/roll) still apply.

## 5. Mirror & front-axis (tasks 3) — verification, not code
- `DebugChannels.mirrored = true` by default → front-facing "mirror" view; flips
  horizontal sense only, not the front axis. After the swap, re-confirm a real left lean
  shows as a left lean on screen; flip a sign in `mirror(_:)` if not.
- Camera (`makeCamera`) is a separate root at ~80° elevation on the +Z side — unchanged.
  Confirm the model's authored front (+Z) faces it.

## 6. Verification checklist
1. App launches; figure appears (not the procedural fallback) — log which path ran.
2. `findEntity(named: "ShoulderDisc"/"Head")` returns non-nil (else names are wrong).
3. Twist input → torso + head rotate together about vertical axis through the base.
4. Lean input → figure rocks about the ground contact; head rides along (task 1 + 2).
5. Head-look input → head rotates about the neck with the torso still (task 2).
6. Left/right read correctly with mirror on (task 3).
7. Ghost shows faint at rest pose and never moves.
8. Run PostureLogic tests (CI gates TestFlight on them) — should be unaffected (pure UI),
   but confirm no build breakage.

## 7. Open decisions to settle before coding
- Forward-creep: keep as uniform scale, or reinterpret as forward pitch about base?
- Keep procedural `makeAssembly()` as a permanent fallback, or delete after proving USDZ?
- Mirror: make permanent (drop the debug guard) or keep toggle?
- Does the model carry a `HeadBand`-equivalent for state tint, or do we tint the head
  material directly?
