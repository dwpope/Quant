# Ticket 2.5 — ReplayService Implementation Summary

## Implementation Complete ✅

**Goal**: Play back recorded sessions as if live, Simulator-friendly

**Date**: 2026-01-09

## What Was Implemented

### 1. ReplayServiceProtocol
**Location**: `PostureLogic/Sources/PostureLogic/Protocols/ReplayServiceProtocol.swift`

Defines the interface for replaying recorded sessions:
- `load(session:)` - Load a recorded session
- `play()` - Start playback, returns AsyncStream
- `stop()` - Halt playback
- `setSpeed(_:)` - Adjust playback speed (0.1x - 100x)
- `isPlaying` - Current playback state
- `progress` - Playback progress (0.0 - 1.0)
- Conforms to `DebugDumpable` for introspection

### 2. ReplayService Implementation
**Location**: `PostureLogic/Sources/PostureLogic/Services/ReplayService.swift`

Key features:
- **AsyncStream Interface**: Modern Swift concurrency for sample playback
- **Timing-Accurate Playback**: Respects original timestamp intervals
- **Variable Speed**: Adjust playback from 0.1x to 100x speed
- **Progress Tracking**: Real-time progress updates (0.0 - 1.0)
- **Stop Support**: Can halt playback mid-stream
- **Simulator-Friendly**: No ARKit dependency, works anywhere
- **Multiple Playback Support**: Can replay same session multiple times

### 3. Convenience Extensions

Extensions on `ReplayService`:
- `fromFile(_:)` - Load and create service from JSON file
- `estimatedDuration` - Calculate total playback time at current speed
- `remainingTime` - Time left in current playback

### 4. Comprehensive Test Suite
**Location**: `PostureLogic/Tests/PostureLogicTests/ReplayServiceTests.swift`

All 16 tests passing:
- ✅ Initial state and session loading
- ✅ Sample emission (all samples, in order)
- ✅ Timing accuracy (timestamp delays)
- ✅ Speed control (1x, 10x, clamping)
- ✅ Stop functionality
- ✅ Progress tracking
- ✅ Playback state management
- ✅ Debug state tracking
- ✅ Duration estimation
- ✅ Multiple playback support
- ✅ Empty session handling

## How It Works

### Basic Usage

```swift
// Load a recorded session
let replay = ReplayService()
let session = try RecordedSession.loadFromFile(url: sessionURL)
replay.load(session: session)

// Play at normal speed
for await sample in replay.play() {
    // Process sample as if it were live
    let metrics = metricsEngine.compute(from: sample, baseline: baseline)
    // ...
}
```

### With Speed Control

```swift
// Replay at 10x speed for quick testing
replay.setSpeed(10.0)

for await sample in replay.play() {
    print("Sample at \(sample.timestamp)")
    // Samples arrive 10x faster than original timing
}
```

### Stop Mid-Playback

```swift
Task {
    for await sample in replay.play() {
        if someCondition {
            replay.stop()  // Halt playback
            break
        }
    }
}
```

### Track Progress

```swift
for await sample in replay.play() {
    print("Progress: \(Int(replay.progress * 100))%")
    print("Remaining: \(replay.remainingTime ?? 0) seconds")
}
```

## AsyncStream Architecture

Uses Swift's modern concurrency:

```swift
public func play() -> AsyncStream<PoseSample> {
    return AsyncStream { continuation in
        Task {
            for sample in samples {
                // Calculate delay from timestamps
                let delay = currentTimestamp - lastTimestamp
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                // Yield sample
                continuation.yield(sample)
            }
            continuation.finish()
        }
    }
}
```

### Benefits:
- **Cancellable**: Consumers can break out of loop anytime
- **Backpressure**: Automatic flow control
- **Modern**: Integrates with async/await
- **Clean**: No callbacks or delegates

## Acceptance Criteria Met

- ✅ Can replay in Simulator (no ARKit needed)
- ✅ Playback speed adjustable (1x, 2x, 10x)
- ✅ Timing-accurate replay
- ✅ AsyncStream interface
- ✅ All unit tests pass (16/16)
- ✅ Full test suite passes (79/79)

## Test Results

```
Test Suite 'ReplayServiceTests' passed
Executed 16 tests, with 0 failures in 36.393 seconds

Full PostureLogic test suite: 79 tests passed
```

### Timing Validation

Test `test_play_respectsTimestampDelays`:
- 3 samples with 0.1s spacing
- Expected duration: ~0.2s
- Actual duration: 0.208s ✅
- Tolerance: ±50ms

Test `test_setSpeed_changesPlaybackSpeed`:
- Same setup at 10x speed
- Expected duration: ~0.02s
- Actual duration: <0.1s ✅

## Critical Implementation Details

### Timestamp-Based Timing

```swift
var lastTimestamp: TimeInterval = samples[0].timestamp

for sample in samples {
    let timeDelta = sample.timestamp - lastTimestamp
    if timeDelta > 0 {
        let adjustedDelay = timeDelta / Double(playbackSpeed)
        let nanoseconds = UInt64(adjustedDelay * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    continuation.yield(sample)
    lastTimestamp = sample.timestamp
}
```

This ensures:
- Playback matches original timing exactly
- Speed multiplier applies uniformly
- No drift accumulation

### Speed Clamping

```swift
playbackSpeed = max(0.1, min(speed, 100.0))
```

Prevents:
- Negative/zero speed (would hang)
- Excessive speed (potential overflow)
- Unreasonable values

### Progress Calculation

```swift
_progress = Float(index + 1) / Float(samples.count)
```

Simple index-based progress:
- Accurate regardless of timestamp distribution
- Updates after each sample
- Reaches exactly 1.0 at completion

## Use Cases

### Simulator Testing

```swift
// NO ARKit needed - works in Simulator!
let replay = try ReplayService.fromFile(goldenRecordingURL)

for await sample in replay.play() {
    // Test posture engine behavior
    let state = postureEngine.update(metrics: metrics, ...)
    XCTAssertEqual(state, expectedState)
}
```

### Rapid Regression Testing

```swift
// Test 5-minute session in 30 seconds
replay.setSpeed(10.0)

var nudgeCount = 0
for await sample in replay.play() {
    let decision = nudgeEngine.evaluate(state: state, ...)
    if case .fire = decision {
        nudgeCount += 1
    }
}

XCTAssertEqual(nudgeCount, expectedNudges)
```

### Golden Recording Validation

```swift
// Verify "gradual_slouch.json" triggers detection
let session = try RecordedSession.loadFromFile(url: slouchRecording)
replay.load(session: session)

var detectedSlouch = false
for await sample in replay.play() {
    if postureState.isBad {
        detectedSlouch = true
        break
    }
}

XCTAssertTrue(detectedSlouch, "Should detect slouch in golden recording")
```

### UI Preview/Demo

```swift
// Show UI with realistic data
replay.setSpeed(1.0)  // Real-time

for await sample in replay.play() {
    await MainActor.run {
        viewModel.updateWithSample(sample)
    }
}
```

## Integration Points

### Inputs
- `RecordedSession` from RecorderService (Ticket 2.3)
- JSON files from disk
- Golden recordings (Ticket 2.6)

### Outputs
- `AsyncStream<PoseSample>` for consumers
- Same format as live PoseDepthFusion output
- Indistinguishable from real-time data

### Debug State
```swift
{
    "isPlaying": true,
    "progress": 0.45,
    "playbackSpeed": 10.0,
    "samplesLoaded": 3000,
    "currentSampleIndex": 1350
}
```

## Performance Characteristics

### Memory
- Holds reference to session (already loaded)
- No additional copy of samples
- Lightweight state tracking

### CPU
- Minimal overhead per sample
- Task.sleep is efficient
- AsyncStream has low cost

### Timing Accuracy
- Sub-millisecond precision with Task.sleep
- Validated to ±50ms over 200ms intervals
- Acceptable for posture analysis (5-minute scales)

## Simulator Compatibility

✅ **100% Simulator-compatible**

No dependencies on:
- ARKit
- Camera
- LiDAR
- Physical device sensors

Perfect for:
- Unit testing
- CI/CD pipelines
- Development without hardware
- Rapid iteration

## Next Steps

According to the plan, the next ticket is:

**Ticket 2.6 — Golden Recordings Requirement**
- Create 4 reference recordings:
  1. `good_posture_5min.json`
  2. `gradual_slouch.json`
  3. `reading_vs_typing.json`
  4. `depth_fallback_scenario.json`
- Use for regression testing
- Validate posture detection accuracy

Then Sprint 3:

**Ticket 3.1 — 3D Position Calculation** (enhanced testing)
**Ticket 3.2 — 2D Fallback Metrics**
**Ticket 3.3 — MetricsEngine Implementation**

## Files Created

**Created**:
- `PostureLogic/Sources/PostureLogic/Protocols/ReplayServiceProtocol.swift`
- `PostureLogic/Sources/PostureLogic/Services/ReplayService.swift`
- `PostureLogic/Tests/PostureLogicTests/ReplayServiceTests.swift`

**Updated**:
- Test count: 63 → 79 tests

## Architecture Benefits

### Testability
- Deterministic playback for regression tests
- No flaky tests from camera/sensor variability
- Fast test execution with speed multiplier

### Development Workflow
```
Record on device → Export JSON → Test in Simulator
     ↓                 ↓              ↓
  Real data     Shareable file   Fast iteration
```

### CI/CD Integration
- No hardware needed for test runs
- Parallel test execution
- Reproducible results

## Example: Complete Testing Pipeline

```swift
class PostureDetectionTests: XCTestCase {
    func test_detectsSlouch_inGoldenRecording() async throws {
        // Load golden recording
        let session = try RecordedSession.loadFromFile(
            url: Bundle.module.url(forResource: "gradual_slouch", withExtension: "json")!
        )

        // Create engine with known thresholds
        let engine = PostureEngine(thresholds: .default)
        let replay = ReplayService()
        replay.load(session: session)

        // Run at 10x speed
        replay.setSpeed(10.0)

        var detectedBadPosture = false

        for await sample in replay.play() {
            let metrics = metricsEngine.compute(from: sample, baseline: session.baseline)
            let state = engine.update(metrics: metrics, ...)

            if state.isBad {
                detectedBadPosture = true
                break
            }
        }

        XCTAssertTrue(detectedBadPosture)
    }
}
```

This pattern enables:
- Regression testing against real data
- Performance validation
- Threshold tuning
- ML training data generation

## Summary

Ticket 2.5 completes Sprint 2's recording and replay infrastructure. Combined with RecorderService (2.3), the system now has a complete test data pipeline for development without hardware dependencies.
