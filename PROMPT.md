# Phase 2b: Task Mode, Settings & Validation (Steps 36–41)

Implement activity classification, runtime threshold tuning, setup validation, and stale baseline detection. See `.agents/planning/2026-03-08-posture-detection/implementation/plan.md` for full architectural context.

## Important: Existing Infrastructure

Much of the groundwork is already in place — **do not duplicate or rewrite** these:

- **`TaskMode`** enum exists at `PostureLogic/Sources/PostureLogic/Models/TaskMode.swift` — cases: `.unknown`, `.reading`, `.typing`, `.meeting`, `.stretching`
- **`PostureEngine.checkPostureBad(metrics:taskMode:)`** already applies per-mode threshold multipliers (reading: 1.2x forward, typing: 1.2x twist, meeting: 1.2x+, stretching: disabled)
- **`NudgeEngine.evaluate()`** already accepts `taskMode` and `movementLevel` parameters
- **`MetricsSmoother`** already computes `movementLevel` (0–1 Float) and `headMovementPattern` (`.still`, `.smallOscillations`, `.largeMovements`, `.erratic`)
- **`RawMetrics`** already carries `movementLevel` and `headMovementPattern` fields
- **`Pipeline`** currently passes `.unknown` as taskMode everywhere — this is what Step 39 fixes

## Step 36: TaskModeEngine Implementation

Create `PostureLogic/Sources/PostureLogic/Engines/TaskModeEngine.swift`.

- Analyze a rolling window of `RawMetrics` (~100 entries = ~10 seconds at 10 FPS)
- Classification rules using existing `movementLevel` and `headMovementPattern`:
  - **Reading**: `movementLevel < 0.2` AND `headMovementPattern == .smallOscillations`
  - **Typing**: `movementLevel` in `0.2..<0.5` AND `headMovementPattern == .largeMovements`
  - **Stretching**: `movementLevel > 0.7`
  - **Meeting**: `movementLevel` in `0.15..<0.4` AND `headMovementPattern == .still` (looking at screen, occasional gestures)
  - **Unknown**: fewer than 10 samples, or no pattern matches
- Public API: `func infer(from recentMetrics: [RawMetrics]) -> TaskMode`
- Conform to `DebugDumpable`

**Tests** (in `PostureLogicTests/TaskModeEngineTests.swift`):
- `test_classifiesReading_withLowMovementSmallOscillations`
- `test_classifiesTyping_withModerateMovementLargeMovements`
- `test_classifiesStretching_withHighMovement`
- `test_classifiesMeeting_withLowMovementStill`
- `test_returnsUnknown_withInsufficientSamples`
- `test_returnsUnknown_whenNoPatternMatches`

## Step 37: Task-Adjusted Thresholds

Verify and align the existing multipliers in `PostureEngine.checkPostureBad()` with the spec:

| Mode | forwardCreep | twist | lateralLean | headDrop | shoulderRounding |
|------|-------------|-------|-------------|----------|-----------------|
| Reading | 1.3x | 1.0x | 1.0x | 1.0x | 1.2x |
| Typing | 1.0x | 1.2x | 1.0x | 1.0x | 1.0x |
| Meeting | 1.2x | 1.5x | 1.2x | 1.0x | 1.2x |
| Stretching | ∞ (disabled) | ∞ | ∞ | ∞ | ∞ |
| Unknown | 1.0x | 1.0x | 1.0x | 1.0x | 1.0x |

- If multipliers already match, just add/update tests confirming each row
- If they differ, update to match and ensure no regressions
- headDrop is **never** adjusted by task mode (always 1.0x)

**Tests** (add to existing `PostureEngineTests.swift`):
- `test_readingMode_relaxesForwardCreepAndShoulderRounding`
- `test_typingMode_relaxesTwist`
- `test_meetingMode_relaxesMultipleMetrics`
- `test_stretchingMode_disablesAllJudgement`
- `test_headDrop_notAffectedByAnyTaskMode`
- All existing PostureEngine tests still pass

## Step 38: Thresholds Settings Screen

Create `Quant/Views/ThresholdsSettingsView.swift`.

- Sliders for all `PostureThresholds` metric fields:
  - forwardCreepThreshold (0.01–0.10, step 0.005)
  - twistThreshold (5–30°, step 1)
  - sideLeanThreshold (0.02–0.20, step 0.01)
  - headDropThreshold (0.02–0.15, step 0.005)
  - shoulderRoundingThreshold (3–20°, step 1)
- Timing controls:
  - slouchDurationBeforeNudge (60–600s)
  - nudgeCooldown (60–1800s)
  - maxNudgesPerHour (1–10)
- "Reset to Defaults" button
- Changes apply immediately to Pipeline's thresholds (live-reload)
- Persist to UserDefaults using `PostureThresholds.Codable` conformance
- Load persisted thresholds at app launch in AppModel
- Add navigation link from existing settings/calibration screen

**Tests**:
- Manual testing only (UI). Verify changes persist across relaunch.

## Step 39: TaskModeEngine Pipeline Integration

Wire TaskModeEngine into Pipeline to replace hardcoded `.unknown`.

- Add `TaskModeEngine` instance to Pipeline
- Maintain rolling `[RawMetrics]` buffer (max 100 entries ≈ 10 seconds at 10 FPS)
- After smoothing each frame: append to buffer, trim to max, call `infer(from:)`
- Add `@Published var taskMode: TaskMode = .unknown` to Pipeline
- Replace all hardcoded `.unknown` in Pipeline with the inferred taskMode
- Expose in debug overlay

**Tests** (in `PostureLogicTests/PipelineTaskModeTests.swift`):
- `test_pipeline_infersTaskMode_fromMetricsWindow`
- `test_pipeline_passesInferredTaskMode_toPostureEngine`
- `test_pipeline_passesInferredTaskMode_toNudgeEngine`
- All existing Pipeline tests still pass

## Step 40: Setup Validation

Create `PostureLogic/Sources/PostureLogic/Services/SetupValidator.swift`.

- `func validate(sample: PoseSample, baseline: Baseline?) -> SetupValidationResult`
- `SetupValidationResult`: `.valid`, `.tooClose(detail)`, `.tooFar(detail)`, `.badAngle(detail)`, `.bodyNotFullyVisible(detail)`
- Depth mode checks: `shoulderMidpoint.z` against 0.5m–1.5m range
- 2D mode checks: `shoulderWidthRaw` as distance proxy (>0.5 = too close, <0.15 = too far)
- Also check: vertical angle, full upper body visibility (both shoulders + head detected)
- Integrate into calibration flow: warn before/during sampling
- Add warning UI to CalibrationView when validation fails

**Tests** (in `PostureLogicTests/SetupValidatorTests.swift`):
- `test_failsTooClose_depthMode`
- `test_failsTooFar_depthMode`
- `test_failsTooClose_2DMode`
- `test_failsTooFar_2DMode`
- `test_passesValidRange`
- `test_failsBadAngle`
- `test_failsMissingUpperBody`

## Step 41: Stale Baseline Detection

Create `PostureLogic/Sources/PostureLogic/Services/StaleBaselineDetector.swift`.

- Compare current shoulder position against baseline
- Position shift detection: if `abs(current.shoulderWidthRaw - baseline.shoulderWidthRaw) / baseline.shoulderWidthRaw > 0.30`, flag stale
- Time-based staleness: baseline older than 1 hour flags as stale
- `func check(current: PoseSample, baseline: Baseline, baselineAge: TimeInterval) -> StaleBaselineResult`
- `StaleBaselineResult`: `.fresh`, `.positionShifted(percent)`, `.timeExpired(age)`, `.bothStale`
- Wire into Pipeline: check periodically (every 60s, not every frame)
- Add `@Published var baselineStaleness: StaleBaselineResult = .fresh` to Pipeline
- Show non-intrusive "Recalibrate?" suggestion in UI when stale (don't force)

**Tests** (in `PostureLogicTests/StaleBaselineDetectorTests.swift`):
- `test_detectsStaleBaseline_afterSignificantShift`
- `test_detectsStaleBaseline_afterTimeout`
- `test_returnsFresh_whenWithinTolerances`
- `test_detectsBothStale_whenShiftedAndExpired`

## Constraints

- All existing tests must continue to pass — no regressions
- Follow existing project patterns (protocols, DebugDumpable conformance, test naming)
- PostureLogic package changes only in `PostureLogic/` — app-level UI in `Quant/`
- Do NOT duplicate infrastructure that already exists (TaskMode enum, threshold multipliers, movementLevel, etc.)
- Steps 36 and 37 can be worked in parallel (no dependency)
- Step 39 depends on Step 36
- Steps 40 and 41 are independent of 36–39

## After Each Step

When a step is committed:
1. Update `.agents/planning/2026-03-08-posture-detection/implementation/plan.md` — change `- [ ] Step XX:` to `- [x] Step XX:` for the completed step
2. Verify all tests pass (`swift test --package-path PostureLogic`)

## Success Criteria

- [ ] TaskModeEngine classifies reading/typing/meeting/stretching from movement patterns
- [ ] Task-adjusted thresholds match the spec table above
- [ ] Thresholds settings screen allows runtime tuning with persistence
- [ ] Pipeline uses inferred taskMode instead of hardcoded `.unknown`
- [ ] Setup validation warns when phone is too close/far/angled during calibration
- [ ] Stale baseline detected and recalibration suggested (not forced)
- [ ] All existing PostureLogic tests still pass (no regressions)
- [ ] Plan checklist updated after each step commits
