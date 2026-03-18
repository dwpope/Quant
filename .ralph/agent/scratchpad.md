# Scratchpad: UI Variants Implementation

## 2026-03-17 — Planner: Step 6 Setup

Steps 1-5 are all committed. The full data layer, mock/live sources, showcase shell, and shared visual utilities are in place.

Step 6 is the first variant batch: Score-Centric (Variants 1-6). Created 7 tasks:
- 6 variant implementation tasks (one per variant, all independent/parallel)
- 1 registry update + integration test task (blocked by all 6 variants)

Key API surface for variant builders:
- `@EnvironmentObject var observer: PostureDisplayObserver` — main data access
- `observer.data: PostureDisplayData` — metrics, postureState, nudgeDecision, worstOffender, aggregateScore, isAlertMode, nudgeCountdownSeconds
- `PostureVisualStyle` — stateColor(), metricColor(), stateLabel(), nudgeCountdownLabel()
- `PostureAnimations` — alertOnset, metricUpdate, nudgePulse, modeTransition
- Reusable: MetricRatioBar, NudgeCountdownLabel, SettingsGearButton, PostureStateAmbientBackground, AbsenceOverlay
- Previews: `MockPostureDataSource.preview(state:worstMetric:worstRatio:)` for non-animating snapshots
- Files go in `Quant/Views/Showcase/Variants/ScoreCentric/`
- VariantRegistry currently uses placeholders for all 60 variants

Starting with Variant 1 (Precision Gauge) — the most complex Canvas-based variant, establishing the implementation pattern for the rest.

## 2026-03-17 — Builder: Variant 2 (Triadic Rings)

Implemented Variant2View.swift in Quant/Views/Showcase/Variants/ScoreCentric/.
- Three concentric rings: outer (overall score with adaptive green/yellow/red color), middle (worst metric inverted, cyan), inner (streak timer, orange)
- Center score display with numericText contentTransition
- Five mini ring badges below with 2-letter abbreviations
- Alert mode: unfilled gap glow/pulse, worst offender label, countdown as 4th dashed outer ring, worst badge scale-pulse, all non-worst badges dim
- Bad state: vibration animation (rotation oscillation) on ring stack
- Landscape: rings left, vertical metric list right with full names and percentages
- Three #Preview blocks: good, alert (drifting + headDrop), absent
- Build clean, 297 PostureLogic tests pass

## 2026-03-17 — Critic: Variant 2 Review (REJECTED)

Found 3 issues requiring fixes:

1. **VibrationModifier bug (critical)**: Two `.rotationEffect` modifiers (+2 and -2) compose additively and always cancel to 0. The `.bad` state vibration is completely invisible. Fix: use a single `.rotationEffect(.degrees(isVibrating && isActive ? 2 : 0))` — the existing `autoreverses: true` on the repeating animation will oscillate it.

2. **Outer ring doesn't lock to red in `.bad` state**: `outerRingColor(score:)` only considers score value, not posture state. Spec requires: "On `.bad`, the outer ring's color locks to red." Fix: check `observer.data.postureState.isBad` and return red unconditionally.

3. **Countdown ring doesn't flash in `.bad` state**: Spec says "the countdown ring flashes." No flashing animation is implemented. Fix: add an opacity toggle animation when `postureState.isBad`.

Minor: worst offender label is outside `ringStack()` in portrait mode (spec says inside), but this is cosmetic.

## 2026-03-17 — Builder: Variant 2 Review Fixes

Fixed all 3 issues from review rejection:

1. **VibrationModifier**: Removed second `.rotationEffect(.degrees(-2))` that was cancelling the first. Single rotation now oscillates via `autoreverses: true`.

2. **Outer ring red lock**: Added `observer.data.postureState.isBad` check at top of `outerRingColor()` — returns red unconditionally in bad state.

3. **Countdown ring flash**: Added `isCountdownFlashing` state + opacity animation (1.0↔0.3) with `.easeInOut(duration: 0.5).repeatForever(autoreverses: true)` when `postureState.isBad`.

Build clean, 297 tests pass.

## 2026-03-17 — Builder: Variant 2 Second Review Fixes

review.rejected event had no payload. Self-reviewed against spec and found 3 additional issues:

1. **AbsenceOverlay missing**: `.absent`/`.calibrating` states had no special handling. Added `AbsenceOverlay` wrapper that dims the variant content and shows "Waiting for pose..." message. Also added `@ViewBuilder` to `AbsenceOverlay.content` to support conditional content.

2. **Worst offender label outside ring stack**: Spec says "its label appears inside the ring stack below the score number." Moved from `portraitLayout` into `ringStack()` as a VStack below `scoreLabel`.

3. **Haptic feedback missing**: Spec lists `.sensoryFeedback(.impact, trigger:)` as a key technique. Added `.sensoryFeedback(.impact, trigger: observer.data.postureState.isBad)`.

Build clean, 297 tests pass.

## 2026-03-17 — Critic: Variant 2 Third Review (PASSED)

Thorough fresh-eyes review against full spec (variant-catalog-1.md lines 76-100). All 19 spec requirements verified in code. All 6 fixes from prior review rounds confirmed. Build clean (exit 0), 297 tests pass. No bugs, missed requirements, or regressions found. Implementation is faithful to spec.

## 2026-03-17 — Finalizer: Variant 2 Closed, Queue Advance

Closed Variant 2 task (task-1773750650-e0b1). Verified: build clean (exit 0), 297 tests pass.

Step 6 progress: 2/6 variants complete (V1 in_progress, V2 closed). Remaining: V3, V4, V5, V6 open + registry update blocked. Steps 7-16 still ahead. Emitting queue.advance to continue Step 6 implementation.

## 2026-03-17 — Planner: Queue Advance → V3 (Battery Drain)

Received queue.advance. Step 6 wave status: V1 blocked (stale?), V2 closed, V3-V6 ready. Dispatching V3 (Battery Drain) next.

V3 key features from spec:
- Custom battery Shape (rounded rect + nub)
- Fill level = overallScore, color transitions green→yellow→red at 0.6/0.3 thresholds
- Canvas for undulating fill edge with 5 metric control points (bezier curve)
- Lightning bolt (bolt.fill) flashing yellow on drifting
- Critical mode (bad): red fill, red bolt, pulsing red glow, "CRITICAL" label
- Fire: shutdown animation (opacity flash)
- Landscape: vertical battery (nub on top), left 40%, metric column right
- Three previews: good, alert, absent

## 2026-03-17 — Builder: Variant 3 (Battery Drain)

Implemented Variant3View.swift in Quant/Views/Showcase/Variants/ScoreCentric/.
- Custom BatteryShape (Shape struct) with rounded rect body + nub (right for horizontal, top for vertical)
- Fill level mapped to overallScore via Canvas with 5-metric bezier undulating edge
- Battery fill color: green >0.6, yellow 0.3-0.6, red <0.3
- Lightning bolt (bolt.fill) with .symbolEffect(.pulse) in alert mode, yellow on drifting, red on bad
- Drain animation: slow cosmetic drain offset (0→8%) with linear repeatForever on drifting
- Critical mode (bad): red glow pulsing shadow on battery outline, "CRITICAL" text
- Fire: opacity flash (0.8→1.0) triggered by NudgeDecision.fire
- Worst offender zone highlighted with white overlay in Canvas
- Countdown label: "Low posture warning in M:SS" below percentage
- Landscape: vertical battery (nub on top) left 40%, metric column right with icons + names + percentages
- AbsenceOverlay for absent/calibrating states
- Settings gear top-left, haptic feedback on bad state
- Three #Preview blocks: good, alert (drifting + headDrop), absent
- Build clean, tests pending

## 2026-03-17 — Critic: Variant 3 Review (REJECTED)

Build clean (exit 0), 297 tests pass. Found 3 missed requirements:

1. **Missing divider lines**: Spec says "five thin vertical divider lines segment the battery into five zones, one per metric." No divider lines are drawn in the Canvas. The undulating edge exists but zones are not visually delineated. Fix: draw 4 thin vertical lines (between the 5 zones) in the Canvas after the fill, using a semi-transparent stroke.

2. **Worst offender zone missing draining animation**: Spec says zone "highlights with a brighter fill AND a downward-draining animation specific to that segment." Code only has a static `white.opacity(0.2)` rect overlay. Fix: add an animated offset or height reduction on the worst zone to simulate that segment draining faster.

3. **Landscape percentage not inside battery**: Spec says "The percentage label moves inside the battery near the bottom of the fill." Code places `percentageLabelInside` below the battery in a VStack, outside the ZStack. Fix: overlay the label on the battery using a ZStack with `.frame(maxHeight: .infinity, alignment: .bottom)` inside the battery view.

## 2026-03-17 — Builder: Variant 3 Review Fixes

Fixed all 3 issues from review rejection:

1. **Divider lines**: Added 4 thin divider lines in the Canvas after the fill. Horizontal battery: vertical lines dividing width into 5 zones. Vertical battery: horizontal lines dividing height into 5 zones. Styled with `white.opacity(0.15)`, lineWidth 1.

2. **Worst zone draining animation**: Replaced static `white.opacity(0.2)` overlay with animated downward drain. Added `@State worstZoneDrain: CGFloat = 0` that animates 0→0.4 with `linear(duration: 3).repeatForever(autoreverses: true)` during alert mode. The highlight rectangle's top edge moves down proportionally, simulating that zone draining faster.

3. **Landscape percentage inside battery**: Changed landscape layout from VStack (battery above, label below) to ZStack(alignment: .bottom) so `percentageLabelInside` overlays the battery near the bottom with 12pt padding.

Build clean (exit 0), 297 tests pass.

## 2026-03-17 — Critic: Variant 3 Second Review (REJECTED)

Build clean (exit 0), 297 tests pass. Reviewed all 3 fixes from prior rejection — dividers, worst zone drain, landscape label — all implemented. However, found 2 concrete bugs from the same pattern: missing `.onAppear` handlers for `onChange`-driven state.

**Variant2View got this right** — `isCountdownFlashing` has `.onAppear { if isBad { isCountdownFlashing = true } }` (line 154-156), and `VibrationModifier` has `.onAppear { if isActive { isVibrating = true } }` (line 341-343). Variant3View doesn't follow this established pattern.

1. **`worstZoneDrain` animation not started on appear** (concrete bug): The `.onChange(of: data.isAlertMode)` handler at line 194 starts the worst zone draining animation only on state *changes*. If the view appears already in alert mode (e.g., the "Alert Mode" preview), the `onChange` never fires and `worstZoneDrain` stays at 0. The worst zone highlight will be static with no draining animation. Fix: add to the existing `.onAppear` block (line 181) a check for `isAlertMode` to start the `worstZoneDrain` animation.

2. **`isCriticalPulsing` not set on appear** (concrete bug): The `.onChange(of: data.postureState.isBad)` handler at line 185 sets `isCriticalPulsing` only on changes. If the view starts in `.bad` state, the red glow pulse won't activate. Fix: add `.onAppear` check for `postureState.isBad` to set `isCriticalPulsing = true`.

Both are the identical `.onChange`-without-`.onAppear` bug pattern that was already fixed in Variant2View.

## 2026-03-17 — Builder: Variant 3 Third Review Fixes

Fixed 2 bugs from second review rejection (missing `.onAppear` handlers):

1. **`worstZoneDrain` on appear**: Expanded `.onAppear` block to check `observer.data.isAlertMode` — if true, starts the `worstZoneDrain` animation (0→0.4 with linear repeatForever) immediately.

2. **`isCriticalPulsing` on appear**: Added check for `observer.data.postureState.isBad` in `.onAppear` — sets `isCriticalPulsing = true` immediately so the red glow pulse is active from the start.

Both follow the same pattern established in Variant2View. Build clean (exit 0), 297 tests pass.

## 2026-03-17 — Critic: Variant 3 Third Review (REJECTED)

Build clean (exit 0), 297 tests pass. Verified all previous fixes (dividers, worst zone drain, landscape label, worstZoneDrain onAppear, isCriticalPulsing onAppear) are correctly implemented.

However, found 1 concrete bug — the same pattern that was caught and fixed in Variant2View's second review:

1. **Battery fill doesn't force red in `.bad` state** (concrete bug): `batteryFillColor(score:)` at line 481 only uses the score value to determine fill color (green >0.6, yellow 0.3-0.6, red <0.3). It does NOT check `postureState.isBad`. The spec explicitly says: "On `.bad`, the battery enters 'critical' mode: the fill is red." If the aggregate score is above 0.3 during `.bad` state, the fill would be yellow or green — while the bolt is red, the shadow pulses red, and the label says "CRITICAL" in red. This is visually contradictory and spec-non-compliant.

   This is the exact same bug pattern as Variant2View's `outerRingColor()`, which was fixed by adding `if observer.data.postureState.isBad { return red }` at the top of the function (V2 line 293). Fix: add the same check to `batteryFillColor()`, or pass the postureState and force red unconditionally in `.bad`.

## 2026-03-17 — Builder: Variant 3 Fourth Review Fix

Fixed 1 bug from third review rejection:

1. **Battery fill forced red in `.bad` state**: Added `observer.data.postureState.isBad` check at the top of `batteryFillColor(score:)` — returns red unconditionally in bad state, matching the V2 `outerRingColor()` pattern. Build clean (exit 0).

## 2026-03-17 — Critic: Variant 3 Fourth Review (PASSED)

Thorough fresh-eyes review against full spec (variant-catalog-1.md 'Variant 3: Battery Drain'). Verified all 28 spec requirements against code. All 6 fixes from prior review rounds (divider lines, worst zone drain animation, landscape percentage inside battery, worstZoneDrain onAppear, isCriticalPulsing onAppear, batteryFillColor forced red in .bad) confirmed correctly implemented. Build clean (exit 0), 297 tests pass. No bugs, missed requirements, or regressions found. Implementation is faithful to spec.

## 2026-03-17 — Finalizer: Variant 3 Closed, Queue Advance

Closed Variant 3 task (task-1773750652-5820). Verified: build clean (exit 0).

Step 6 progress: 3/6 variants complete (V1 closed, V2 closed, V3 closed). Remaining: V4, V5, V6 open + registry update blocked. Steps 7-16 still ahead. Emitting queue.advance to continue Step 6 implementation.

## 2026-03-17 — Planner: Queue Advance → V4 (Arc Meter)

Received queue.advance after V3 closure. Step 6 wave status: V1, V2, V3 closed; V4, V5, V6 ready; registry blocked. Dispatching V4 (Arc Meter) next.

V4 key features from spec:
- Single wide arc (240°) with LinearGradient stroke (red→yellow→green)
- Glowing marker dot positioned via trigonometry at score position on arc
- Ultra-light score text (128pt, .ultraLight) at center
- Five colored status dots below arc
- Alert mode: marker oscillation animation along arc + countdown bar below
- Landscape: widens arc radius and adjusts layout
- Three previews: good, alert, absent

## 2026-03-17 — Builder: Variant 4 (Arc Meter)

Implemented Variant4View.swift in Quant/Views/Showcase/Variants/ScoreCentric/.
- ArcShape custom Shape struct for the 180° arc
- Thick arc (~20pt stroke) with AngularGradient (green→yellow→red)
- White marker dot (18pt) positioned via cos/sin trigonometry on arc at score position
- Marker glow shadow colored to match arc position (green/yellow/red based on score)
- Score displayed in .system(size: 72, weight: .ultraLight, design: .rounded)
- Five metric names listed vertically with small colored status circles (green <0.5, yellow 0.5-0.8, red >0.8)
- Alert mode: marker oscillation (+/- 5.4° = 3% of 180° arc, 2s period)
- Alert mode: worst offender scales to .title2 with ratio, others become "N metrics OK" summary
- Countdown bar: horizontal line shortening from full width to zero, colored by zone
- Bad state: marker glow becomes aggressive pulsing red halo (radius oscillating 4-36pt)
- Bad state: score number tints red, countdown bar flashes
- Bad state: markerColor forced to red unconditionally
- Landscape: arc stretches wider, metric list repositions to right side, countdown bar spans full width
- AbsenceOverlay for absent/calibrating states
- Settings gear top-right, haptic feedback on bad state
- .onAppear handlers for oscillation, glow pulse, and countdown flash (same pattern as V2/V3)
- Three #Preview blocks: good, alert (drifting + headDrop), absent
- Build clean, tests pending

## 2026-03-17 — Critic: Variant 4 Review (REJECTED)

Build clean (exit 0), 297 tests pass. Thorough spec review against variant-catalog-1.md lines 131-154. Found 3 issues:

1. **Oscillation asymmetric / half-range (concrete animation bug)**: `startOscillation()` animates `markerOscillation` from 0→5.4 with `autoreverses: true`, producing 0→5.4→0→5.4... This is one-sided — the marker shifts +2.7° on average instead of oscillating symmetrically around its position. Spec says "+/- 3% of arc length" = +/- 5.4°, meaning the oscillation should be centered: -5.4→+5.4→-5.4. Fix: initialize `markerOscillation = -5.4` before the withAnimation block that animates to `+5.4`.

2. **Landscape countdown bar not full width (concrete layout bug)**: In `landscapeLayout`, `countdownBar(width: size.width * 0.55)` is inside the left `VStack` of the `HStack`. Spec says: "The countdown bar spans the full landscape width below the arc." The bar should be below both the arc section and the metric list. Fix: wrap the `HStack` in a `VStack` and place the countdown bar outside the HStack at full width.

3. **Gear icon at top-right instead of center-bottom of arc (spec deviation)**: Spec explicitly says "the gear icon is a small element at the exact center-bottom of the arc." The comment in code acknowledges "center-bottom of arc area" but the layout places it at top-right. Fix: position the gear at the center-bottom of the arc, e.g., below the arc horizontally centered.

## 2026-03-17 — Builder: Variant 4 Review Fixes

Fixed all 3 issues from review rejection:

1. **Oscillation symmetric**: Changed `startOscillation()` to set `markerOscillation = -5.4` before animating to `+5.4`. With `autoreverses: true`, this oscillates -5.4→+5.4→-5.4 symmetrically around the score position.

2. **Landscape countdown bar full width**: Wrapped the `HStack` in a `VStack`, moved `countdownBar` outside the HStack at `width: size.width * 0.9` — spans full landscape width below both the arc and metric list.

3. **Gear icon at center-bottom**: Replaced top-right HStack layout with a VStack that pushes gear to bottom-center using `frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)`.

Build clean (exit 0), tests pending.

## 2026-03-17 — Critic: Variant 4 Second Review (REJECTED)

Build clean (exit 0), 297 tests pass. Verified all 3 fixes from prior rejection:
- Oscillation now symmetric (-5.4→+5.4 with autoreverses) ✓
- Landscape countdown bar outside HStack at full width ✓
- Gear icon at bottom-center ✓

All 20+ spec requirements verified. However, found 1 concrete visual bug:

1. **AngularGradient center misaligned with arc center (coordinate space confusion)**: The `AngularGradient` at line 126 uses `center: .init(x: 0.5, y: 0.85)`, but the `ArcShape` draws its path with center at `(rect.midX, rect.midY)` — which is `UnitPoint(0.5, 0.5)` in the shape's coordinate space. The `0.85` value was copied from `centerY = size.height * 0.85` (the arc's position in the *parent* view), but the gradient's center is in UnitPoint space relative to the *shape's own frame*. With the gradient center offset from the arc's geometric center, the angular gradient's color-to-angle mapping is rotated — colors on the arc don't transition evenly green (left) → yellow (top) → red (right) as the spec requires. The marker's computed shadow color (from `markerColor(score:)`) will visually disagree with the arc's actual gradient color at the marker's position. Fix: change `center: .init(x: 0.5, y: 0.85)` to `center: .center`.

## 2026-03-17 — Builder: Variant 4 Third Review Fix

Fixed 1 bug from second review rejection:

1. **AngularGradient center aligned**: Changed `center: .init(x: 0.5, y: 0.85)` to `center: .center` in the AngularGradient stroke. The 0.85 was incorrectly copied from the arc's parent-view Y position (`size.height * 0.85`) but the gradient center uses UnitPoint space relative to the shape's own frame, where center is (0.5, 0.5). Build clean (exit 0), all tests pass.
