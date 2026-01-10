# Golden Recordings

This directory contains reference recordings for regression testing the posture detection system.

## Recordings

### 1. good_posture_5min.json
- **Duration:** 5 minutes (3000 samples @ 10 FPS)
- **Size:** ~1.8 MB
- **Purpose:** Sustained good posture validation, false positive testing

### 2. gradual_slouch.json
- **Duration:** 10 minutes (6000 samples @ 10 FPS)
- **Size:** ~3.5 MB
- **Purpose:** Slouch detection validation, posture deterioration progression

### 3. reading_vs_typing.json
- **Duration:** 8 minutes (4800 samples @ 10 FPS)
- **Size:** ~2.5 MB
- **Purpose:** Task mode classification, movement pattern validation

### 4. depth_fallback_scenario.json
- **Duration:** 6 minutes (3600 samples @ 10 FPS)
- **Size:** ~2.1 MB
- **Purpose:** Mode switching testing, 2D fallback validation

## Regeneration

To regenerate all recordings:

```bash
cd PostureLogic
swift test --filter GoldenRecordingTests.test_generateGoldenRecordings
```

## Validation

To validate all recordings:

```bash
cd PostureLogic
swift test --filter GoldenRecordingTests
```

## Usage

Load recordings in tests:

```swift
let session = try GoldenRecordingLoader.loadGradualSlouch()
```

See `TICKET_2.6_SUMMARY.md` for complete details.
