# Implementation Plan: Posture Metrics UI Variants

**Project:** Quant — Posture Metrics UI Variants
**Date:** 2026-03-16
**Status:** Ready for Implementation

**Design documents:**
- `.agents/planning/2026-03-16-ui-variants/design/detailed-design.md`
- `.agents/planning/2026-03-16-ui-variants/design/variant-catalog-1.md` (Variants 1–20)
- `.agents/planning/2026-03-16-ui-variants/design/variant-catalog-2.md` (Variants 21–40)
- `.agents/planning/2026-03-16-ui-variants/design/variant-catalog-3.md` (Variants 41–60)

---

## Checklist

- [x] **Step 1** — Shared data layer: `MetricKey`, `MetricInfo`, `PostureDisplayData`, factory
- [x] **Step 2** — Mock data source: simulation state machine, manual controls
- [x] **Step 3** — Live data source: `LivePostureDataSource` wrapping `AppModel`
- [x] **Step 4** — Showcase navigation shell: `VariantShowcaseView`, `VariantDescriptor`, mock/live toggle, settings sheet
- [x] **Step 5** — Shared visual utilities: `PostureVisualStyle`, animation helpers, reusable sub-views
- [x] **Step 6** — Variant batch A: Score-Centric (Variants 1–6)
- [ ] **Step 7** — Variant batch B: Dashboard / Multi-Metric (Variants 7–12)
- [ ] **Step 8** — Variant batch C: Minimal / Typographic (Variants 13–20)
- [ ] **Step 9** — Variant batch D: Abstract Geometric (Variants 21–28)
- [ ] **Step 10** — Variant batch E: 3D / Body / Instrument (Variants 29–40)
- [ ] **Step 11** — Metal shader infrastructure and shader-driven variants (Variants 43, 47, 51–54, and others using `.distortionEffect`/`.colorEffect`)
- [ ] **Step 12** — SceneKit / 3D infrastructure and 3D variants
- [ ] **Step 13** — Variant batch F: Organic / Nature (Variants 41–46)
- [ ] **Step 14** — Variant batch G: Gamified (Variants 47–54)
- [ ] **Step 15** — Variant batch H: Architectural / Structural (Variants 55–60)
- [ ] **Step 16** — Polish, accessibility, performance

---

## Implementation Steps

---

### Step 1 — Shared Data Layer

**Objective:** Define the canonical data model that every subsequent component depends on. This is the foundation. Nothing else can be built without it.

**Implementation guidance:**

Create a new Swift package target `PostureUI` (or a new group inside `Quant/`) containing the following files. The design document section 4 defines the full interface; implement exactly that.

1. `MetricKey.swift` — `public enum MetricKey: String, CaseIterable, Identifiable` with `displayName` and `symbolName` computed properties. Maps to the five fields of `RawMetrics` (`forwardCreep`, `headDrop`, `shoulderRounding`, `lateralLean`, `twist`).

2. `MetricInfo.swift` — `public struct MetricInfo` with fields: `key: MetricKey`, `value: Float`, `ratio: Float`, `threshold: Float`, `isWorstOffender: Bool`. Computed properties: `isExceeded: Bool`, `clampedRatio: Float`.

3. `PostureDisplayData.swift` — `public struct PostureDisplayData` with fields: `metrics: [MetricInfo]` (always five in canonical order), `postureState: PostureState`, `nudgeDecision: NudgeDecision`, `trackingQuality: TrackingQuality`, `worstOffender: MetricInfo?`, `timeInCurrentState: TimeInterval?`, `nudgeCountdownSeconds: TimeInterval?`, `thresholds: PostureThresholds`. Computed properties: `aggregateScore: Float`, `isAlertMode: Bool`, `metric(for:) -> MetricInfo`.

4. `PostureDisplayData+Make.swift` — `extension PostureDisplayData` with the static factory `make(from:postureState:nudgeDecision:trackingQuality:thresholds:) -> PostureDisplayData`. Uses `abs(rawValue) / threshold` for each ratio, identifies worst offender, extracts countdown from `.pending` case. Handles nil `RawMetrics` by substituting zero values. See design doc section 4.5 for the full algorithm.

5. `RawMetrics+Extensions.swift` — Convenience extension on the existing `RawMetrics` type:
   - `static var zero: RawMetrics` sentinel with all values at 0.0
   - `func value(for key: MetricKey) -> Float` subscript-style accessor

6. `PostureThresholds+Extensions.swift` — Convenience extension on the existing `PostureThresholds` type:
   - `func threshold(for key: MetricKey) -> Float` accessor mapping each `MetricKey` to its `PostureThresholds` field

7. `PostureDataSourceProtocol.swift` — `protocol PostureDataSourceProtocol: ObservableObject` with `var currentData: PostureDisplayData { get }`.

8. `PostureDisplayObserver.swift` — `@MainActor class PostureDisplayObserver: ObservableObject` holding `@Published var data: PostureDisplayData` and a `func switchSource(to:)` method. This is the `@EnvironmentObject` that all variant views read.

**Test requirements:**

All tests live in `QuantTests/`.

- `MetricKeyTests`: verify `allCases` has exactly 5 cases; verify each case has a non-empty `displayName` and `symbolName`.
- `MetricInfoTests`: verify `isExceeded` is true when ratio >= 1.0 and false otherwise; verify `clampedRatio` caps at 1.0.
- `PostureDisplayDataMakeTests`:
  - Given a `RawMetrics` with `forwardCreep = 0.03` and `forwardCreepThreshold = 0.03`, the resulting `MetricInfo` for `.forwardCreep` has `ratio == 1.0`.
  - Given nil `RawMetrics`, all five `MetricInfo` values have `ratio == 0.0`.
  - `worstOffender` is the metric with highest ratio; nil when all ratios are zero.
  - `aggregateScore` is 1.0 when all ratios are 0.0 and 0.0 when all ratios are 1.0.
  - `isAlertMode` is true for `.drifting` and `.bad`, false for `.good`, `.absent`, `.calibrating`.
  - `nudgeCountdownSeconds` is non-nil only when `nudgeDecision` is `.pending`.
- `RawMetricsExtensionTests`: verify `.zero` returns all-zero values; verify `value(for:)` returns the correct field for each key.
- `PostureThresholdsExtensionTests`: verify `threshold(for:)` returns the correct field for each key.

**Integration notes:**

`PostureDisplayData` and its helpers do not import SwiftUI — they are pure Swift. They import `PostureLogic` only for the existing types (`RawMetrics`, `PostureState`, `NudgeDecision`, `PostureThresholds`, `TrackingQuality`). This ensures they are unit-testable without any UI dependencies.

**Demo description:** No visible UI yet. All tests pass in the `QuantTests` target.

---

### Step 2 — Mock Data Source

**Objective:** Build a self-contained data source that generates realistic posture simulation without any camera or pipeline dependency. This enables all subsequent UI development to proceed without a physical device or live camera session.

**Implementation guidance:**

Create `MockPostureDataSource.swift`:

1. `@MainActor final class MockPostureDataSource: ObservableObject, PostureDataSourceProtocol`

2. Published properties exposed to `MockControlsInspector`:
   - `@Published var manualForwardCreep: Float = 0.0` (and for each of the five metrics)
   - `@Published var manualPostureState: PostureState = .good`
   - `@Published var isAutoSimulating: Bool = true`
   - `@Published var simulationSpeedMultiplier: Double = 1.0`

3. Simulation state machine (private). See design doc section 5.2 for the phase diagram and descriptions. Implement the four phases:
   - **Good phase (8–12s):** All metrics animated with subtle Perlin-noise-like variation (layered sine waves at different frequencies, ±5% of threshold amplitude). Use two or three sine terms per metric with irrational frequency ratios to avoid obvious periodicity.
   - **Drifting phase (15–30s):** One or two metrics ramp up using an ease-in curve. Pick the dominant metric randomly from `MetricKey.allCases`. `postureState` becomes `.drifting(since:)`. `nudgeDecision` becomes `.pending(reason:, timeRemaining:)` where `timeRemaining` counts down from `PostureThresholds.slouchDurationBeforeNudge`.
   - **Bad phase (10–20s):** Metrics remain elevated. `postureState` is `.bad(since:)`. `nudgeDecision` fires `.fire(reason:)` once at phase start, then returns to `.none` after 2 seconds.
   - **Recovery:** Metrics ease back to zero over 3–5 seconds on transition to Good.

4. Timer-driven update loop at 30Hz using `Timer.scheduledTimer`. Each tick advances the simulation clock by `(1.0 / 30.0) * simulationSpeedMultiplier` seconds, recomputes `RawMetrics`-equivalent values from the current phase, and calls `PostureDisplayData.make(...)`.

5. When `isAutoSimulating == false`, use the manual slider values directly instead of the simulation engine. Build `RawMetrics` from the manual values and the default thresholds.

6. Static convenience factory for Xcode previews:
   ```swift
   static func preview(
       state: PostureState,
       worstMetric: MetricKey? = nil,
       worstRatio: Float = 0.0
   ) -> MockPostureDataSource
   ```
   Returns a non-animating instance with `isAutoSimulating = false` and sliders set to produce the requested state. Used in `#Preview` blocks.

**Test requirements:**

- `MockPostureDataSourceSimulationTests`:
  - After constructing with `isAutoSimulating = true`, run the simulation loop for a simulated 90 seconds (using `simulationSpeedMultiplier = 100.0` to fast-forward synchronously in tests) and verify at least one full Good → Drifting → Bad → Good cycle occurred.
  - Verify that `currentData.postureState` transitions through all expected states.
  - Verify that `currentData.nudgeCountdownSeconds` is non-nil during the drifting phase.
  - Verify that `currentData.nudgeDecision` equals `.fire` for at least one emission during the bad phase.

- `MockPostureDataSourceManualTests`:
  - With `isAutoSimulating = false`, setting `manualForwardCreep = PostureThresholds().forwardCreepThreshold` produces a `currentData` where the `forwardCreep` metric has `ratio == 1.0`.
  - Setting `manualPostureState = .bad(since: ...)` with all metrics at zero does not crash.

- `MockPostureDataSourcePreviewTests`:
  - `MockPostureDataSource.preview(state: .good)` returns `currentData.postureState == .good`.
  - `MockPostureDataSource.preview(state: .drifting(...), worstMetric: .headDrop, worstRatio: 1.3)` returns `currentData.worstOffender?.key == .headDrop` and `currentData.worstOffender?.ratio ≈ 1.3`.

**Integration notes:**

`MockPostureDataSource` imports only `PostureLogic` and Foundation. It does not import SwiftUI. The timer must be invalidated in `deinit` to avoid memory leaks. Provide a `func stopSimulation()` that can be called in tests to prevent timer lingering.

**Demo description:** No visible UI yet. All unit and simulation tests pass. Confirm in the REPL or test suite that the simulation cycles correctly through states.

---

### Step 3 — Live Data Source

**Objective:** Build the adapter that bridges `AppModel`'s existing published properties to `PostureDisplayData`. After this step, the entire data pipeline is connected end-to-end, even though no variant UI exists yet.

**Implementation guidance:**

Create `LivePostureDataSource.swift`:

1. `@MainActor final class LivePostureDataSource: ObservableObject, PostureDataSourceProtocol`

2. Subscribes to `AppModel` via `Combine`. Use `Publishers.CombineLatest4` combining `appModel.$latestMetrics`, `appModel.$postureState`, `appModel.$nudgeDecision`, `appModel.$trackingQuality`. Each emission calls `PostureDisplayData.make(...)`. The `thresholds` are read directly from `appModel.postureThresholds` inside the map closure (capturing `[weak appModel]`) so threshold changes also propagate.

3. See design doc section 5.1 for the complete interface and implementation pattern.

4. Initialize `currentData` synchronously from `appModel`'s current values before any Combine subscription fires, so the first render has valid data.

**Test requirements:**

- `LivePostureDataSourceTests`:
  - Construct with a mock `AppModel` (or a test double that publishes the same properties). Publish a new `latestMetrics` value and verify `currentData` updates within one RunLoop tick.
  - Verify that a change to `appModel.postureState` alone (with metrics constant) triggers an update to `currentData.postureState`.
  - Verify that `currentData` is never nil after initialization (even when `appModel.latestMetrics` is nil).
  - Verify that threshold changes in `appModel.postureThresholds` propagate: change `forwardCreepThreshold`, publish a new `latestMetrics`, and verify the updated ratio in `currentData`.

**Integration notes:**

`LivePostureDataSource` is constructed once in `VariantShowcaseView` (Step 4) and reused while the showcase is on screen. It should be torn down (subscriptions cancelled) when the showcase disappears, which happens automatically when the `VariantShowcaseView` goes out of scope (since `LivePostureDataSource` is a `@StateObject`).

Do not add any navigation or UI in this step. The goal is a tested, working data bridge.

**Demo description:** All tests pass. Confirmed via test output that `LivePostureDataSource` reacts correctly to `AppModel` changes.

---

### Step 4 — Showcase Navigation Shell

**Objective:** Build the `VariantShowcaseView` with a navigable list of all 60 variant slots, the mock/live data source toggle, and the settings sheet entry point. At this point all 60 variant slots are stubbed with placeholder views, but the full navigation and data flow infrastructure is in place and demoable.

**Implementation guidance:**

Create the following files (all in `Quant/Views/Showcase/` or similar):

1. `VariantDescriptor.swift` — `struct VariantDescriptor: Identifiable, Hashable` with fields `id: Int`, `name: String`, `category: VariantCategory`, `technologies: [TechTag]`, `makeView: () -> AnyView`. See design doc section 5.4. `VariantCategory` and `TechTag` enums as defined there.

2. `VariantRegistry.swift` — A static `let allVariants: [VariantDescriptor]` array listing all 60 variants by name, category, and tech tags. For now, every variant's `makeView` returns `AnyView(VariantPlaceholderView(descriptor: descriptor))`. This file will be updated in each variant batch step to replace placeholders with real views.

3. `VariantPlaceholderView.swift` — A simple SwiftUI view showing the variant number, name, and category in a centered `VStack`. Reads `@EnvironmentObject var observer: PostureDisplayObserver` and displays the current `postureState` as text. This confirms the environment injection works end-to-end.

4. `DataSourceMode.swift` — `enum DataSourceMode: String, CaseIterable` with cases `.mock` and `.live`.

5. `DataSourceToggleView.swift` — A `Picker` or segmented control bound to `DataSourceMode`.

6. `VariantShowcaseView.swift` — The root view. See design doc section 5.3 for the full interface. Key behaviors:
   - `@StateObject private var mockSource = MockPostureDataSource()`
   - `@StateObject private var liveSource: LivePostureDataSource` initialized lazily from `@EnvironmentObject var appModel: AppModel`
   - `@State private var dataSourceMode: DataSourceMode = .mock`
   - `@State private var selectedVariant: VariantDescriptor?`
   - `@State private var showingSettings: Bool = false`
   - In portrait: `NavigationStack` with a list that pushes to the variant detail.
   - In landscape (regular horizontal size class): `NavigationSplitView` with sidebar + detail.
   - Toolbar: mock/live picker on the leading side, settings gear on the trailing side.
   - The `activeObserver: PostureDisplayObserver` computed property switches between mock and live sources based on `dataSourceMode`.
   - The `PostureDisplayObserver` is injected into the detail view via `.environmentObject(activeObserver)`.

7. `VariantCatalogList.swift` — A `List` with `Section` grouping by `VariantCategory`, listing all variants from `VariantRegistry.allVariants`. Each row shows the variant number, name, and a `HStack` of `TechTag` badges.

8. `SettingsSheetView.swift` — A modal sheet that wraps the existing `CalibrationSettingsView` (already in the codebase) and adds a posture thresholds panel, camera mode picker, camera preview toggle, haptic picker, and test nudge button (migrating controls from `DebugOverlayView`). Route to this via `.sheet(isPresented: $showingSettings)`.

9. `MockControlsInspector.swift` — A `@EnvironmentObject var mockSource: MockPostureDataSource` view presenting the auto-simulate toggle, per-metric sliders, and state override buttons as defined in design doc section 5.6. Presented as a bottom sheet (`.sheet` or `.overlay`) accessible from the variant detail view when `dataSourceMode == .mock`.

**Connect the showcase to the app:** In `ContentView.swift` (or wherever the app's root navigation lives), add a navigation link or toolbar button to `VariantShowcaseView`. Pass `appModel` as an environment object.

**Test requirements:**

- `VariantRegistryTests`:
  - `allVariants.count == 60`
  - All variant IDs are unique and span 1–60.
  - All `VariantCategory` cases have at least one variant.
  - Every `makeView` closure can be called without crashing (instantiate each and verify it is non-nil).

- `VariantShowcaseViewTests` (Xcode previews, not unit tests):
  - `#Preview("Showcase — Mock")`: Showcase with `dataSourceMode = .mock`, shows the category list.
  - `#Preview("Showcase — Placeholder Selected")`: Showcase with `selectedVariant` set to variant 1 (placeholder), confirms the placeholder view renders.

- `SettingsSheetViewTests`:
  - Verify the settings sheet can be presented without crash by constructing it with an injected `AppModel`.

**Integration notes:**

`LivePostureDataSource` is initialized with `appModel` inside `VariantShowcaseView`. The `VariantShowcaseView` must receive `AppModel` as an `@EnvironmentObject`, which it already gets from the existing app entry point. Do not instantiate `AppModel` a second time.

`PostureDisplayObserver` must be recreated whenever `dataSourceMode` changes, not reused. Use a computed property that creates a new observer each time, or use `switchSource(to:)`. Avoid creating new observers on every render; use `@State` to hold the observers and update them reactively.

**Demo description:** Launch the app. Tap the showcase entry point. See a scrollable list of 60 variant slots organized by category. Tap any variant and see the placeholder view showing the variant name and current posture state (from mock data). Toggle mock/live — the posture state label updates when on live mode and the camera is running. Tap the gear icon to open the settings sheet. Confirm the mock controls inspector appears as a bottom sheet from the variant detail.

---

### Step 5 — Shared Visual Utilities

**Objective:** Build the shared styling, color, animation, and reusable sub-view infrastructure that all 60 variant implementations will draw on. This step prevents code duplication across variants and ensures semantic consistency.

**Implementation guidance:**

Create `PostureVisualStyle.swift` and companion files:

1. `PostureVisualStyle.swift` — `enum PostureVisualStyle` namespace (no cases, no instances). Implement exactly the static functions from design doc section 5.8:
   - `static func stateColor(for state: PostureState) -> Color`
   - `static func metricColor(ratio: Float) -> Color`
   - `static func stateLabel(for state: PostureState) -> String`
   - Additional helpers: `static func nudgeCountdownLabel(seconds: TimeInterval) -> String` (formats as "M:SS"), `static func stateAccessibilityLabel(for state: PostureState, worstOffender: MetricInfo?) -> String`.

2. `PostureAnimations.swift` — Constants and factory functions for animations used across multiple variants:
   - `static let alertOnset: Animation` — `.spring(response: 0.6, dampingFraction: 0.7)`
   - `static let metricUpdate: Animation` — `.interpolatingSpring(stiffness: 200, damping: 15)`
   - `static let nudgePulse: Animation` — `.easeInOut(duration: 1.2).repeatForever(autoreverses: true)`
   - `static let modeTransition: Animation` — `.easeInOut(duration: 0.35)`

3. `MetricRatioBar.swift` — A reusable horizontal bar for a single metric. Props: `info: MetricInfo`, `showLabel: Bool`, `showValue: Bool`. Used by variants that show a secondary row of metric bars (e.g., Variants 1, 4, 9). Handles the green-yellow-red fill color interpolation, threshold marker line, and animation.

4. `NudgeCountdownLabel.swift` — A reusable label that displays the nudge countdown. Props: `seconds: TimeInterval?`, `style: NudgeCountdownStyle` (enum with `.compact` "3:45", `.verbose` "Nudge in 3m 45s", `.hud` "T-3:45"). Returns `EmptyView` when `seconds == nil`.

5. `SettingsGearButton.swift` — A reusable settings entry point button. Props: `action: () -> Void`. Renders a `gearshape.fill` SF Symbol with appropriate padding and tap target size. Used by variants that want the standard corner placement.

6. `PostureStateAmbientBackground.swift` — A subtle background color/gradient that shifts with posture state. Used as a `.background()` modifier on variants that want ambient state-responsive coloring. Props: `state: PostureState`, `intensity: Double` (0.0–1.0).

7. `AbsenceOverlay.swift` — A reusable overlay for the `.absent` state that shows a gentle pulsing "Waiting for pose..." indicator in the variant's visual language. Props: a closure `content: () -> Content` for the dimmed underlying view.

**Test requirements:**

- `PostureVisualStyleTests`:
  - `stateColor(for: .good)` returns the documented teal-green hue (verify hue component is approximately 0.38 ± 0.05).
  - `stateColor(for: .bad)` returns the documented coral-red hue.
  - `metricColor(ratio: 0.0)` returns a green hue (hue ≈ 0.35).
  - `metricColor(ratio: 1.0)` returns a red hue (hue ≈ 0.0).
  - `metricColor(ratio: 2.0)` is identical to `metricColor(ratio: 1.0)` (clamped).
  - `nudgeCountdownLabel(seconds: 275)` returns "4:35".
  - `nudgeCountdownLabel(seconds: 0)` returns "0:00".

- Xcode preview for each reusable component confirming it renders in both light and dark mode.

**Integration notes:**

These files do not replace any variant-specific styling. Variants are free to deviate from `PostureVisualStyle` for their own aesthetic. These utilities are conveniences, not constraints.

**Demo description:** No new visible feature. Confirm that `PostureVisualStyle` functions return correct colors and labels in unit tests.

---

### Step 6 — Variant Batch A: Score-Centric (Variants 1–6)

**Objective:** Implement the first six variants, establishing the full pattern for all subsequent variant batches: Xcode previews, real-time mode, alert mode with animated transition, orientation adaptation, absent/calibrating states, and integration with `VariantRegistry`.

**Variants in this batch:**
- Variant 1: Precision Gauge
- Variant 2: Triadic Rings
- Variant 3: Battery Drain
- Variant 4: Arc Meter
- Variant 5: Numeric Countdown
- Variant 6: Traffic Light

**Implementation guidance:**

For each variant, create `Variant{N}View.swift` (e.g., `Variant1View.swift`) in `Quant/Views/Showcase/Variants/ScoreCentric/`. Each file follows the canonical variant structure from design doc section 5.5:

```swift
struct Variant1View: View {
    @EnvironmentObject var observer: PostureDisplayObserver
    // local UI state only
    var body: some View { ... }
}
```

Refer to the variant-catalog-1.md for exact visual specifications, key SwiftUI techniques, landscape adaptation, and distinguishing features for each variant. Do not reproduce those specs here; use the catalog as the implementation reference.

**Shared implementation notes for this batch:**

- `postureData.data.isAlertMode` drives the mode transition. Use `.animation(PostureAnimations.alertOnset, value: observer.data.isAlertMode)` on the outermost container.
- The settings entry point for each variant should present `SettingsSheetView` via `@State private var showingSettings = false` and `.sheet(isPresented: $showingSettings)`.
- Use `GeometryReader` at the outermost level to get the available size. Branch on `geometry.size.width > geometry.size.height` for landscape vs. portrait layouts.
- Handle `.absent` and `.calibrating` states explicitly. At minimum: show the variant's visual structure at zero/neutral values with a `.opacity(0.4)` treatment and a brief "Waiting" or "Calibrating" text overlay.
- Absent state must NOT display metric values or ratios — use neutral/zero visual positions only.

**After implementing each view**, update `VariantRegistry.allVariants` to replace the placeholder with the real view for that variant ID.

**Test requirements:**

For each variant (repeat this test pattern):

- Three `#Preview` blocks per variant: good-posture real-time mode, alert mode (worst offender chosen to best illustrate the variant's alert design), and absent state. Each preview in both light and dark color schemes.
- Snapshot-style note: visually verify in Xcode Preview that:
  - The real-time mode shows all 5 metrics.
  - The alert mode focuses on the worst offender with visible countdown.
  - The absent state shows a neutral, non-misleading placeholder.
  - Portrait and landscape previews both lay out without clipping.

- `VariantBatchAIntegrationTests`:
  - Variants 1–6 are registered in `VariantRegistry.allVariants` with correct IDs, names, and categories.
  - Each `makeView()` closure returns a non-nil `AnyView`.

**Integration notes:**

Update `VariantRegistry` at the end of this step. All six placeholder entries for IDs 1–6 become real views. The showcase list and navigation already work from Step 4; no navigation changes needed.

**Demo description:** Launch the showcase. Navigate to any of the six Score-Centric variants. Watch the mock simulation cycle from good (real-time mode) through drifting (alert onset) to bad (full alert). Rotate the device to confirm landscape adaptation. Toggle to live mode and verify the variant responds to real camera data. All six variants are demoable in sequence.

---

### Step 7 — Variant Batch B: Dashboard / Multi-Metric (Variants 7–12)

**Objective:** Implement six information-dense variants that give equal visual weight to all five metrics simultaneously.

**Variants in this batch:**
- Variant 7: Five-Bar Equalizer
- Variant 8: Donut Breakdown
- Variant 9: Horizontal Rails
- Variant 10: Radial Dial Array
- Variant 11: Digital Cockpit
- Variant 12: Split Flap Display

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/Dashboard/`. Refer to variant-catalog-1.md for full visual specifications.

Key technical notes for this batch:

- **Variant 7 (Five-Bar Equalizer):** The `Canvas`-based flame particle effect requires `TimelineView(.animation)` wrapping. Particles are small `Circle` paths with a random y-offset that increases per frame. Pool 8–12 particles per bar; reset when a particle reaches the top. The shatter effect at the threshold line is a `Canvas` drawing of 6–8 short lines radiating from the threshold point, revealed once and not looped.

- **Variant 8 (Donut Breakdown):** The variable-radius donut requires a custom `Shape` that computes five arc segments using `Path.addArc(center:radius:startAngle:endAngle:clockwise:)` with per-segment outer radius. Smooth the boundaries between adjacent segments with a short bezier curve connecting the outer-edge endpoints. The `.rotationEffect` animation in bad state uses `Animation.linear(duration: 30).repeatForever(autoreverses: false)`.

- **Variant 9 (Horizontal Rails):** The "overflow" effect (fill bar extending past track) is achieved by conditionally removing `.clipShape` on the worst offender's fill rectangle in bad state. The shimmer highlight is a `LinearGradient` (`clear → white.opacity(0.3) → clear`) with an `.offset(x:)` animation that moves from -barWidth to +barWidth and `Animation.linear(duration: 1.5).repeatForever(autoreverses: false)`.

- **Variant 10 (Radial Dial Array):** Pentagon positioning: center offsets are `CGPoint(x: r * cos(angle), y: r * sin(angle))` where `angle = -90° + i * 72°` for i in 0..<5. The "fracture" path is a pre-computed static jagged `Path` rendered via `trim(from: 0, to:)` with a short animation when `.fire` occurs.

- **Variant 11 (Digital Cockpit):** Force `.preferredColorScheme(.dark)` for this variant only using `.environment(\.colorScheme, .dark)`. The attitude indicator horizon tilt is `lateralLean.ratio * 30 degrees` rotationEffect. Altimeter tape scrolling: use `Canvas` drawing numbers offset by `overallScore * tapeHeight`, where `tapeHeight` covers values 0–100.

- **Variant 12 (Split Flap Display):** Each character cell is a `VStack(spacing: 0)` of two `ZStack` views (top half and bottom half), each clipped to half height via `.clipped()` with `.clipShape(Rectangle().inset(by: ...))`. The flip uses `rotation3DEffect(.degrees(angle), axis: (1, 0, 0), anchor: .bottom)` for the outgoing top half and `.anchor: .top` for the incoming bottom half. Drive the stagger via a `Task` with `try? await Task.sleep(nanoseconds: UInt64(charIndex) * 150_000_000)` per character.

**Test requirements:**

- Three `#Preview` blocks per variant (good, alert, absent).
- `VariantBatchBIntegrationTests`: Variants 7–12 are registered correctly; all `makeView()` closures are callable.
- Specific behavior tests:
  - `Variant7Tests`: Verify that the flame particle canvas does not produce NaN offsets when metric ratio is 0.0.
  - `Variant12Tests`: Verify that `SplitFlapCharacter` cycles from 'A' to the target character in the correct number of steps; verify the cascade stagger produces distinct start times for each character position.

**Integration notes:**

Update `VariantRegistry` entries 7–12. No other infrastructure changes needed.

**Demo description:** All 12 score-centric and dashboard variants are navigable from the showcase. In particular, the Split Flap's character cascade animation and the Donut Breakdown's bad-state rotation are visually striking and confirm that complex animations work within the mock simulation cycle.

---

### Step 8 — Variant Batch C: Minimal / Typographic (Variants 13–20)

**Objective:** Implement eight variants that communicate posture state through typography, color fields, and negative space rather than charts or gauges.

**Variants in this batch:**
- Variant 13: Single Word
- Variant 14: Color Field
- Variant 15: Breathing Orb
- Variant 16: Monogram
- Variant 17: Haiku
- Variant 18: Score + Stripe
- Variant 19: Shadow People
- Variant 20: Ink Wash

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/Minimal/`. Refer to variant-catalog-1.md for full visual specifications.

Key technical notes for this batch:

- **Typographic variants (13, 16, 17):** Use `contentTransition(.numericText())` (iOS 17+) where scores change as digits. Use `GeometryReader` to calculate `dynamicSize` so text fills the desired proportion of the screen.

- **Color Field (14):** The full-screen color transition uses `Color(hue:saturation:brightness:)` interpolating based on `aggregateScore`. Drive `.animation(.easeInOut(duration: 1.5), value: observer.data.aggregateScore)` on the background color for a slow, atmospheric shift.

- **Breathing Orb (15):** The scale oscillation for the "breathing" idle animation uses `withAnimation(.easeInOut(duration: breathingPeriod).repeatForever(autoreverses: true)) { scale = 1.08 }` where `breathingPeriod` interpolates from 4.0s (good) to 1.5s (bad), implemented by restarting the animation when the state changes.

- **Ink Wash (20):** If a Metal shader is not available for the ink diffusion effect, implement using `Canvas` with multiple overlapping semi-transparent `Circle` fills with random slight offsets and `.blur(radius: 8)` applied to each, driven by `TimelineView`. This produces a credible organic ink effect without Metal.

**Test requirements:**

- Three `#Preview` blocks per variant.
- `VariantBatchCIntegrationTests`: Variants 13–20 registered correctly.
- Verify `contentTransition(.numericText())` variants do not crash when score transitions from nil to a valid value (edge case at launch).

**Integration notes:**

Update `VariantRegistry` entries 13–20.

**Demo description:** The 20 variants across Score-Centric, Dashboard, and Minimal categories are all navigable and demoable. The contrast between information-dense Dashboard variants and the radical simplicity of Single Word (Variant 13) or Color Field (Variant 14) illustrates the full design spectrum available.

---

### Step 9 — Variant Batch D: Abstract Geometric (Variants 21–28)

**Objective:** Implement eight variants based on abstract geometric primitives that encode posture through shape deformation, spatial arrangement, and physics-based motion.

**Variants in this batch:**
- Variant 21: Stacked Totem
- Variant 22: Radar Glyph
- Variant 23: Concentric Target (motion trails)
- Variant 24: Pendulum Array (physics simulation)
- Variant 25: Tensegrity (catenary cables)
- Variant 26: Lissajous Figure
- Variant 27: Voronoi Cells
- Variant 28: Morphing Blob

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/AbstractGeometric/`. Refer to variant-catalog-2.md for full visual specifications.

Key technical notes for this batch:

- **Variant 21 (Stacked Totem):** All three primitives are drawn in a single `Canvas`. The deformation parameters (stem curve control point offset, shoulder line arc depth, head circle y-offset, lateral lean x-offset, twist rotation) are computed from the five metric ratios and passed to the canvas draw closure via `@Binding` or a local `@State` struct. Use `withAnimation(PostureAnimations.metricUpdate)` when metric values change. The `Canvas` resolves symbol images for metric labels via `context.resolveSymbol(id:)`.

- **Variant 22 (Radar Glyph):** Compute pentagon vertex positions using `angle = startAngle + i * (2π / 5)`. Polygon path uses `move(to: vertex[0])` then `addLine(to:)` for each remaining vertex. Fill the polygon with `.color(fillColor.opacity(0.3))`. Stroke in `.color(strokeColor)`. In alert mode, use `matchedGeometryEffect` on the worst-offender vertex to drive its position change visually.

- **Variant 23 (Concentric Target):** Implement a ring buffer per metric as a `struct` holding a fixed-size array of 30 `CGPoint` values and a write index. Each `TimelineView` tick appends the current metric dot position. The trail is rendered as a `Path` connecting the buffered points with decreasing opacity using `context.drawLayer`.

- **Variant 24 (Pendulum Array):** Physics simulation runs inside `TimelineView(.animation)`. Each pendulum has a stored `velocity` and `angle`. Each frame: `angle += velocity * dt`, apply damping `velocity *= 0.97`, apply restoring force `velocity -= springConstant * (angle - targetAngle) * dt`. This gives organic overshoot and settling without a full physics engine.

- **Variant 25 (Tensegrity):** Catenary curve: approximate with a quadratic Bezier where the control point's y-offset below the straight line = `sagDepth * (1 - tension)`. Draw cables as `Path` with `addQuadCurve(to:control:)`. Tension per cable is derived from the relevant metric ratio — see variant-catalog-2.md for the per-cable metric mapping.

**Test requirements:**

- Three `#Preview` blocks per variant.
- `VariantBatchDIntegrationTests`: Variants 21–28 registered correctly.
- `PendulumPhysicsTests`: Given a pendulum at angle 0 with a target angle of 30 degrees, verify it reaches within 1 degree of 30 degrees within 50 simulation steps (1/60s each) and does not oscillate indefinitely (settles within 200 steps).
- `RadarGlyphTests`: Verify the polygon path has exactly 5 vertices for any valid `PostureDisplayData` input and that no vertex is `NaN` or `Inf`.

**Integration notes:**

Update `VariantRegistry` entries 21–28. The physics simulations in Variants 24 and 25 run only while those views are on screen (driven by `TimelineView` inside the variant body). No background computation occurs.

**Demo description:** Navigate to the Pendulum Array (Variant 24) and observe the spring-damped settling behavior as mock metrics change. Navigate to the Radar Glyph (Variant 22) and observe the pentagon morphing during the alert transition. The Abstract Geometric category's variants all emphasize tactile, physics-like motion that contrasts with the static chart-based Dashboard variants.

---

### Step 10 — Variant Batch E: 3D / Body / Instrument (Variants 29–40)

**Objective:** Implement twelve variants covering the 3D/Body and Flight/Engineering Instrument categories. These are generally the most complex SwiftUI-only variants, combining spatial reasoning with real-time metric encoding.

**Variants in this batch:**
- Variant 29: Wire Skeleton
- Variant 30: Posture Shadow
- Variant 31: Body Heat Map
- Variant 32: Muscle Tension Map
- Variant 33: Bubble Chart
- Variant 34: Sankey Flow
- Variant 35: Timeline Waterfall
- Variant 36: Horizon Horizon
- Variant 37: Altimeter Stack
- Variant 38: Seismograph
- Variant 39: Compass Rose
- Variant 40: Periscope

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/ThreeDInstrument/`. Refer to variant-catalog-2.md for full visual specifications.

Key technical notes for this batch:

- **Wire Skeleton (29):** Draw as a connected stick figure using `Canvas`. Joint positions are computed from metric ratios: spine base fixed at center-bottom, spine top displaced by `forwardCreep.ratio * maxForwardOffset`, head displaced further by `headDrop.ratio * headDropOffset`, shoulder endpoints displaced by `shoulderRounding.ratio * roundingOffset`, etc. Store joint positions in a struct and compute them in a pure function for testability.

- **Posture Shadow (30):** A silhouette of a human figure rendered as a single filled `Path`. When posture is good, the silhouette is upright and symmetric. Deformations are applied as affine transforms on sub-regions of the path. Use a pre-authored set of control points for "good" and "bad" shapes, then interpolate between them using `MetricInfo.clampedRatio`.

- **Body Heat Map (31):** Render five colored overlapping `Ellipse` shapes positioned over approximate body regions, each filled with a `RadialGradient` from `metricColor(ratio:)` at the center to `clear` at the edge. The body outline beneath them is a simplified stick figure or silhouette.

- **Seismograph (38):** A scrolling waveform. Maintain a `CircularBuffer<Float>` of the last N samples per metric, updated each `TimelineView` tick. Render each buffer as a `Path` using `move(to:)` then `addLine(to:)` for each sample point. Scroll by shifting all points left by one pixel per frame, or by using `offset(x:)` on the entire path with a counter that resets. The "paper scroll" effect is achieved with a cream/off-white background with subtle horizontal rule lines.

- **Variants 33–37 (Data Visualization):** These are pure SwiftUI charts, grids, and flows. No special infrastructure needed beyond `Canvas` and `Path`. Implement them in sequence using the catalog specifications.

**Test requirements:**

- Three `#Preview` blocks per variant.
- `VariantBatchEIntegrationTests`: Variants 29–40 registered correctly.
- `WireSkeletonJointPositionTests`: Given all metrics at 0.0, the head joint is directly above the shoulder midpoint (within 1 pixel). Given `forwardCreep.ratio = 1.0`, the head joint is displaced forward by approximately `maxForwardOffset` pixels.
- `SeismographBufferTests`: Verify the circular buffer correctly overwrites old values without crashing when filled to capacity and then written to again.

**Integration notes:**

Update `VariantRegistry` entries 29–40. After this step, 40 of 60 variants are implemented.

**Demo description:** Browse all 40 implemented variants in sequence. The Seismograph (Variant 38) and Wire Skeleton (Variant 29) demonstrate real-time continuous update patterns. The Digital Cockpit (Variant 11) and Altimeter Stack (Variant 37) together illustrate how the aviation instrument aesthetic is expressed in both a combined view and a single-metric slice.

---

### Step 11 — Metal Shader Infrastructure and Shader-Driven Variants

**Objective:** Build the reusable Metal shader file(s) and integrate them into the variants that require hardware-accelerated visual effects. Metal shaders unlock the most visually distinctive variants — the Water Surface, ambient glows, and noise-based distortions.

**Variants this step directly enables:**
- Variant 43: Water Surface (`.distortionEffect` wave shader)
- Variant 47: Neon Pulse (`.colorEffect` glow shader)
- Variant 51: Gradient Noise (`.colorEffect` domain-warping shader)
- Variant 52: Chromatic Aberration (`.distortionEffect` lens shader)
- Any other variant using `.layerEffect`, `.distortionEffect`, or `.colorEffect`

**Implementation guidance:**

1. **Create the Metal shader file.** Add `PostureShaders.metal` to the `Quant` target. This file contains all Metal Shading Language (MSL) functions used by posture variants. Organize into three groups:
   - Wave distortion functions (for water/fluid effects)
   - Color/noise effect functions (for ambient glow, grain, noise)
   - Utility functions (noise primitives, smoothstep, etc.)

2. **Wave shader** (used by Variant 43):
   ```metal
   [[ stitchable ]] float2 waveDistortion(
       float2 position, float time,
       float forwardCreep, float headDrop,
       float shoulderRounding, float lateralLean, float twist
   )
   ```
   This function displaces UV coordinates using layered sine waves. Each metric contributes a wave with distinct frequency, direction, and amplitude. `time` drives temporal evolution. Return value is a UV offset in points.

3. **Noise color effect** (used by ambient variants):
   ```metal
   [[ stitchable ]] half4 noiseColorEffect(
       float2 position, half4 currentColor,
       float time, float intensity, float hue
   )
   ```
   Applies a domain-warped noise field to the current pixel color, blending in a tinted noise at `intensity` strength.

4. **SwiftUI bridge.** Create `MetalShaderBridge.swift` containing convenience `ShaderLibrary` accessors:
   ```swift
   extension ShaderLibrary {
       static var waveDistortion: Shader { ... }
       static var noiseColorEffect: Shader { ... }
   }
   ```
   And `View` extension helpers:
   ```swift
   extension View {
       func postureWaveEffect(data: PostureDisplayData, time: TimeInterval) -> some View
       func postureNoiseEffect(intensity: Float, hue: Float, time: TimeInterval) -> some View
   }
   ```

5. **Fallback handling.** Metal shaders require iOS 17+ and a device with a GPU. Always provide a `.background` fallback for variants that use shaders: the fallback is the same variant with a simpler non-shader animation. Gate shader usage with `#available(iOS 17, *)` checks and/or a runtime capability check.

**Test requirements:**

- `MetalShaderAvailabilityTests`: Verify that `ShaderLibrary.default.waveDistortion` can be accessed without throwing on a simulator target that supports Metal. If Metal is unavailable, verify the fallback path is taken (not a crash).
- `MetalShaderBridgeTests`: Verify `postureWaveEffect(data:time:)` returns a view (not `EmptyView`) when called on any `View` instance.
- Xcode Preview for the Water Surface variant using a static `PostureDisplayData` in bad state — verify the shader renders (or falls back gracefully on Metal-unavailable simulators).

**Integration notes:**

The Metal shader file must be added to the `Quant` target membership in Xcode (not to `PostureLogic` or `QuantTests`). The `.metal` extension tells Xcode to compile it with the Metal compiler. The shader functions are accessed via `ShaderLibrary.default` at runtime.

After this step, update `VariantRegistry` entries for the shader-dependent variants to replace their placeholders with partial implementations that use the shader infrastructure (even if the full variant UI is not complete until a later batch step).

**Demo description:** Navigate to Variant 43 (Water Surface) and observe the real-time wave animation responding to mock posture data. The water surface visibly surges, ripples, and tilts in response to the simulated metric changes. The ambient noise effect on Variant 47 (Neon Pulse) creates a glowing, atmospheric look that clearly differs from any of the chart-based variants.

---

### Step 12 — SceneKit / 3D Infrastructure and 3D Variants

**Objective:** Build the SceneKit integration infrastructure and implement the variants that require true 3D rendering (as opposed to 2D perspective tricks).

**Variants this step directly enables:**
- Variant 29's optional SceneKit-enhanced version (if selected over the Canvas version)
- Variant 32: Muscle Tension Map (3D body model)
- Any variant using `SCNView` or `SCNScene` for 3D rendering

**Implementation guidance:**

1. **Create `SceneKitViewBridge.swift`.** A `UIViewRepresentable` wrapper around `SCNView` that:
   - Manages a `SCNScene` instance
   - Exposes a `updatePostureData(_:)` method that animates scene nodes based on `PostureDisplayData`
   - Handles `SCNView` creation, renderer setup, and appearance mode (dark/light)
   - Pauses rendering when the view is off-screen (`scnView.isPlaying = false`)

2. **PostureSceneBuilder.swift** — Factory for creating SceneKit scenes used by posture variants:
   - `static func makeBodyScene() -> SCNScene` — A stick-figure or low-poly body model as `SCNNode` hierarchy: head sphere, spine cylinder, shoulder strut, rib cage box, pelvis box. Each node has a named identifier so `updatePostureData` can find them by name.
   - `static func applyPostureDeformation(to scene: SCNScene, data: PostureDisplayData)` — Animates node transforms based on metric ratios. Forward creep rotates the spine node forward, head drop rotates the head node, shoulder rounding pulls the shoulder endpoints inward, etc.

3. **Implement Variant 32 (Muscle Tension Map)** using `SceneKitViewBridge`. The body model has surface nodes whose `SCNMaterial.emission.contents` is updated per frame to shift color from neutral to red based on the relevant metric's ratio.

4. **Verify the SceneKit view integrates cleanly with the `PostureDisplayObserver` environment object.** The `UIViewRepresentable` `updateUIView` method calls `updatePostureData` whenever SwiftUI re-renders due to data changes.

**Test requirements:**

- `SceneKitViewBridgeTests`:
  - Verify `makeBodyScene()` returns a non-nil scene with the expected named nodes.
  - Verify `applyPostureDeformation` does not throw for any valid `PostureDisplayData` including edge cases (all metrics at 0, all metrics at 2.0).
  - Verify the scene's `forwardCreep` node has a non-zero `eulerAngles.x` after applying deformation with `forwardCreep.ratio = 1.0`.

- `VariantSceneKitIntegrationTests`:
  - Variant 32 registered in `VariantRegistry` with `technologies` containing `.sceneKit`.
  - `Variant32View()` with a mock environment object renders without crash.

**Integration notes:**

SceneKit runs on the main thread for node transforms but the renderer runs on a background thread. Never update `SCNNode` properties from the background renderer thread; always use `SCNTransaction.begin()` / `commit()` on the main thread, or use `SCNAction` for animations.

Only create SceneKit infrastructure if the variant catalog specifies SceneKit explicitly. If a variant's 3D effect can be achieved with `Canvas` perspective transforms or `rotation3DEffect`, prefer that approach to avoid the SceneKit overhead.

**Demo description:** Navigate to Variant 32 (Muscle Tension Map). Observe the 3D body model with color-coded tension regions updating in response to mock simulation. Rotate the device — the SceneKit camera adapts to the new aspect ratio. Confirm that navigating away from the variant and back does not cause memory leaks or orphaned render loops (verify by profiling briefly in Instruments).

---

### Step 13 — Variant Batch F: Organic / Nature (Variants 41–46)

**Objective:** Implement six variants using organic metaphors — plants, trees, water, terrain, weather — that communicate posture state through living-system metaphors.

**Variants in this batch:**
- Variant 41: Wilting Plant
- Variant 42: Tree of Life
- Variant 43: Water Surface (shader-driven, infrastructure from Step 11)
- Variant 44: Terrain Map
- Variant 45: Weather System
- Variant 46: Bioluminescence

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/OrganicNature/`. Refer to variant-catalog-3.md for full visual specifications.

Key technical notes for this batch:

- **Variant 41 (Wilting Plant):** All plant geometry is drawn in `Canvas`. The stem is a cubic Bezier with 3 segments; the control points for each segment are derived from the metric ratios. Store all control points in a `PlantGeometry` struct conforming to `Animatable` (using `AnimatablePair` chains or an `AnimatableVector` helper). The `withAnimation(.spring(response: 0.8, dampingFraction: 0.7))` on the geometry struct drives smooth wilting transitions. Leaf pairs are drawn as two mirrored ellipses rotated around the branch attachment point. The bloom is 8 petal paths arranged with `.rotationEffect` at 45-degree increments.

- **Variant 42 (Tree of Life):** The woodcut aesthetic uses `.stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))` throughout with no fills. Grain lines are parallel paths running the trunk's length, offset by a layered sine-wave noise function per line. Perlin-noise approximation: `noise(x) = sin(x * 3.7) * 0.5 + sin(x * 7.3) * 0.3 + sin(x * 13.1) * 0.2`. Apply this to y-coordinates of the grain line control points. Falling leaves in bad state: use `TimelineView(.animation)` with an array of leaf particle structs, each with a random starting x position, fall speed, and horizontal drift. Update positions each tick, wrapping leaves that exit the bottom back to the top.

- **Variant 43 (Water Surface):** Uses the wave distortion shader from Step 11. The SwiftUI overlay views (floating metric markers) use `.offset(x: waveDisplacementX, y: waveDisplacementY)` driven by the same wave function evaluated at the marker's position. This synchronizes marker movement with the underlying surface distortion.

- **Variant 44 (Terrain Map):** Contour ring generation: for each metric, compute a Gaussian height function `h(x, y) = metricRatio * exp(-((x - peakX)^2 + (y - peakY)^2) / (2 * sigma^2))`. Sample this function on a grid to find contour lines at threshold levels (iso-contours). A simplified approach: draw 4–6 concentric ellipses per metric peak, each scaled by the metric ratio, using `Ellipse().stroke()`.

- **Variant 45 (Weather System):** The rain animation uses an array of `RainDrop` structs with `x: CGFloat`, `y: CGFloat`, `speed: CGFloat`. Each `TimelineView` tick increments `y` by `speed * dt`, resets to a random `y = -20` when `y > viewHeight`. The number of active drops scales with `headDrop.ratio`. Draws rain as thin `Path` lines. Lightning: schedule a `Timer` that fires at decreasing intervals as `twist.ratio` increases; each fire briefly sets an `@State var lightningOpacity = 1.0` that decays to 0 over 0.2s.

**Test requirements:**

- Three `#Preview` blocks per variant.
- `VariantBatchFIntegrationTests`: Variants 41–46 registered correctly.
- `PlantGeometryTests`: Given all metrics at 0.0, the plant geometry's stem control points are in a straight vertical line (x offsets all zero). Given `forwardCreep.ratio = 1.0`, the stem's middle control point has a horizontal offset ≥ maxOffset * 0.9.
- `WeatherSystemRainTests`: Verify `RainDrop` positions do not escape the view bounds after 10 seconds of simulation (all y values are in range -20 to viewHeight + 20).

**Integration notes:**

Update `VariantRegistry` entries 41–46.

**Demo description:** Navigate to the Wilting Plant (Variant 41) during the mock simulation's drifting phase. Observe the plant wilting in real time. Navigate to the Water Surface (Variant 43) and observe the shader-driven wave response. The organic nature category provides the most emotionally resonant variants — confirm that the plant's color desaturation from vibrant green to dusty yellow is perceptible during the transition.

---

### Step 14 — Variant Batch G: Gamified (Variants 47–54)

**Objective:** Implement eight variants using game-inspired visual languages: progress bars, XP meters, character health, pixel art, and achievement systems.

**Variants in this batch:**
- Variant 47: Neon Pulse (shader glow, infrastructure from Step 11)
- Variant 48: Health Bar
- Variant 49: XP Level Ring
- Variant 50: Pixel Art Body
- Variant 51: Achievement Shields
- Variant 52: Boss Health Bar
- Variant 53: Rhythm Game
- Variant 54: Tower Defense

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/Gamified/`. Refer to variant-catalog-3.md for full visual specifications.

Key technical notes for this batch:

- **Variant 47 (Neon Pulse):** Uses the `.colorEffect` shader from Step 11 to add a neon glow to the SVG-style metric lines. The base metrics are drawn as `Canvas` paths; the `.colorEffect` adds the bloom/glow post-process. At good posture, the glow color is blue-cyan; at bad posture, the glow shifts to red via a `hue` parameter passed to the shader.

- **Variant 50 (Pixel Art Body):** Draw using a pixel grid. Define a 16x24 pixel art sprite for a "standing upright" body. Each pixel is a `Rectangle().frame(width: pixelSize, height: pixelSize)`. Deformations shift pixel positions according to metric ratios. An `@State var pixels: [[Color]]` 2D array drives the rendering. Use `Canvas` for performance: draw each pixel as a `context.fill(rect, with: .color(color))` call.

- **Variant 53 (Rhythm Game):** Scrolling notes approach: a continuous stream of circular "notes" scrolls from right to left. Notes are green when they correspond to good posture metrics and red when a metric exceeds its threshold. The "timing bar" at the left edge acts as the "hit zone." When a note enters the hit zone, if the corresponding metric is good, the note pulses green ("hit"). If the metric is bad, the note turns red and plays a miss animation. Drive the scroll via `TimelineView(.animation)` and store notes in a circular buffer.

- **Variant 54 (Tower Defense):** A simplified tower defense metaphor: a castle icon at the center of the screen represents the user. Five enemy paths (one per metric) approach from the screen edges. The "enemy" on each path advances proportionally to that metric's ratio. When a metric reaches its threshold (ratio = 1.0), the enemy reaches the castle and triggers the alert mode animation. Between the castle and each enemy, a "tower" icon sits at the midpoint, styled per metric. At good posture, the towers glow green and the enemies are distant.

**Test requirements:**

- Three `#Preview` blocks per variant.
- `VariantBatchGIntegrationTests`: Variants 47–54 registered correctly.
- `PixelArtBodyTests`: Verify the pixel grid has exactly 16 * 24 = 384 pixels for any valid data input and no pixel color is `Color.clear` in good posture state.
- `RhythmGameNoteTests`: Verify note positions are monotonically decreasing in x over successive `TimelineView` frames (they move left); verify notes are recycled (not accumulated indefinitely) after exiting the left edge.

**Integration notes:**

Update `VariantRegistry` entries 47–54.

**Demo description:** Navigate through the gamified category. The Health Bar (Variant 48) and XP Level Ring (Variant 49) are immediately legible to anyone familiar with RPG games. The Rhythm Game (Variant 53) is the most kinetic variant in the entire showcase — confirm that note scrolling continues smoothly at 60fps during mock simulation.

---

### Step 15 — Variant Batch H: Architectural / Structural (Variants 55–60)

**Objective:** Implement the final six variants inspired by architectural blueprints, structural engineering, and construction systems.

**Variants in this batch:**
- Variant 55: Blueprint Grid
- Variant 56: Load Diagram
- Variant 57: Circuit Board
- Variant 58: Structural Frame
- Variant 59: Isometric City
- Variant 60: Construction Progress

**Implementation guidance:**

Create files in `Quant/Views/Showcase/Variants/Architectural/`. Refer to variant-catalog-3.md for full visual specifications.

Key technical notes for this batch:

- **Variant 55 (Blueprint Grid):** The blueprint aesthetic: dark navy background (`Color(red: 0.03, green: 0.1, blue: 0.25)`), thin white grid lines (1pt stroke at 24pt intervals), white text and lines. Blueprint annotations (dimension arrows, hatching) are drawn in `Canvas`. Metric values are displayed as blueprint-style dimensions with arrow leaders and numeric callouts in a monospaced font.

- **Variant 56 (Load Diagram):** A structural engineering free-body diagram. Five vertical columns represent metrics as load-bearing pillars. Column cross-section size scales with the metric ratio. Horizontal "beams" connect the column tops. Applied "loads" (downward arrows) above each column grow with the metric ratio. Stress concentration zones appear as hatched triangles at column bases when ratio > 0.8.

- **Variant 57 (Circuit Board):** PCB trace aesthetic: green background, gold-colored routing traces connecting five component symbols (one per metric). Each component has a status LED (tiny circle) that is green when ratio < 0.5, yellow when 0.5–0.8, red when > 0.8. The trace routing is drawn as `Path` with only 90-degree and 45-degree angles (PCB routing rules). In alert mode, an "ESD" warning icon appears at the worst offender component with red traces.

- **Variant 58 (Structural Frame):** A steel frame structure (H-beams and C-channels) shown in cross-section or elevation view. The frame represents the body skeleton. Deformations match those from Variant 21 (Stacked Totem) but rendered in an engineering drawing style: precise angles, dimension annotations, bolted joints shown as circles with crosshairs.

- **Variant 59 (Isometric City):** An isometric projection of a miniature city where buildings are posture metric visualizations. Each of the five metrics is a building block. Good posture = tall, fully-built buildings. Bad posture = crumbling, partially-collapsed structures. Isometric projection: `isoX = (x - y) * cos(30°)`, `isoY = (x + y) * sin(30°) - z`. All drawing in `Canvas` using isometric tile rendering.

- **Variant 60 (Construction Progress):** A construction site showing a building "under construction" whose completion level maps to overall posture score. At 100% posture quality, the building is complete. As posture degrades, the construction "regresses" — scaffolding appears, walls crack, and sections of the building fade back to structural outlines. Cranes and scaffolding are drawn as `Canvas` linework. Worker silhouettes appear and disappear based on metric ratios.

**Test requirements:**

- Three `#Preview` blocks per variant.
- `VariantBatchHIntegrationTests`: Variants 55–60 registered correctly; `VariantRegistry.allVariants.count == 60`.
- `IsometricProjectionTests`: Verify the isometric projection function maps `(0, 0, 0)` to the expected screen center coordinates; verify the inverse is consistent.
- `BlueprintAnnotationTests`: Verify dimension arrow paths have non-zero length for any metric ratio > 0.

**Integration notes:**

Update `VariantRegistry` entries 55–60. After this step, all 60 variants are implemented. Run `VariantRegistryTests` to confirm the full count and that every `makeView()` closure is callable.

**Demo description:** All 60 variants are available in the showcase. Browse the complete catalog from Variant 1 to Variant 60, observing the full spectrum from radically minimal (Single Word) to architecturally complex (Isometric City). The showcase list by category now has all eight categories fully populated.

---

### Step 16 — Polish, Accessibility, Performance

**Objective:** Apply cross-cutting improvements to all 60 variants and the showcase shell: VoiceOver accessibility, reduce-motion support, performance profiling, and final visual polish.

**Implementation guidance:**

**Accessibility:**

1. All 60 variants must provide a meaningful `accessibilityLabel` and `accessibilityValue` on their root view. Use `PostureVisualStyle.stateAccessibilityLabel(for:worstOffender:)` from Step 5 as the label source.

2. For animated variants, respect `UIAccessibility.isReduceMotionEnabled`. Add a `@Environment(\.accessibilityReduceMotion) var reduceMotion` property to each variant. When `reduceMotion == true`:
   - Replace spring/bounce animations with `.easeInOut(duration: 0.3)` equivalents.
   - Disable continuously repeating animations (pendulum swing, breathing orb, particle effects).
   - Disable the split-flap character roll-through; jump directly to the target character.

3. Ensure the settings gear button has `.accessibilityLabel("Settings")` and a sufficient tap target size (minimum 44×44pt).

4. The `NudgeCountdownLabel` must have `.accessibilityLabel("Nudge in \(formattedTime)")` for VoiceOver users to hear the countdown.

**Reduce Transparency:**

5. When `UIAccessibility.isReduceTransparencyEnabled`, replace `Material` blur backgrounds (`.ultraThinMaterial`, `.thinMaterial`) with solid color equivalents. Add a helper `extension View { func postureBackground() -> some View }` that conditionally applies material vs. solid color based on the accessibility flag.

**Performance:**

6. Profile the `TimelineView`-driven variants (Variants 7, 23, 24, 38, 41, 42, 43, 45, 53) using Instruments / Metal Performance Analyzer in the simulator. Verify each runs at ≥ 60fps on iPhone 14 equivalent hardware.

7. For `Canvas`-heavy variants, ensure the `Canvas` closure captures only the minimal required data. Avoid capturing `@EnvironmentObject` directly inside `Canvas` (pass values as local constants computed before the closure).

8. Variants using `TimelineView` should pause their animation when the variant is not visible. Implement `onAppear { isAnimating = true }` / `onDisappear { isAnimating = false }` guards in variants where animation can be disabled without visual degradation.

9. The split-flap animation (Variant 12) must not create new `Task` instances on every SwiftUI render. Gate task creation with `@State var animationTask: Task<Void, Never>?` and cancel/restart only on meaningful state changes.

**Final Visual Polish:**

10. Audit all 60 variants in both light and dark mode. Identify any variant that uses hard-coded `Color.black` or `Color.white` and replace with semantic colors (`Color.primary`, `Color.secondary`, etc.) or conditional logic.

11. Verify all 60 variants in portrait and landscape on both a small screen (iPhone SE: 375×667 pt) and a large screen (iPhone Pro Max: 430×932 pt) using the Xcode simulator. Fix any layout issues (clipped content, text truncation, overlapping elements).

12. The showcase list should show a thumbnail preview of each variant in its row. Implement `VariantThumbnailView` as a small (60×60pt) snapshot of the variant using `Image(size:renderer:)` from SwiftUI's `ImageRenderer`. Update `VariantCatalogList` to include the thumbnail.

**Test requirements:**

- `AccessibilityTests`:
  - For each variant, verify `accessibilityLabel` is non-empty.
  - Verify that with `reduceMotion = true`, the root animation for each variant uses a duration ≤ 0.5s.

- `PerformanceTests`:
  - Benchmark the 5 heaviest variants (identified by profiling) using `measure {}` in XCTest. Target: each variant renders 100 SwiftUI body evaluations (via rapid `PostureDisplayData` changes) in < 500ms.

- `VariantThumbnailTests`:
  - `VariantThumbnailView` renders without crash for all 60 variants using `MockPostureDataSource.preview(state: .good)`.

- Final `VariantRegistryTests`:
  - All 60 variants have a non-empty `name`.
  - All 60 variants have a non-empty `technologies` array.
  - All 60 `makeView()` closures are callable.
  - `VariantCategory.allCases` are all represented by at least one variant.

**Integration notes:**

This step touches all 60 variant files. Make changes incrementally: handle accessibility first (adding modifiers is non-breaking), then reduce-motion support, then performance fixes (which may require refactoring internals), then visual polish (pure UI changes).

The `VariantThumbnailView` using `ImageRenderer` requires iOS 16+, which is below the project's iOS 17 minimum target.

**Demo description:** Launch the showcase on a device with VoiceOver enabled. Navigate to several variants and verify that VoiceOver announces the posture state meaningfully. Enable Reduce Motion in Accessibility settings and confirm that all animations become subtle and non-distracting. Profile a complex variant in Instruments and confirm smooth 60fps rendering. The full showcase of 60 variants is production-quality and ready for user evaluation to select the final design direction.

---

## Appendix: File Organization

```
Quant/
  Views/
    Showcase/
      VariantShowcaseView.swift
      VariantRegistry.swift
      VariantDescriptor.swift
      VariantCatalogList.swift
      VariantPlaceholderView.swift
      VariantThumbnailView.swift
      DataSourceMode.swift
      DataSourceToggleView.swift
      MockControlsInspector.swift
      SettingsSheetView.swift
      DataSources/
        PostureDataSourceProtocol.swift
        PostureDisplayObserver.swift
        MockPostureDataSource.swift
        LivePostureDataSource.swift
      Models/
        MetricKey.swift
        MetricInfo.swift
        PostureDisplayData.swift
        PostureDisplayData+Make.swift
        RawMetrics+Extensions.swift
        PostureThresholds+Extensions.swift
      SharedUI/
        PostureVisualStyle.swift
        PostureAnimations.swift
        MetricRatioBar.swift
        NudgeCountdownLabel.swift
        SettingsGearButton.swift
        PostureStateAmbientBackground.swift
        AbsenceOverlay.swift
      Shaders/
        PostureShaders.metal
        MetalShaderBridge.swift
      SceneKit/
        SceneKitViewBridge.swift
        PostureSceneBuilder.swift
      Variants/
        ScoreCentric/
          Variant1View.swift  ... Variant6View.swift
        Dashboard/
          Variant7View.swift  ... Variant12View.swift
        Minimal/
          Variant13View.swift ... Variant20View.swift
        AbstractGeometric/
          Variant21View.swift ... Variant28View.swift
        ThreeDInstrument/
          Variant29View.swift ... Variant40View.swift
        OrganicNature/
          Variant41View.swift ... Variant46View.swift
        Gamified/
          Variant47View.swift ... Variant54View.swift
        Architectural/
          Variant55View.swift ... Variant60View.swift

QuantTests/
  MetricKeyTests.swift
  MetricInfoTests.swift
  PostureDisplayDataMakeTests.swift
  RawMetricsExtensionTests.swift
  PostureThresholdsExtensionTests.swift
  MockPostureDataSourceSimulationTests.swift
  MockPostureDataSourceManualTests.swift
  MockPostureDataSourcePreviewTests.swift
  LivePostureDataSourceTests.swift
  VariantRegistryTests.swift
  PostureVisualStyleTests.swift
  PendulumPhysicsTests.swift
  RadarGlyphTests.swift
  WireSkeletonJointPositionTests.swift
  SeismographBufferTests.swift
  PlantGeometryTests.swift
  WeatherSystemRainTests.swift
  PixelArtBodyTests.swift
  RhythmGameNoteTests.swift
  IsometricProjectionTests.swift
  BlueprintAnnotationTests.swift
  MetalShaderAvailabilityTests.swift
  MetalShaderBridgeTests.swift
  SceneKitViewBridgeTests.swift
  AccessibilityTests.swift
  PerformanceTests.swift
  VariantBatchAIntegrationTests.swift
  VariantBatchBIntegrationTests.swift
  VariantBatchCIntegrationTests.swift
  VariantBatchDIntegrationTests.swift
  VariantBatchEIntegrationTests.swift
  VariantBatchFIntegrationTests.swift
  VariantBatchGIntegrationTests.swift
  VariantBatchHIntegrationTests.swift
```

## Appendix: Variant Category Breakdown

| Step | Category | Variants | Count |
|---|---|---|---|
| 6 | Score-Centric | 1–6 | 6 |
| 7 | Dashboard / Multi-Metric | 7–12 | 6 |
| 8 | Minimal / Typographic | 13–20 | 8 |
| 9 | Abstract Geometric | 21–28 | 8 |
| 10 | 3D / Body / Instrument | 29–40 | 12 |
| 13 | Organic / Nature | 41–46 | 6 |
| 14 | Gamified | 47–54 | 8 |
| 15 | Architectural / Structural | 55–60 | 6 |
| **Total** | | | **60** |

*Variants 43 (Water Surface) and 47 (Neon Pulse) depend on Metal shader infrastructure from Step 11 and SceneKit infrastructure from Step 12, but their SwiftUI wrappers are completed in their respective category batch steps (13 and 14).*
