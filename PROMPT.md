# Phase 3a: Stability & Thermal Hardening (Steps 42–43)

Implement a long-run stability harness and thermal throttling strategy. See `.agents/planning/2026-03-08-posture-detection/implementation/plan.md` for full architectural context.

## Important: Existing Infrastructure

Key components already in place — **do not duplicate or rewrite** these:

- **`MockPoseProvider`** at `PostureLogic/Sources/PostureLogic/Testing/MockPoseProvider.swift` — emits `InputFrame` via `framePublisher`, has `emit(frame:)` and `emit(scenario:)` helpers
- **`TestScenarios`** at `PostureLogic/Sources/PostureLogic/Testing/TestScenarios.swift` — static scenario builders returning `TestScenario` structs with `frames` and `expectedStates`
- **`Pipeline`** at `PostureLogic/Sources/PostureLogic/Pipeline.swift` — the main orchestrator. Uses `poseFrameInterval` (0.1s = 10 FPS) for throttling. Processes frames via `process(_:)` which runs Vision, depth, metrics, posture, nudge engines
- **`ModeSwitcher`** at `PostureLogic/Sources/PostureLogic/Services/ModeSwitcher.swift` — switches between `.depthFusion` and `.twoDOnly` based on depth confidence. Good pattern to follow for thermal-based mode changes
- **`PoseProvider` protocol** at `PostureLogic/Sources/PostureLogic/Protocols/PoseProvider.swift` — `framePublisher: AnyPublisher<InputFrame, Never>`, `start()`, `stop()`
- **`PostureThresholds`** at `PostureLogic/Sources/PostureLogic/Models/PostureThresholds.swift` — all configurable thresholds, Codable
- **`DebugDumpable` protocol** — all engines/services conform to this for debug overlay state exposure
- **`InputFrame`** carries `precomputedSample` for fast-path replay (bypasses Vision). Use this for the stability test to avoid needing real pixel buffers
- **`PoseSample`** builder and golden recordings exist in tests — reuse patterns from `GoldenRecordingTests.swift`

## Step 42: Long-Run Stability Harness

Create a test that proves 90-minute session stability with no memory leaks or crashes.

### Implementation

Create `PostureLogicTests/LongRunStabilityTests.swift`:

- Use `MockPoseProvider` to emit 54,000 frames (90 min × 10 FPS) at accelerated speed
- Build realistic `InputFrame` instances using `precomputedSample` path (avoids needing real pixel buffers — fast and deterministic)
- Generate varied pose data: alternate between good posture, gradual slouch, recovery, stretching periods to exercise all engines
- Set a calibration baseline on the Pipeline before the run
- Run the full Pipeline (metrics, smoothing, task mode, posture, nudge, staleness — all engines)
- **Memory measurement**: Sample `task_info` memory at start and at intervals (every 5,000 frames). Final memory must be < 100MB above start
- **No unbounded growth**: Arrays like `recentMetricsBuffer`, `frameTimestamps`, `recentQualities` must not grow beyond their caps
- **All published properties** must have valid values at the end (not stuck at defaults)

### Test Cases

- `test_90MinuteSession_noMemoryLeak`: Emit 54k precomputed frames through Pipeline. Assert memory delta < 100MB. Assert Pipeline is still functional (postureState != .absent after processing)
- `test_buffersCapped_afterLongRun`: After 54k frames, verify `recentMetricsBuffer` never exceeds 100, `frameTimestamps` never exceeds 30
- `test_allEnginesExercised_duringLongRun`: Verify that during the run, taskMode changed from .unknown, postureState transitioned through multiple states, nudgeDecision included at least one .fire or .pending

### Notes

- Use `XCTestExpectation` with timeout for async frame processing
- The test should complete in < 60 seconds (accelerated, no real-time waits)
- Use `mach_task_basic_info` for memory measurement (reliable on Darwin)
- Since Pipeline processes frames on MainActor, you'll need to give RunLoop time to process. Use a small delay between batches or `RunLoop.current.run(until:)` between chunks

## Step 43: Thermal Throttling Strategy

Create a `ThermalMonitor` that observes device thermal state and adjusts Pipeline behavior to prevent overheating.

### Implementation

#### 1. ThermalState Model

Create `PostureLogic/Sources/PostureLogic/Models/ThermalState.swift`:

```swift
public enum ThermalLevel: Int, Comparable, CaseIterable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ThermalPolicy {
    public let maxFPS: Float          // Target FPS cap
    public let depthEnabled: Bool     // Whether to use depth/LiDAR
    public let detectionPaused: Bool  // Whether to pause detection entirely

    public static let nominal = ThermalPolicy(maxFPS: 10, depthEnabled: true, detectionPaused: false)
    public static let fair = ThermalPolicy(maxFPS: 5, depthEnabled: true, detectionPaused: false)
    public static let serious = ThermalPolicy(maxFPS: 3, depthEnabled: false, detectionPaused: false)
    public static let critical = ThermalPolicy(maxFPS: 0, depthEnabled: false, detectionPaused: true)

    public static func policy(for level: ThermalLevel) -> ThermalPolicy {
        switch level {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        }
    }
}
```

#### 2. ThermalMonitor Protocol & Implementation

Create `PostureLogic/Sources/PostureLogic/Protocols/ThermalMonitorProtocol.swift`:

```swift
public protocol ThermalMonitorProtocol {
    var currentLevel: ThermalLevel { get }
    var currentPolicy: ThermalPolicy { get }
    var levelPublisher: AnyPublisher<ThermalLevel, Never> { get }
}
```

Create `PostureLogic/Sources/PostureLogic/Services/ThermalMonitor.swift`:

- Observe `ProcessInfo.thermalStateDidChangeNotification`
- Map `ProcessInfo.ThermalState` → `ThermalLevel`
- Publish level changes via Combine
- Conform to `DebugDumpable`

#### 3. MockThermalMonitor for Testing

Create `PostureLogic/Sources/PostureLogic/Testing/MockThermalMonitor.swift`:

- Allows setting thermal level programmatically for tests
- Publishes changes immediately

#### 4. Pipeline Integration

Modify `Pipeline.swift`:

- Add optional `thermalMonitor: (any ThermalMonitorProtocol)?` parameter to `init` (default nil — backwards compatible)
- Subscribe to `levelPublisher` when monitor is provided
- **FPS throttling**: Adjust `poseFrameInterval` based on `ThermalPolicy.maxFPS` (e.g., fair → 0.2s interval, serious → 0.333s)
- **Depth disabling**: When policy says `depthEnabled: false`, skip depth sampling in `process(_:)` (treat as if no depth available)
- **Detection pausing**: When `detectionPaused: true`, skip frame processing entirely
- Add `@Published public var thermalLevel: ThermalLevel = .nominal` for UI display
- Add `@Published public var thermalPolicy: ThermalPolicy = .nominal` for debug overlay

#### 5. App-Level UI (Quant/)

- When `thermalLevel >= .serious`: Show a banner/overlay "Reduced accuracy — device is warm"
- When `thermalLevel == .critical`: Show full-screen "Cooling down..." with a pause indicator
- Wire `ThermalMonitor()` (real) into Pipeline in `AppModel.swift`

### Test Cases (in `PostureLogicTests/ThermalMonitorTests.swift`)

- `test_nominalPolicy_fullOperation`: Verify nominal → 10 FPS, depth on, not paused
- `test_fairPolicy_reducesFPS`: Verify fair → 5 FPS, depth still on
- `test_seriousPolicy_disablesDepth`: Verify serious → 3 FPS, depth off
- `test_criticalPolicy_pausesDetection`: Verify critical → 0 FPS, detection paused

### Test Cases (in `PostureLogicTests/PipelineThermalTests.swift`)

- `test_pipeline_throttlesFPS_onFairThermalState`: Set mock thermal to fair, emit frames, verify effective FPS ≤ 5
- `test_pipeline_disablesDepth_onSeriousThermalState`: Set mock thermal to serious, verify depth samples are nil even when depth data is available in frame
- `test_pipeline_pausesDetection_onCriticalThermalState`: Set mock thermal to critical, emit frames, verify no new `latestSample` updates
- `test_pipeline_resumesNormally_afterThermalRecovery`: Go critical → nominal, verify processing resumes

## Constraints

- All existing tests must continue to pass — no regressions
- Follow existing project patterns (protocols, DebugDumpable conformance, test naming conventions)
- PostureLogic package changes only in `PostureLogic/` — app-level UI changes in `Quant/`
- Pipeline init must remain backwards-compatible (thermalMonitor is optional/defaulted)
- Step 42 has no dependency on Step 43 — they can be worked in any order
- The stability test (Step 42) should use precomputed samples, NOT real Vision processing

## After Each Step

When a step is committed:
1. Update `.agents/planning/2026-03-08-posture-detection/implementation/plan.md` — change `- [ ] Step XX:` to `- [x] Step XX:` for the completed step
2. Verify all tests pass (`swift test --package-path PostureLogic`)

## Success Criteria

- [ ] 90-minute stability test passes: 54k frames processed, memory delta < 100MB, no crashes
- [ ] All Pipeline buffers proven capped (no unbounded growth)
- [ ] ThermalMonitor observes ProcessInfo thermal state and publishes ThermalLevel
- [ ] ThermalPolicy correctly maps: nominal→full, fair→5FPS, serious→3FPS+noDepth, critical→paused
- [ ] Pipeline respects thermal policy (throttles FPS, disables depth, pauses detection)
- [ ] Pipeline resumes normal operation when thermal state recovers
- [ ] UI shows thermal warnings at serious/critical levels
- [ ] All existing PostureLogic tests still pass (no regressions)
- [ ] Plan checklist updated after each step commits
