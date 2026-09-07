# Plan: default to Front (Face) + retire the monocular face-fit (Tier 2)

**Branch:** `usdz-figure-pipeline` · **Created:** 2026-06-20 · **Status:** APPROVED, not yet executed

Two changes the user requested after Layer 1 (ARFaceAnchor) landed and the monocular
path proved inadequate:

1. **Make `.frontFace` the default camera mode on TrueDepth-capable devices.**
2. **Retire the Tier-2 Vision rev-3 monocular face-fit** (Layer 0) — the in-between
   path that didn't fix the pitch. ARFace supersedes it where hardware allows; the
   legacy 2D formula remains the fallback where it doesn't.

## ⚠️ The one real decision (flag before/while executing)

Defaulting to `.frontFace` trades the rear LiDAR path's **depth-based posture
scoring** (true forward-lean / forward-creep) for the front camera's accurate head
visualization. Posture **scoring** is the app's core job and is best on `.rearDepth`
(LiDAR); head angles are **viz-only**. So this default optimizes the figure's head
fidelity over depth-scoring accuracy. The user asked for it explicitly; implement,
but if they reconsider, the alternative is to keep `.rearDepth` default and just make
`.frontFace` easily selectable (already done). This only affects NEW installs / users
who never picked a mode (an explicit persisted choice is always respected).

## Context (what's being removed vs kept)

Three head-angle sources exist today (post-Layer-1):
- **Tier 1 — ARFaceAnchor** (`InputFrame.externalHeadAngles` → `PoseObservation.externalHeadAngles`). TrueDepth only. **KEEP — primary.**
- **Tier 2 — Vision rev-3 monocular face-fit** (`faceYaw/facePitch/faceRoll`, gated by `FaceAngleTuning.useFaceAngles`, `face` overlay chip). **RETIRE.**
- **Tier 3 — legacy 2D formulas** (`computeHeadYaw/Pitch/Roll`). **KEEP — fallback floor for non-TrueDepth devices + face-anchor dropout.**

Cannot delete more because: ARFace needs TrueDepth (SE/older lack it); ARFace gives
head only, so Vision **body** pose still supplies shoulders/side-lean even in
`.frontFace`; rear LiDAR is the primary scoring path. Head angles never feed
`PostureEngine` scoring — viz-only — so all of this is render-only risk.

---

## TASK 2 — Retire Tier-2 monocular face-fit (do FIRST; Task 1 is tiny)

### Dependency to clear first
`HeadOrientationDecomposition.taitBryanZYXDegrees` (KEEP) calls
`FaceAngleConversion.degrees` at `HeadOrientationDecomposition.swift:50`. Inline a
plain rad→deg there so `FaceAngleConversion` can be deleted.

### PostureLogic source
1. **`HeadOrientationDecomposition.swift`**
   - Replace the `FaceAngleConversion.degrees(...)` call (~line 50) with inline
     `let k = Float(180.0 / .pi)` and `return (yawRad*k, pitchRad*k, rollRad*k)`.
   - Fix the doc comment (~line 5) that references `FaceAngleConversion`.
2. **`FaceAngleConversion.swift`** — **DELETE the whole file** (both `FaceAngleConversion`
   and `FaceAngleTuning` enums).
3. **`PoseObservation.swift`**
   - Remove `faceYaw/facePitch/faceRoll` stored props (lines ~24-26), their init
     params (~40-42), assignments (~48-50), and their doc block. **Keep `externalHeadAngles`.**
   - Fix the `externalHeadAngles` doc comment that mentions the `useFaceAngles` flag (~line 32).
4. **`PoseService.swift`**
   - Remove `faceRequest` (lines ~64-65); change `try handler.perform([request, faceRequest])`
     back to `try handler.perform([request])`.
   - Remove `let faceAngles = extractFaceAngles(...)` (~line 81) and the
     `faceYaw/facePitch/faceRoll:` args (~87-89) from the `PoseObservation(...)` init.
     **Keep `externalHeadAngles: frame.externalHeadAngles`.**
   - Delete `minFaceConfidence` (~155) and the whole `extractFaceAngles(...)` func (~162-180).
   - Keep `import Vision` (still used by `VNDetectHumanBodyPoseRequest`).
5. **`PoseDepthFusion.swift` — `computeHeadAngles`** → collapse 3-tier to 2-tier:
   ```swift
   func computeHeadAngles(from pose: PoseObservation) -> HeadAngles {
       if let external = pose.externalHeadAngles { return external }   // Tier 1: ARKit
       return HeadAngles(                                              // Tier 3: legacy
           pitch: computeHeadPitch(from: pose),
           yaw: computeHeadYaw(from: pose),
           roll: computeHeadRoll(from: pose))
   }
   ```
   - Remove the Tier-2 block (`guard FaceAngleTuning.useFaceAngles … pose.facePitch ?? legacy …`).
   - The `fuse3D` `externalHeadAngles == nil` pitch-override guard stays as-is (correct).
   - Update doc comments referencing `useFaceAngles` (~467, 481, 491).

### PostureLogic tests
6. **`FaceAngleConversionTests.swift`** — **DELETE the whole file.**
7. **`PoseDepthFusionTests.swift`**
   - Remove Tier-2 tests: `test_faceAngles_eliminateLegacyPhantomNodOnPureTurn`,
     `test_faceAngles_pureYawSweep_staysFlat`, `test_faceAngles_nilFieldsFallBackToLegacyExactly`,
     `test_faceAngles_partialFit_mixesPerAxis`, `test_faceAngles_defaultOff_ignoresFaceFields`.
   - Remove helper `makeFacePose(...)`. **KEEP `turnGeometry()`** (the external tests use it).
   - In the external (Layer-1) tests: drop the `FaceAngleTuning.useFaceAngles` lines;
     change `makeExternalPose` to drop its `face:` param (no more faceYaw/etc);
     delete `test_external_beatsFaceFit_whenBothPresent` (Tier 2 gone — nothing to beat);
     rename `test_external_winsVerbatim_evenWithFaceFlagOff` → `test_external_winsVerbatim`.
   - Keep `test_external_nil_isLegacyExactly`, `test_external_pitchSurvivesLiDAROverrideInDepthMode`.

### App target
8. **`PostureVisualizationCalibrationOverlay.swift`** — remove the `chip("face", faceAnglesBinding)`
   (~line 224) and the `faceAnglesBinding` computed property (~256-263). Leave the
   `mirror` chip + the rest.
9. **`PostureVisualizationDevNotes.swift`** — remove the now-obsolete toAction item
   "FACE-FIT SOURCE — confirm on device + bake" (~line 46); add a one-line changelog
   entry noting Tier-2 retirement. (Historical changelog entries can stay.)

---

## TASK 1 — Default `.frontFace` on supported devices

10. **`AppModel.swift` init** — change the mode-load block to:
    ```swift
    var initialMode: CameraMode
    if let raw = defaults.string(forKey: Keys.cameraMode),
       let saved = CameraMode(rawValue: raw) {
        initialMode = saved                                   // explicit choice wins
    } else {
        initialMode = ARFaceTrackingService.isFaceTrackingSupported ? .frontFace : .rearDepth
    }
    if initialMode == .frontFace && !ARFaceTrackingService.isFaceTrackingSupported {
        initialMode = .front2D                                // safety net
    }
    self.cameraMode = initialMode
    PostureVisualizationBinding.faceTrackingActive = (initialMode == .frontFace)
    ```
    (The last line already exists — keep it.)

---

## Verify / land
- `cd PostureLogic && swift test` — expect green; count drops (≈511 → ~500 after
  removing the 5 Tier-2 fusion tests + 5 FaceAngleConversion tests).
- `xcodebuild build -project Quant.xcodeproj -scheme Quant -destination 'generic/platform=iOS Simulator' -configuration Debug` — expect **BUILD SUCCEEDED**. (SourceKit "No such module" errors are known false positives; xcodebuild is authoritative.)
- Update `MEMORY.md` memory note (`project_usdz_figure_pipeline.md`).
- Commit (two logical commits or one) + push to `usdz-figure-pipeline`. Fetch first
  (nightly auto-build agent shares the branch). End commit msgs with the required
  Co-Authored-By + Claude-Session trailers.

## Post-change source-of-truth (head angles)
ARFaceAnchor (`.frontFace`, TrueDepth) → else legacy 2D formula. No monocular
middle tier. Default mode = `.frontFace` where supported, else `.rearDepth`
(coerced to `.front2D` only if a stale `.frontFace` is persisted on unsupported hw).
