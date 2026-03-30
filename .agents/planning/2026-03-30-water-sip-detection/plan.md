# Water Sip Detection — Implementation Plan
**Date:** 2026-03-30

## Overview

Adds a desk-only hydration tracker to Quant. The system monitors both wrists for sipping
gestures using a three-signal scoring engine, optionally personalised via a calibration capture
mode. Frequency is tracked ("how regularly you're drinking while working"), not total volume.
UI is upfront about this limitation.

---

## Architecture

```
Camera → Pipeline → poseObservationPublisher (PassthroughSubject)
                          ↓
                    SipDetector (PostureLogic)
                     idle → candidate → confirmed → cooldown → idle
                          ↓ (SipEvent)
                    AppModel (app target)
                          ↓
                    SipStore (app target, persistence)
                          ↓
                    HydrationCard + SipTimelineView (UI)
```

**Key decisions:**
- `SipDetector` and `SipEvent` live in PostureLogic (zero UIKit deps, fully testable)
- Pipeline exposes `poseObservationPublisher`; Pipeline doesn't know SipDetector exists
- Persistence, calibration UI, and timeline view live in the app target
- Same pattern as PostureEngine/NudgeEngine

---

## Three-Signal Scoring

1. **Wrist-to-nose proximity** — normalised against shoulder width (scale-invariant)
2. **Wrist velocity profile** — accelerate-up, decelerate-near-face, pause, accelerate-down;
   chin-resting has near-zero velocity
3. **Duration band** — 1–8 seconds of face proximity scores positively

Trigger on whichever wrist (left or right) crosses threshold first.

---

## State Machine

```
idle → candidate → confirmed → cooldown → idle
```
- **idle**: monitoring both wrists
- **candidate**: one or more signals triggered, accumulating confirmation
- **confirmed**: all signal thresholds met → log SipEvent
- **cooldown**: suppress detection for N seconds (default 30s) after confirmed sip

---

## Data Model

```swift
// PostureLogic
struct SipEvent {
    let id: UUID
    let timestamp: TimeInterval   // sip start time
    let duration: TimeInterval    // how long wrist was near face
    let confidence: Float?        // nil until CreateML model exists
}

struct SipThresholds {
    var proximityThreshold: Float = 0.35       // wrist-to-nose / shoulder-width
    var velocityThreshold: Float = 0.008       // normalised units/frame
    var minDuration: TimeInterval = 1.0
    var maxDuration: TimeInterval = 8.0
    var cooldownDuration: TimeInterval = 30.0
    var candidateScoreRequired: Float = 2.0    // of 3 signals
}
```

---

## Calibration Capture

- `SipCalibrationCapture` records 10 seconds of raw keypoint data per sip
- After 5 recorded sips, derives thresholds from min/max values + 20% margin
- Derived thresholds replace defaults in `SipThresholds`

---

## Build Steps (commit after each)

### ✅ Step 1 — SipEvent + SipDetector in PostureLogic
Files:
- `PostureLogic/Sources/PostureLogic/Models/SipEvent.swift`
- `PostureLogic/Sources/PostureLogic/Models/SipThresholds.swift`
- `PostureLogic/Sources/PostureLogic/Engines/SipDetector.swift`

### ✅ Step 2 — SipCalibrationCapture in PostureLogic
Files:
- `PostureLogic/Sources/PostureLogic/Engines/SipCalibrationCapture.swift`

### ✅ Step 3 — Pipeline poseObservationPublisher
Files:
- `PostureLogic/Sources/PostureLogic/Pipeline.swift` (add PassthroughSubject, publish each observation)

### ✅ Step 4 — SipStore in app target
Files:
- `Quant/Models/SipStore.swift`

### ✅ Step 5 — Wire SipDetector in AppModel
Files:
- `Quant/AppModel.swift` (add SipDetector, subscribe to poseObservationPublisher, save events)

### ✅ Step 6 — Functional monitoring screen: two cards
Files:
- `Quant/ContentView.swift` (replace placeholder monitoringView)
- `Quant/Views/PostureCard.swift`
- `Quant/Views/HydrationCard.swift`

### ✅ Step 7 — SipTimelineView
Files:
- `Quant/Views/SipTimelineView.swift`

### ✅ Step 8 — Sip calibration UI
Files:
- `Quant/Views/SipCalibrationView.swift`

### ✅ Step 9 — Debug overlay sip info
Files:
- `Quant/Views/DebugOverlayView.swift` (add SipDetector debug state section)

### ✅ Step 10 — Tests
Files:
- `PostureLogic/Tests/PostureLogicTests/SipDetectorTests.swift`
- `PostureLogic/Tests/PostureLogicTests/SipCalibrationCaptureTests.swift`

---

## Test Matrix (Step 10)

### SipDetectorTests
- `test_idle_noSignals_staysIdle` — wrist far from face, no state change
- `test_proximityAlone_entersCandidate` — proximity signal alone enters candidate
- `test_allSignals_confirmedSip` — all three signals → confirmed, SipEvent emitted
- `test_confirmed_entersCooldown` — after confirm, suppresses next sip for cooldown duration
- `test_cooldownExpiry_returnsToIdle` — after cooldown, idle resumes
- `test_candidateAbandoned_ifProximityLost` — wrist drops away → back to idle
- `test_bothWrists_triggerOnFirst` — left wrist triggers; right wrist also rising doesn't double-fire
- `test_chinResting_noConfirm` — zero velocity near face → stays candidate, never confirms
- `test_durationTooShort_noConfirm` — wrist near face < minDuration → no event
- `test_durationTooLong_noConfirm` — wrist near face > maxDuration → abandoned
- `test_reset_clearsState` — reset() returns to idle

### SipCalibrationCaptureTests
- `test_fewerThan5Sips_notReady` — 4 recorded sips → `isReady` false
- `test_exactly5Sips_isReady` — 5 sips → `isReady` true
- `test_derivedThresholds_withinMargin` — derived proximity = min of samples * 0.8

---

## UI Layout Reference

**Functional monitoring screen:**
```
┌─────────────────────────────┐
│  POSTURE                    │
│  ● Good / Drifting / Bad    │
│  State description          │
└─────────────────────────────┘
┌─────────────────────────────┐
│  HYDRATION                  │
│  12 sips today              │
│  Last sip 4 min ago         │
│  Desk use only              │
└─────────────────────────────┘
```

**Sip Timeline:**
```
Today's Sips                    [+]
─────────────────────────────────
 9:14 AM     ← swipe to delete
 9:52 AM
10:30 AM
11:05 AM
```
