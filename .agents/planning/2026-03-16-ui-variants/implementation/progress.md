# Progress: Posture Metrics UI Variants

## Current Step
**Step 2 — Mock Data Source**

## Active Wave
- `code-assist:ui-variants:step-02:manual-and-preview` (task-1773705968-191d) — MockPostureDataSource class skeleton + manual mode + preview factory + manual/preview tests
- `code-assist:ui-variants:step-02:simulation-engine` (task-1773705982-48bf) — Simulation state machine + timer loop + simulation tests (blocked by manual-and-preview)

## Verification Notes

### task-1773699549-ef9d: MetricKey + RawMetrics/PostureThresholds extensions
- **Tests written (RED):** MetricKeyTests (4 tests), RawMetricsExtensionTests (2 tests), PostureThresholdsExtensionTests (1 test) — all failed with expected "no member" compilation errors
- **Implementation (GREEN):** 3 files in `Quant/PostureUI/`: `MetricKey.swift`, `RawMetrics+Extensions.swift`, `PostureThresholds+Extensions.swift`
- **Full suite (19 tests):** All pass, no regressions
- **Scheme fix:** Updated `QuantNoWatchTests.xcscheme` to include Quant app as build dependency and enable implicit dependencies
- **Build command:** `xcodebuild test -scheme QuantNoWatchTests -destination 'platform=iOS Simulator,id=E43DED31-68B0-412D-8B92-91DA5B94547A'`

### task-1773699552-eeaf: MetricInfo struct + computed properties
- **Tests written (RED):** MetricInfoTests (5 tests) — failed with expected "Cannot find 'MetricInfo' in scope"
- **Implementation (GREEN):** `Quant/PostureUI/MetricInfo.swift` — struct with key, value, ratio, threshold, isWorstOffender; computed isExceeded, clampedRatio
- **Focused tests (5/5):** All pass
- **Full suite (24 tests):** All pass (5 new + 19 existing), no regressions

### task-1773699568-13ad: PostureDisplayData + factory + tests
- **Tests written (RED):** PostureDisplayDataMakeTests (14 tests) — failed with expected "Cannot find 'PostureDisplayData' in scope"
- **Implementation (GREEN):** 2 files in `Quant/PostureUI/`: `PostureDisplayData.swift` (struct with metrics, state, computed properties), `PostureDisplayData+Make.swift` (factory method per design doc 4.5)
- **Focused tests (14/14):** All pass
- **Full suite (38 tests):** All pass (14 new + 24 existing), no regressions
- **Test coverage:** (a) ratio at threshold, (b) nil metrics, (c) worstOffender identification, (d) aggregateScore boundaries, (e) isAlertMode for all states, (f) nudgeCountdownSeconds for all decision types

### task-1773699577-32db: PostureDataSourceProtocol + PostureDisplayObserver
- **Scaffold task (no tests):** Observer will be integration-tested in Step 2 with MockPostureDataSource
- **Implementation:** 2 files in `Quant/PostureUI/`:
  - `PostureDataSourceProtocol.swift` — protocol inheriting ObservableObject, requires `currentData: PostureDisplayData`
  - `PostureDisplayObserver.swift` — @MainActor ObservableObject with @Published data, Combine subscription via generic helper to open existential, switchSource(to:) for runtime source swapping
- **Build:** Clean build success
- **Full suite (38 tests):** All pass, no regressions
- **Review round 2:** Fixed `switchSource(to:)` — added `self.data = newSource.currentData` snapshot before subscribing (mirrors init behavior). Build clean, 38/38 tests pass.

## Completed Tasks (Step 1)
- ✅ `code-assist:ui-variants:step-01:metric-key-and-extensions` — MetricKey enum + RawMetrics/PostureThresholds extensions (task-1773699549-ef9d)
- ✅ `code-assist:ui-variants:step-01:metric-info` — MetricInfo struct + computed properties + tests (task-1773699552-eeaf)
- ✅ `code-assist:ui-variants:step-01:display-data-and-factory` — PostureDisplayData + factory + tests (task-1773699568-13ad)
- ✅ `code-assist:ui-variants:step-01:observer-and-protocol` — PostureDataSourceProtocol + PostureDisplayObserver (task-1773699577-32db)

### task-1773705968-191d: MockPostureDataSource manual mode + preview factory
- **Tests written (RED):** MockPostureDataSourceManualTests (2 tests), MockPostureDataSourcePreviewTests (2 tests) — failed with expected "Cannot find 'MockPostureDataSource' in scope"
- **Implementation (GREEN):** `Quant/PostureUI/MockPostureDataSource.swift` — @MainActor final class conforming to PostureDataSourceProtocol with:
  - `currentData` computed property: delegates to `_currentData` (auto-sim) or `buildManualData()` (manual)
  - 5 manual slider @Published properties, manualPostureState, isAutoSimulating
  - `buildManualData()` builds RawMetrics from sliders and calls PostureDisplayData.make()
  - `preview(state:worstMetric:worstRatio:)` static factory for non-animating snapshots
  - `stopSimulation()` and `deinit` for timer cleanup (timer will be added in simulation-engine task)
- **Focused tests (4/4):** All pass
- **Full suite (42 tests):** All pass (4 new + 38 existing), no regressions
- **Test details:** manual slider ratio==1.0 at threshold; bad state with zero metrics doesn't crash; preview(.good) returns good state; preview(.drifting, worstMetric:.headDrop, worstRatio:1.3) returns correct worstOffender

### task-1773705982-48bf: MockPostureDataSource simulation engine
- **Tests written (RED):** MockPostureDataSourceSimulationTests (3 tests) — failed with expected "has no member 'simulationTick'"
- **Implementation (GREEN):** Added to `Quant/PostureUI/MockPostureDataSource.swift`:
  - `SimulationPhase` enum: `.good(elapsed)`, `.drifting(elapsed, dominantMetric)`, `.bad(elapsed)`, `.recovery(elapsed)`
  - 4-phase state machine with randomized durations: Good (8-12s), Drifting (15-30s), Bad (10-20s), Recovery (3-5s)
  - `simulationTick()` method: advances clock by `(1/30)*speedMultiplier`, advances phase, builds `PostureDisplayData`
  - Good phase: layered sine waves at irrational frequencies (1.1, 1.7, 2.3), ±5% threshold amplitude
  - Drifting phase: dominant metric ramps 0→1.2× threshold via quadratic ease-in, `nudgeDecision=.pending` with countdown
  - Bad phase: metrics stay elevated, `.fire(reason:)` for first 2s then `.none`
  - Recovery phase: quadratic ease-out from 1.2× to zero
  - 30Hz timer via `Timer.scheduledTimer`, auto-starts in `init()`, `startSimulation()`/`stopSimulation()` for lifecycle
  - Updated `preview()` factory to call `stopSimulation()` before disabling auto-sim
- **Focused tests (3/3):** All pass
- **Full suite (45 tests):** All pass (3 new + 42 existing), zero regressions

## Completed Tasks (Step 2)
- ✅ `code-assist:ui-variants:step-02:manual-and-preview` — MockPostureDataSource class skeleton + manual mode + preview factory + manual/preview tests (task-1773705968-191d)
- ✅ `code-assist:ui-variants:step-02:simulation-engine` — Simulation state machine + timer loop + simulation tests (task-1773705982-48bf)

## Completed Steps
- ✅ **Step 1 — Shared Data Layer** (4/4 tasks): MetricKey, MetricInfo, PostureDisplayData+factory, PostureDataSourceProtocol+PostureDisplayObserver. 38 tests, all pass.
- ✅ **Step 2 — Mock Data Source** (2/2 tasks): MockPostureDataSource with manual mode, preview factory, 4-phase simulation engine, 30Hz timer. 45 tests, all pass.
