# Absence Detection — Implementation Plan

_Planning session: 2026-03-27_

## Problem Statement

Distinguish between two cases that currently look identical to the app:

1. **User is absent** — they left the seat. Camera sees an empty room.
2. **Tracking degraded** — user is present but the model can't detect them (occlusion, lighting, bad angle).

Currently, both cases map to `TrackingQuality.lost`, which silently freezes `PostureEngine` with no state change and no UI feedback.

---

## Design Decisions

| # | Question | Decision |
|---|----------|----------|
| Q1 | Mental model | **Signal-based.** `.degraded` = user present, tracking bad. `.lost` = user absent. Short `.lost` spikes absorbed by existing 3-frame smoother. |
| Q2 | Entry timing for `.absent` | **Short dwell.** Require `.lost` quality to sustain for `absentThreshold` (already 3.0s in `PostureThresholds`) before declaring `.absent`. |
| Q3 | Return path from `.absent` | **Duration-dependent.** Absence < 30s → resume saved pre-absence state. Absence ≥ 30s → reset to `.good`. |
| Q4 | Session analytics during absence | **Tracked separately.** Session clock continues; absence intervals are logged and excluded from posture quality calculations. |
| Q5 | `.degraded` visibility | **Distinct PostureState.** Promote to a visible `PostureState` case with its own overlay. User sees "tracking struggling" vs "you're away". |

---

## State Machine (New)

```
TrackingQuality.good   ──────────────────────────────────────────────────────────────
                           ┌────────┐  bad metrics  ┌──────────┐  timeout  ┌───────┐
                           │  GOOD  │ ────────────> │ DRIFTING │ ────────> │  BAD  │
                           └────────┘ <──────────── └──────────┘           └───────┘
                                good metrics                                    │
                                    ^──────────────── recovery grace ───────────┘

TrackingQuality.degraded ─────────────────────────────────────────────────────────────
                           Any real state → .degraded immediately
                           .degraded + quality recovers to .good → restore savedState

TrackingQuality.lost (< absentThreshold) ─────────────────────────────────────────────
                           Any real state → .degraded (same UI; dwell timer starts)

TrackingQuality.lost (≥ absentThreshold) ─────────────────────────────────────────────
                           → .absent
                           .absent + quality recovers to .good:
                             absenceDuration < absentResumeThreshold → restore savedState
                             absenceDuration ≥ absentResumeThreshold → .good
```

**Key rule:** `.degraded` and `.absent` never advance the posture state machine. `lastGoodUpdateTimestamp` is cleared on entry to both.

---

## Files to Change

### Step 1 — `PostureState`: add `.degraded` case

**File:** `PostureLogic/Sources/PostureLogic/Models/PostureState.swift`

Add `.degraded` between `.absent` and `.calibrating`. The compiler will flag every exhaustive switch that needs updating (60+ variant views, `PostureDisplayData`, `DebugOverlayView`).

```swift
public enum PostureState: Codable, Equatable {
    case absent
    case degraded   // NEW: user present, tracking struggling
    case calibrating
    case good
    case drifting(since: TimeInterval)
    case bad(since: TimeInterval)
}
```

**Blast radius:** Every `switch postureState` in the codebase. Most variant views treat all non-`.absent` states identically for their overlays, so `.degraded` can share the `.absent` arm in most places and only diverge at the overlay layer.

---

### Step 2 — `PostureThresholds`: add `absentResumeThreshold`

**File:** `PostureLogic/Sources/PostureLogic/Models/PostureThresholds.swift`

`absentThreshold: TimeInterval = 3.0` already exists and covers the Q2 dwell. Only one new property is needed:

```swift
// MARK: - Mode Switching
public var depthRecoveryDelay: TimeInterval = 2.0
public var absentThreshold: TimeInterval = 3.0
public var absentResumeThreshold: TimeInterval = 30.0  // NEW
```

---

### Step 3 — `PostureEngine`: rework quality handling

**File:** `PostureLogic/Sources/PostureLogic/Engines/PostureEngine.swift`

#### New stored properties

```swift
/// Timestamp when `.lost` quality was first observed in the current run.
/// Nil when quality is not `.lost`.
private var lostQualityStart: TimeInterval?

/// The posture state saved immediately before entering `.degraded` or `.absent`.
/// Restored when tracking quality recovers (subject to absence duration check).
private var savedPostureState: PostureState?

/// Timestamp when `.absent` was declared. Used to determine short vs. long absence.
private var absenceDeclaredAt: TimeInterval?
```

#### Rework of the guard block

The current `guard trackingQuality.allowsPostureJudgement` block returns early and freezes silently. Replace it with explicit dispatch:

```swift
// SAFETY GATE: Don't judge posture with unreliable data
guard trackingQuality == .good else {
    lastGoodUpdateTimestamp = nil
    handleNonGoodQuality(trackingQuality, at: metrics.timestamp)
    return currentState
}

// Quality is .good — reset lost-dwell tracker
lostQualityStart = nil

// Handle return from .absent or .degraded
if currentState == .absent || currentState == .degraded {
    restoreFromTrackingLoss(at: metrics.timestamp)
}
```

#### `handleNonGoodQuality(_:at:)` (new private method)

```swift
private func handleNonGoodQuality(_ quality: TrackingQuality, at timestamp: TimeInterval) {
    switch quality {
    case .degraded:
        lostQualityStart = nil          // reset lost dwell
        saveAndTransition(to: .degraded)

    case .lost:
        let dwellStart = lostQualityStart ?? timestamp
        lostQualityStart = dwellStart

        let dwell = timestamp - dwellStart
        if dwell >= thresholds.absentThreshold {
            // Sustained loss → declare absent
            if currentState != .absent {
                saveAndTransition(to: .absent)
                absenceDeclaredAt = timestamp
            }
        } else {
            // Still in dwell window → show degraded
            saveAndTransition(to: .degraded)
        }

    case .good:
        break // unreachable; handled by guard above
    }
}
```

#### `saveAndTransition(to:)` (new private method)

```swift
private func saveAndTransition(to newState: PostureState) {
    // Only save if we're leaving a "real" posture state
    switch currentState {
    case .good, .drifting, .bad:
        savedPostureState = currentState
    default:
        break // already in .absent/.degraded/.calibrating — don't overwrite saved state
    }
    currentState = newState
}
```

#### `restoreFromTrackingLoss(at:)` (new private method)

```swift
private func restoreFromTrackingLoss(at timestamp: TimeInterval) {
    defer {
        savedPostureState = nil
        absenceDeclaredAt = nil
        lostQualityStart = nil
    }

    // For .degraded: always restore (no duration rule — user was present the whole time)
    guard currentState == .absent else {
        currentState = savedPostureState ?? .good
        return
    }

    // For .absent: duration determines whether to restore or reset
    let absenceDuration = absenceDeclaredAt.map { timestamp - $0 } ?? .infinity
    if absenceDuration < thresholds.absentResumeThreshold, let saved = savedPostureState {
        currentState = saved
    } else {
        currentState = .good
        accumulatedDriftTime = 0
        recoveryStartTime = nil
    }
}
```

---

### Step 4 — `Pipeline`: track absence segments

**File:** `PostureLogic/Sources/PostureLogic/Pipeline.swift`

Add an `absenceSegments` log published alongside posture state. Each segment is open (nil end) until absence resolves.

```swift
// New published property on Pipeline
@Published public private(set) var absenceSegments: [(start: TimeInterval, end: TimeInterval?)] = []
```

In the section that calls `postureEngine.update(...)`, detect `.absent` entry/exit and append/close segments:

```swift
let previousState = currentPostureState
let newState = postureEngine.update(metrics: smoothedMetrics, taskMode: inferredTaskMode, trackingQuality: finalQuality)

// Track absence segments
if case .absent = newState, !(previousState == .absent) {
    absenceSegments.append((start: smoothedMetrics.timestamp, end: nil))
} else if case .absent = previousState, !(newState == .absent) {
    if let last = absenceSegments.indices.last, absenceSegments[last].end == nil {
        absenceSegments[absenceSegments.indices.last!].end = smoothedMetrics.timestamp
    }
}
```

> **Note:** Absence segments are currently in-memory only. Persistence to session storage is out of scope for this feature.

---

### Step 5 — New `DegradedTrackingOverlay.swift`

**File:** `Quant/Views/Showcase/DegradedTrackingOverlay.swift`

Mirror of `AbsenceOverlay` with distinct messaging. Uses a different icon (camera/eye symbol rather than person) and different text:

```swift
struct DegradedTrackingOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content
    // Pulsing indicator + "Tracking struggling..." text
    // Same reduce-motion and accessibility treatment as AbsenceOverlay
}
```

---

### Step 6 — `VariantShowcaseView`: wire up new overlay

**File:** `Quant/Views/Showcase/VariantShowcaseView.swift`

The showcase view wraps each variant with overlays based on `postureState`. Add the `.degraded` branch:

```swift
switch postureState {
case .absent:
    AbsenceOverlay { variantView }
case .degraded:
    DegradedTrackingOverlay { variantView }  // NEW
default:
    variantView
}
```

---

### Step 7 — Update exhaustive switches in variant views

The 60 variant views contain `switch`es on `PostureState` (mostly for alert/overlay colouring). Most already handle `.absent` by dimming or showing an overlay. `.degraded` should receive the same treatment as `.absent` in these views — the overlay layer in `VariantShowcaseView` is the source of truth for the distinct UI.

Pattern to apply across all affected variants:

```swift
// Before
case .absent:
    // dim / freeze

// After
case .absent, .degraded:
    // dim / freeze
```

This is a mechanical compiler-guided sweep, not a design decision per-variant.

---

### Step 8 — Tests

**New file:** `PostureLogic/Tests/PostureLogicTests/PostureEngineAbsenceTests.swift`

Test cases:
1. `.degraded` quality → `PostureState.degraded` immediately
2. `.lost` quality, dwell < `absentThreshold` → `PostureState.degraded`
3. `.lost` quality, dwell ≥ `absentThreshold` → `PostureState.absent`
4. Return from `.absent` (duration < 30s) → resumes saved `.drifting` state
5. Return from `.absent` (duration ≥ 30s) → resets to `.good`, clears `accumulatedDriftTime`
6. Return from `.degraded` → always resumes saved state regardless of duration
7. `.lost` → `.absent` → `.lost` again (re-entry): absence timer continues from original `absenceDeclaredAt`
8. Pipeline: absence segment opened on `.absent` entry, closed on `.absent` exit

**Regression guard:** All 297 existing `PostureLogicTests` must continue to pass.

---

## Out of Scope

- Persisting absence segments to disk / session history
- Exposing absence time in the UI (analytics screen)
- Distinguishing *why* tracking degraded (occlusion vs. lighting vs. pose confidence)
- Any changes to the Camera/Vision pipeline that feeds `TrackingQuality`

---

## Implementation Order

```
Step 1  PostureState + .degraded case     ← compiler flags all sites
Step 2  PostureThresholds + absentResumeThreshold
Step 3  PostureEngine rework              ← core logic
Step 4  Pipeline absence segments
Step 5  DegradedTrackingOverlay (new file)
Step 6  VariantShowcaseView wiring
Step 7  Variant views (.absent, .degraded arm sweep)
Step 8  Tests
```

Each step should build clean and pass all tests before proceeding to the next.
