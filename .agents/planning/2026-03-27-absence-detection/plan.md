# Absence Detection — Implementation Plan

_Planning session: 2026-03-27_
_Revised: 2026-03-27 (decisions updated before implementation)_

## Problem Statement

Distinguish between two cases that currently look identical to the app:

1. **User is absent** — they left the seat. Camera sees an empty room.
2. **Tracking degraded** — user is present but the model can't detect them (occlusion, lighting, bad angle).

Currently, both cases map to `TrackingQuality.lost`, which silently freezes `PostureEngine` with no state change and no UI feedback.

---

## Design Decisions (Revised)

| # | Question | Decision |
|---|----------|----------|
| Q1 | Mental model | **Signal-based.** `.degraded` = user present, tracking bad. `.lost` = user absent. Option to add confidence-floor hybrid later if edge cases appear. |
| Q2 | Entry timing for `.absent` | **1-second dwell.** Require `.lost` quality to sustain for `absentThreshold = 1.0s` before declaring `.absent`. |
| Q3 | Return path from `.absent` | **2-second re-validation + duration-dependent restore.** Collect 2s of fresh data (`returnValidationWindow = 2.0`) before committing. Then: short absence (<30s) resumes prior state; long absence (≥30s) goes to `.good` with a prompted but dismissible recalibration nudge ("Welcome back, sit comfortably and tap to recalibrate"). If dismissed, old baseline stays and `StaleBaselineDetector` catches drift later. |
| Q4 | Absence in session analytics | **Internal telemetry only.** `absenceSegments` logged in `Pipeline` but NOT surfaced in posture score or analytics yet. Dead time that doesn't count as good or bad. |
| Q5 | `.degraded` visibility | **Internal state only.** Do NOT add `.degraded` as a `PostureState` case. No UI overlay. No 60-view blast radius. Show `trackingQuality` as a text label on the debug screen (already present in `DebugOverlayView`). `PostureEngine` handles degraded quality by freezing internally. |
| Q6 | Recalibration on long return | **Prompted, dismissible.** After ≥30s absence, show a prompt. If dismissed, resume with old baseline. |

### Key Changes from Original Plan

- ~~Step 1 (add `.degraded` to PostureState)~~ — REMOVED, internal only
- ~~Step 5 (DegradedTrackingOverlay)~~ — REMOVED
- ~~Step 6 (VariantShowcaseView wiring for .degraded)~~ — REMOVED
- ~~Step 7 (60-variant switch sweep)~~ — REMOVED
- `absentThreshold` changed from 3.0 → **1.0**
- Added `returnValidationWindow = 2.0` (new threshold)
- Added `absentResumeThreshold = 30.0` (same value as original, now explicit)
- Added prompted recalibration after long absence (via `showRecalibrationPrompt` on Pipeline)
- Absence segments are internal telemetry only

---

## State Machine (Revised)

```
TrackingQuality.good ────────────────────────────────────────────────────────
                           ┌────────┐  bad metrics  ┌──────────┐  timeout  ┌───────┐
                           │  GOOD  │ ────────────> │ DRIFTING │ ────────> │  BAD  │
                           └────────┘ <──────────── └──────────┘           └───────┘
                                good metrics                                    │
                                    ^──────────────── recovery grace ───────────┘

TrackingQuality.degraded ─────────────────────────────────────────────────────
                           Engine freezes (no PostureState change)
                           No UI change. PostureEngine handles internally.

TrackingQuality.lost (< absentThreshold = 1s) ────────────────────────────────
                           Engine freezes (dwell timer accumulates)

TrackingQuality.lost (≥ absentThreshold = 1s) ────────────────────────────────
                           → PostureState.absent (prior state saved)

Return from .absent:
  → 2s returnValidationWindow of .good quality required
  → short absence (< 30s): restore saved state + savedDriftTime
  → long absence (≥ 30s): → .good + pendingRecalibrationPrompt = true
```

**Key rule:** `.absent` never advances the posture state machine. `lastGoodUpdateTimestamp` is cleared on entry. `.degraded` freezes silently.

---

## Files to Change

### Step 1 — `PostureThresholds`: add thresholds

**File:** `PostureLogic/Sources/PostureLogic/Models/PostureThresholds.swift`

```swift
// MARK: - Mode Switching
public var depthRecoveryDelay: TimeInterval = 2.0
public var absentThreshold: TimeInterval = 1.0          // changed from 3.0
public var absentResumeThreshold: TimeInterval = 30.0   // NEW: short vs long absence
public var returnValidationWindow: TimeInterval = 2.0   // NEW: re-validation on return
```

---

### Step 2 — `PostureEngine`: rework quality handling

**File:** `PostureLogic/Sources/PostureLogic/Engines/PostureEngine.swift`

#### New stored properties

```swift
/// Timestamp when `.lost` quality was first observed in the current run.
private var lostQualityStart: TimeInterval?

/// State saved immediately before entering `.absent`.
private var savedPostureState: PostureState?

/// Accumulated drift time saved with savedPostureState (for drifting restoration).
private var savedDriftTime: TimeInterval = 0

/// Timestamp when `.absent` was declared (nil = not in a real absence).
private var absenceDeclaredAt: TimeInterval?

/// Timestamp when return-validation began (after quality recovers to .good).
private var returnValidationStart: TimeInterval?

/// Set to true when a long absence ends. Pipeline reads and clears via consumeRecalibrationPrompt().
var pendingRecalibrationPrompt: Bool = false
```

#### Rework of the guard block

Replace `guard trackingQuality.allowsPostureJudgement` with:

```swift
guard trackingQuality.allowsPostureJudgement else {
    lastGoodUpdateTimestamp = nil
    handleNonGoodQuality(quality: trackingQuality, at: metrics.timestamp)
    return currentState
}

// Quality is .good — reset lost-dwell tracker
lostQualityStart = nil

// Return validation: require returnValidationWindow of good data
// before committing to a state after a real (declared) absence.
if currentState == .absent, let declaredAt = absenceDeclaredAt {
    if returnValidationStart == nil {
        returnValidationStart = metrics.timestamp
    }
    let validationElapsed = metrics.timestamp - returnValidationStart!
    if validationElapsed < thresholds.returnValidationWindow {
        return currentState  // Still validating — stay in .absent
    }
    returnValidationStart = nil
    commitReturnFromAbsence(absenceDuration: metrics.timestamp - declaredAt)
}
```

#### `handleNonGoodQuality(_:at:)` (new private method)

```swift
private func handleNonGoodQuality(quality: TrackingQuality, at timestamp: TimeInterval) {
    switch quality {
    case .degraded:
        lostQualityStart = nil
        returnValidationStart = nil

    case .lost:
        returnValidationStart = nil
        let dwellStart = lostQualityStart ?? timestamp
        lostQualityStart = dwellStart
        if timestamp - dwellStart >= thresholds.absentThreshold, currentState != .absent {
            saveAndDeclareAbsent(at: timestamp)
        }

    case .good:
        break
    }
}
```

#### `saveAndDeclareAbsent(at:)` (new private method)

```swift
private func saveAndDeclareAbsent(at timestamp: TimeInterval) {
    switch currentState {
    case .good, .drifting, .bad:
        savedPostureState = currentState
        savedDriftTime = (currentState.isDrifting) ? accumulatedDriftTime : 0
    default:
        break
    }
    currentState = .absent
    absenceDeclaredAt = timestamp
}
```

#### `commitReturnFromAbsence(absenceDuration:)` (new private method)

```swift
private func commitReturnFromAbsence(absenceDuration: TimeInterval) {
    defer {
        savedPostureState = nil
        savedDriftTime = 0
        absenceDeclaredAt = nil
    }
    if absenceDuration < thresholds.absentResumeThreshold, let saved = savedPostureState {
        currentState = saved
        accumulatedDriftTime = savedDriftTime
    } else {
        currentState = .absent  // state machine's .absent/.calibrating arm handles → .good
        accumulatedDriftTime = 0
        recoveryStartTime = nil
        if absenceDuration >= thresholds.absentResumeThreshold {
            pendingRecalibrationPrompt = true
        }
    }
}
```

#### `consumeRecalibrationPrompt()` (new internal method)

```swift
func consumeRecalibrationPrompt() -> Bool {
    guard pendingRecalibrationPrompt else { return false }
    pendingRecalibrationPrompt = false
    return true
}
```

---

### Step 3 — `Pipeline`: absence segments + recalibration prompt

**File:** `PostureLogic/Sources/PostureLogic/Pipeline.swift`

```swift
// New published properties
@Published public private(set) var absenceSegments: [(start: TimeInterval, end: TimeInterval?)] = []
@Published public private(set) var showRecalibrationPrompt: Bool = false

// After postureEngine.update(...):
let wasAbsent = self.postureState == .absent
let newPostureState = self.postureEngine.update(...)
self.postureState = newPostureState
let isAbsent = newPostureState == .absent

if isAbsent && !wasAbsent {
    self.absenceSegments.append((start: smoothedMetrics.timestamp, end: nil))
} else if wasAbsent && !isAbsent {
    if let idx = self.absenceSegments.indices.last, self.absenceSegments[idx].end == nil {
        self.absenceSegments[idx].end = smoothedMetrics.timestamp
    }
}

if self.postureEngine.consumeRecalibrationPrompt() {
    self.showRecalibrationPrompt = true
}

// New public method for dismissal:
public func dismissRecalibrationPrompt() {
    showRecalibrationPrompt = false
}
```

> **Note:** `showRecalibrationPrompt` is set by the engine on long-absence return. The UI observes it and shows a dismissible sheet/banner. Dismissal calls `pipeline.dismissRecalibrationPrompt()`.

---

### Step 4 — Tests

**New file:** `PostureLogic/Tests/PostureLogicTests/PostureEngineAbsenceTests.swift`

Test cases:
1. `.lost` quality, dwell < `absentThreshold` → state does NOT change to `.absent`
2. `.lost` quality, dwell ≥ `absentThreshold` → `PostureState.absent`
3. `.degraded` quality → engine freezes (no state change), no absence declared
4. Return from `.absent` (duration < 30s) with 2s validation → resumes saved state + drift time
5. Return from `.absent` (duration ≥ 30s) → goes to `.good`, `consumeRecalibrationPrompt()` returns true
6. Return validation window: quality returns, then drops again before 2s → stays in `.absent`
7. Initial startup (no `absenceDeclaredAt`): first `.good` frame from `.absent` → `.good` immediately (no 2s delay)
8. Pipeline: absence segment opened on `.absent` entry, closed on `.absent` exit
9. `reset()` clears all new state (lostQualityStart, savedPostureState, absenceDeclaredAt, etc.)

**Regression guard:** All existing `PostureLogicTests` must continue to pass.

---

## Out of Scope

- Persisting absence segments to disk / session history
- Exposing absence time in the UI (analytics screen)
- Distinguishing *why* tracking degraded (occlusion vs. lighting vs. pose confidence)
- Any changes to the Camera/Vision pipeline that feeds `TrackingQuality`

---

## Implementation Order

```
Step 0  plan.md updated                       ← this document
Step 1  PostureThresholds                     ← absentThreshold=1.0, new thresholds
Step 2  PostureEngine rework                  ← core logic + recalibration prompt
Step 3  Pipeline absence segments + prompt    ← telemetry + UI signal
Step 4  Tests (PostureEngineAbsenceTests)     ← verify all cases
```

Each step builds clean and passes all tests before proceeding to the next.
