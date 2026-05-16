# Quant Posture Visualization — Build Plan

> **Status:** Design / intent reference. This is the original human-authored spec,
> preserved verbatim. The Ralph-runnable, step-decomposed version lives in
> `../implementation/plan.md`. When the two disagree on *intent* (anti-goals,
> variable mapping, fallback philosophy), **this document wins**. When they
> disagree on *execution order or done-criteria*, `plan.md` wins.

## Goal

Build a 3D-rendered posture visualization for the LinkedIn demo video. A top-down stylized representation of the user's head and shoulders that mirrors their posture in real-time.

**Hero element:** A small head sphere (two-tone hemispheres, with a tick marker for nose direction) sitting above a wider shoulder disc. Both viewed from above. The whole assembly rotates, tilts, scales, and shifts colour based on live posture data.

**Anti-goals (v1):**
- No cel shading
- No outlines
- No photorealistic materials
- No new posture detection logic (use what RawMetrics already provides + minimal additions)

---

## Architecture Principle

**Separate data from rendering.** All orientation calculations live in a shared ViewModel. The view layer (SwiftUI container + embedded RealityView) just binds to published values and renders.

This means:
- Framework choice is reversible — if RealityKit fights back, the same ViewModel feeds a SwiftUI fallback view
- Variable mappings are tunable in one place
- The data work isn't wasted regardless of which renderer ships

---

## Build Sequence

### Phase 0 — Setup (30 min)

- New git worktree: `quant-vis`
- Branch: `feature/posture-visualization`
- New folder: `Quant/Views/Visualization/`
- New folder: `Quant/ViewModels/` (if not already present)

### Phase 1 — Data Layer (2 hours) — Framework-agnostic

Build `PostureVisualizationViewModel: ObservableObject`

**Responsibilities:**
- Subscribe to existing `RawMetrics` and `PoseObservation` from `AppModel`
- Compute head rotation heuristics (yaw/pitch/roll) from keypoints — see Variable Mapping
- Smooth all values with a low-pass filter (start at α = 0.2)
- Scale and clamp raw values into display units
- Convert `PostureState` enum to display `Color`
- Expose `@Published` properties for the view to consume

**Output properties:**
```swift
@Published var shoulderRotationDegrees: Double      // from twist
@Published var sideLeanOffsetPoints: Double         // from lateralLean
@Published var headForwardOffsetPoints: Double     // from headForwardOffset
@Published var assemblyScale: Double                // from forwardCreep
@Published var headYawDegrees: Double               // computed from keypoints
@Published var headPitchDegrees: Double             // computed from keypoints
@Published var headRollDegrees: Double              // computed from keypoints
@Published var opacity: Double                      // from trackingQuality
@Published var stateColor: Color                    // from postureState
@Published var isCalibrating: Bool                  // from postureState
```

**Head rotation heuristics (compute from `VNHumanBodyPoseObservation`):**
- **Yaw:** horizontal offset of nose from ear-midpoint, normalised by ear separation
- **Pitch:** vertical distance from nose to ear-midpoint, normalised by face scale (eye-to-eye distance)
- **Roll:** angle of line between left and right ear

### Phase 2 — Debug Harness (1 hour) — Validation only

Throwaway SwiftUI view: `VisualizationDebugView`

- Sliders for every input variable (or "use live data" toggle)
- Numeric readouts of every ViewModel output
- Confirms ViewModel produces sensible values across full input range
- **Delete after Phase 4**

### Phase 3 — RealityKit Scene (3-4 hours, **time-boxed to 6 hours**)

Build `PostureVisualizationView: View` containing a `RealityView`.

**Scene contents:**
1. **Shoulder disc entity**
   - Flat cylinder, very short height (e.g. 0.4 wide × 0.25 deep × 0.02 tall)
   - `UnlitMaterial`, neutral stroke colour
   - Tick marker entity (small box) at the "front" position
   - Rotates around vertical (Y) axis with twist

2. **Head sphere entity**
   - Sphere, radius ~0.06
   - Two `UnlitMaterial`s applied to hemispheres (use UV or two half-sphere meshes back-to-back)
   - Top hemisphere lighter, bottom hemisphere darker
   - Small box entity (tick marker) attached at the "nose" position on the equator
   - Positioned above the shoulder disc by ~0.15

3. **Camera**
   - Orthographic or perspective from straight above
   - Slight angle (e.g. 80° from horizontal) so the hemisphere reveal is visible

4. **Lighting**
   - Minimal ambient only — `UnlitMaterial` ignores lights anyway, so this only matters if you switch material types later

**Bind ViewModel values to entity transforms** via the `update` closure of RealityView:
- Shoulder disc rotation ← `shoulderRotationDegrees`
- Head sphere position ← `sideLeanOffsetPoints`, `headForwardOffsetPoints`
- Head sphere Euler angles ← `headYawDegrees`, `headPitchDegrees`, `headRollDegrees`
- Whole anchor scale ← `assemblyScale`
- Material colours ← `stateColor`
- Container opacity ← `opacity`

**Time-box discipline:** if you're 6 hours in and still fighting framework setup, stop. Execute Fallback Plan.

### Phase 4 — Integration & Polish (1-2 hours)

- Wire `PostureVisualizationView` into existing app navigation (probably alongside `DebugOverlayView`)
- Add state-driven colour transitions: calibrating (pulsing grey), good (neutral/green), drifting (amber), bad (red)
- Add baseline ghost entities (faint duplicates at calibrated positions)
- Smooth animation curves — use `.smooth(duration: 0.3)` equivalent for RealityKit entity transforms
- Test on device (simulator won't show real pose data)

---

## Variable Mapping (Reference Table)

| Quant variable | Display effect | Element | Starting scale |
|---|---|---|---|
| `twist` (shoulder rotation) | Rotate around vertical axis | Shoulder disc | 1.5× (amplify) |
| `lateralLean` | Horizontal offset | Head sphere | 100pt per unit |
| `headForwardOffset` | Forward offset (toward front of disc) | Head sphere | 100pt per unit |
| `forwardCreep` | Uniform scale | Whole anchor | 1 + (creep × 0.5) |
| `headYaw` (computed) | Rotate around vertical axis | Head sphere | 1.5× |
| `headPitch` (computed) | Rotate around horizontal axis (chin tuck) | Head sphere | 1.5×, cap ±60° |
| `headRoll` (computed) | Rotate around forward axis | Head sphere | 1.5×, cap ±45° |
| `trackingQuality` | Opacity | Whole assembly | quality → opacity directly |
| `postureState` | Colour tint of materials | Both elements | discrete mapping |

All multipliers and caps are starting values — tune by eye during demo recording.

---

## Tech Stack

- **SwiftUI:** container view, navigation, state-driven colour, debug harness
- **RealityKit:** 3D entity rendering, transforms
- **UnlitMaterial:** flat shading (no lighting calculations)
- **No Metal/shader code** in v1
- **No outlines** in v1
- **No ShaderGraphMaterial** in v1

---

## File Structure

```
Quant/
├── ViewModels/
│   └── PostureVisualizationViewModel.swift
├── Views/
│   └── Visualization/
│       ├── PostureVisualizationView.swift       (RealityView container)
│       ├── PostureVisualizationScene.swift      (entity setup)
│       ├── VisualizationDebugView.swift         (throwaway, delete after Phase 4)
│       └── VisualizationFallbackView.swift      (SwiftUI fallback, only if needed)
```

---

## Acceptance Criteria

- [ ] All 9 published ViewModel properties update from live pose data
- [ ] Visualization renders at ≥30fps on device
- [ ] All four state colours visibly distinct (calibrating, good, drifting, bad)
- [ ] Head pitch ≥30° produces clearly visible hemisphere reveal
- [ ] Head yaw ≥30° produces clearly visible tick marker rotation
- [ ] Shoulder twist ≥20° produces clearly visible disc rotation
- [ ] Tracking quality drop visibly reduces opacity within 1 second
- [ ] No frame drops during normal use over 5-minute test
- [ ] Calibration animation plays for the duration of the calibrating state

---

## Fallback Plan

If RealityKit total time exceeds 6 hours and you're still not rendering:

1. **Stop. Don't keep grinding.**
2. Create `VisualizationFallbackView.swift` — a SwiftUI-only version:
   - Shoulder ellipse (`Ellipse()` with stroke, `.rotationEffect`)
   - Head circle (`Circle()` with stroke)
   - Tick marker on head via a small `Capsule()` with `.rotationEffect` for roll, `.offset` for yaw/pitch
   - No hemisphere reveal — accept the trade-off
3. Wire to same `PostureVisualizationViewModel`. Data layer work is preserved.
4. Ship the SwiftUI version. Tag the RealityKit branch as `wip/realitykit-vis` for later.

The asset is the LinkedIn video. Don't let framework choice delay shipping.

---

## Demo Recording Notes

Once build is complete:
- Record 60-second demo on actual hardware (not simulator)
- Sequence: calibration → good posture → progressive slouch → recovery
- Hero shot: the hemisphere reveal during pitch (chin tuck)
- Frame the visualisation prominently — not corner-mounted
- Multiple takes; choose the one where state transitions are cleanest

---

## Out of Scope (v1)

Explicitly deferred to v2 or later:
- Inverted-hull outlines
- ShaderGraphMaterial cel shading
- Cinematic camera angles or animation
- Sound feedback
- Apple Watch parity for the visualization
- Recording/replay of historic posture sessions
