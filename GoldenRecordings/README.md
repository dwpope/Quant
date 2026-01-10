# Golden Recordings

This directory contains reference recordings for regression testing the posture detection system.

## Purpose

These recordings serve as ground truth for validating:
- Posture detection algorithms
- Slouch detection accuracy
- Mode switching behavior (depth fusion ↔ 2D fallback)
- Task mode classification (reading vs typing)
- Replay service functionality

## Recordings

### 1. good_posture_5min.json

**Duration:** 5 minutes (3000 samples @ 10 FPS)
**File Size:** ~1.8 MB
**Description:** Sustained good posture with minimal variation

**Characteristics:**
- Stable position throughout
- Depth fusion enabled
- Good tracking quality
- Subtle breathing and micro-movements
- Used for validating false positive rate

**Tags:** `goodPosture` (automatic)

**Use Cases:**
- Testing that good posture doesn't trigger false nudges
- Validating baseline calibration
- Performance testing (long session stability)

---

### 2. gradual_slouch.json

**Duration:** 10 minutes (6000 samples @ 10 FPS)
**File Size:** ~3.5 MB
**Description:** Progressive posture deterioration from good to bad

**Characteristics:**
- **Minutes 0-2:** Good posture (baseline)
- **Minutes 2-6:** Gradual forward creep and head drop
- **Minutes 6-10:** Sustained slouch (head forward offset > 0.10m, torso angle > 15°)

**Metrics Progression:**
- Head forward offset: 0.02m → 0.10m
- Torso angle: 2° → 15°
- Head position Z: 0.88m → 0.75m (13cm closer)

**Tags:**
- `goodPosture` (automatic, minute 0-1)
- `slouching` (voice, minute 2)
- `slouching` (automatic, minute 6)

**Use Cases:**
- Primary test for slouch detection rate (≥70% success criteria)
- Validating state transitions: Good → Drifting → Bad
- Testing nudge timing (should fire after 5 minutes of bad posture)
- Regression testing for detection accuracy

**Detection Baseline:** 19.7% of samples exceed thresholds (1184/6000)

---

### 3. reading_vs_typing.json

**Duration:** 8 minutes (4800 samples @ 10 FPS)
**File Size:** ~2.5 MB
**Description:** Alternating task modes with distinct movement patterns

**Characteristics:**
- **Minutes 0-2:** Reading (minimal movement, small head oscillations)
- **Minutes 2-4:** Typing (moderate movement, slight forward lean)
- **Minutes 4-6:** Reading again
- **Minutes 6-8:** Typing again

**Movement Patterns:**
- **Reading:** Avg movement 0.005m, small head oscillations
- **Typing:** Avg movement 0.007m, regular arm movements, forward lean

**Tags:**
- `reading` (automatic, minute 0)
- `typing` (voice, minute 2)
- `reading` (voice, minute 4)
- `typing` (manual, minute 6)

**Use Cases:**
- Testing task mode classification (≥80% accuracy criteria)
- Validating task-adjusted thresholds (reading allows more forward lean)
- Training data for movement pattern recognition

---

### 4. depth_fallback_scenario.json

**Duration:** 6 minutes (3600 samples @ 10 FPS)
**File Size:** ~2.1 MB
**Description:** Intermittent depth availability testing mode switching

**Characteristics:**
| Time Window | Depth Mode | Tracking Quality |
|-------------|------------|------------------|
| 0-60s | Depth Fusion | Good |
| 60-120s | 2D Only | Degraded |
| 120-180s | Depth Fusion | Good |
| 180-240s | 2D Only | Degraded |
| 240-360s | Depth Fusion | Good |

**Tags:** `goodPosture` (automatic, at each mode transition)

**Device Metadata:** iPhone14,7 (non-LiDAR device simulation)

**Use Cases:**
- Testing mode switching logic
- Validating 2D fallback metrics work correctly
- Testing depth recovery delay (2 seconds)
- Ensuring posture detection continues during depth loss

---

## Generation

Recordings are generated synthetically using `GoldenRecordingGenerator.swift` to ensure:
- Consistent, reproducible test data
- Known ground truth for validation
- Wide coverage of edge cases
- Simulator compatibility (no real camera needed)

To regenerate recordings:

```bash
cd PostureLogic
swift test --filter GoldenRecordingTests.test_generateGoldenRecordings
```

## Validation

All recordings are validated with comprehensive tests:

```bash
cd PostureLogic
swift test --filter GoldenRecordingTests
```

**Test Coverage:**
- Structure validation (sample count, timestamps, tags)
- Characteristics validation (posture metrics, mode transitions)
- Loading from disk (JSON decoding)
- ReplayService integration
- Success criteria baselines

## Success Criteria Alignment

These recordings are designed to support the project success criteria:

| Criterion | Recording | Expected Result |
|-----------|-----------|-----------------|
| Detection rate ≥70% | gradual_slouch.json | Should detect sustained slouch in minutes 6-10 |
| False positive <3% | good_posture_5min.json | Should NOT trigger nudges during good posture |
| Task mode accuracy ≥80% | reading_vs_typing.json | Should correctly classify reading vs typing segments |
| Recovery within 5s | gradual_slouch.json | State should return to Good when posture corrects |

## File Format

Recordings are JSON-encoded `RecordedSession` objects containing:

```swift
{
  "id": "UUID",
  "startTime": "ISO8601 date",
  "endTime": "ISO8601 date",
  "samples": [PoseSample],
  "tags": [Tag],
  "metadata": SessionMetadata
}
```

Each `PoseSample` includes:
- 3D positions (head, shoulders)
- Derived angles (torso, twist)
- Depth mode and tracking quality
- Timestamp

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-10 | Initial golden recordings for Ticket 2.6 |

## Notes

- Recordings use deterministic UUIDs for reproducibility
- Timestamps start at Unix epoch reference dates
- Noise and breathing patterns are simulated with consistent random seeds
- File sizes are validated to stay under spec limits (< 5MB for 10 minutes)
