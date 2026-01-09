# Ticket 2.2 — PoseSample Builder (Fusion Skeleton) Implementation Summary

## Implementation Complete ✅

**Goal**: Combine pose + depth into unified `PoseSample`

**Date**: 2026-01-09

## What Was Implemented

### 1. PoseDepthFusionProtocol
**Location**: `PostureLogic/Sources/PostureLogic/Protocols/PoseDepthFusionProtocol.swift`

Defines the interface for fusing 2D pose keypoints with depth data:
- `fuse(pose:depthSamples:confidence:cameraIntrinsics:) -> PoseSample`
- Conforms to `DebugDumpable` for introspection
- Supports both 3D (depth fusion) and 2D (fallback) modes

### 2. PoseDepthFusion Implementation
**Location**: `PostureLogic/Sources/PostureLogic/Services/PoseDepthFusion.swift`

Key features:
- **Automatic Mode Selection**: Chooses `DepthFusion` or `TwoDOnly` based on depth confidence and data availability
- **3D Unprojection**: Converts 2D keypoints + depth to 3D world coordinates using camera intrinsics
- **2D Fallback**: Produces valid samples using normalized coordinates when depth unavailable
- **Tracking Quality Detection**: Determines quality based on keypoint presence and confidence
- **Derived Metrics Calculation**: Computes torsoAngle, headForwardOffset, and shoulderTwist
- **Critical Keypoint Extraction**: Focuses on nose, shoulders, and hips for posture analysis

### 3. Comprehensive Test Suite
**Location**: `PostureLogic/Tests/PostureLogicTests/PoseDepthFusionTests.swift`

All 12 tests passing:
- ✅ Mode selection (depth fusion vs 2D only)
- ✅ Tracking quality determination (good/degraded/lost)
- ✅ 2D position calculations
- ✅ 3D position calculations with depth
- ✅ Timestamp preservation
- ✅ Debug state tracking

## How It Works

### Mode Selection

The service automatically selects the appropriate mode:

```swift
let mode = (confidence >= .medium && depthSamples != nil && cameraIntrinsics != nil)
    ? .depthFusion
    : .twoDOnly
```

**DepthFusion Mode**: When depth confidence is `.medium` or higher and all depth data available
**TwoDOnly Mode**: When depth unavailable, unreliable, or missing intrinsics

### 3D Unprojection (Depth Fusion Mode)

Implements the formula from Ticket 3.1 with proper column-major intrinsics:

```swift
let fx = intrinsics[0, 0]  // Focal length X
let fy = intrinsics[1, 1]  // Focal length Y
let cx = intrinsics[2, 0]  // Principal point X (column-major!)
let cy = intrinsics[2, 1]  // Principal point Y

let x = (Float(keypoint.x) - cx) * depth / fx
let y = (Float(keypoint.y) - cy) * depth / fy
let z = depth

return SIMD3(x, y, z)
```

### 2D Fallback Mode

When depth unavailable, uses normalized coordinates:

```swift
// Z component is 0 in 2D mode
let position = SIMD3<Float>(Float(keypoint.x), Float(keypoint.y), 0)
```

Metrics are still computed but use different approaches:
- **headForwardOffset**: Uses Y-difference scaled by shoulder width
- **shoulderTwist**: Cannot be accurately measured in 2D (returns 0)
- **torsoAngle**: Cannot be accurately measured in 2D (returns 0)

### Tracking Quality Determination

Based on keypoint availability and confidence:

```swift
func determineTrackingQuality(keypoints: CriticalKeypoints, poseConfidence: Float) -> TrackingQuality {
    guard keypoints.hasMinimumRequired else { return .lost }

    let avgConfidence = (nose + leftShoulder + rightShoulder) / 3.0

    if avgConfidence > 0.7 && poseConfidence > 0.7 {
        return .good
    } else if avgConfidence > 0.4 {
        return .degraded
    } else {
        return .lost
    }
}
```

**Requirements for minimum tracking**:
- Both shoulders present
- Nose (head) present
- Average confidence > 0.4

## Acceptance Criteria Met

- ✅ Produces valid samples in both depth and 2D modes
- ✅ Computes 3D positions from 2D keypoints + depth
- ✅ Calculates derived metrics (torsoAngle, headForwardOffset, shoulderTwist)
- ✅ Handles missing depth gracefully
- ✅ Determines tracking quality accurately
- ✅ All unit tests pass (12/12)
- ✅ Full test suite passes (40/40)

## Test Results

```
Test Suite 'PoseDepthFusionTests' passed
Executed 12 tests, with 0 failures in 0.002 seconds

Full PostureLogic test suite: 40 tests passed
```

## Critical Implementation Details

### Column-Major Intrinsics (Known Gotcha)
✅ **Correctly implemented**: `cx = intrinsics[2, 0]` not `intrinsics[0, 2]`

### Mode Selection Strategy
- Requires `.medium` or higher depth confidence
- Falls back immediately when confidence drops
- Works with ModeSwitcher (Ticket 1.3) for stable mode transitions

### Keypoint Matching
- Finds closest depth sample to each keypoint position
- Only accepts matches within 5% of frame size
- Returns zero vector if no valid depth sample found

## Integration Points

### Inputs
- `PoseObservation` from PoseService (Ticket 2.1)
- `[DepthAtPoint]` from DepthService (Ticket 1.2)
- `DepthConfidence` from DepthService
- `simd_float3x3` camera intrinsics from ARFrame

### Outputs
- `PoseSample` with unified 3D or 2D positions
- `TrackingQuality` for downstream filtering
- `DepthMode` indicator for context

### Debug State
```swift
{
    "lastMode": "depthFusion",      // Current mode being used
    "lastKeypointCount": 17,         // Keypoints in last observation
    "last3DPointsComputed": 3        // Successfully unprojected points
}
```

## Next Steps

According to the plan, the next ticket is:

**Ticket 2.3 — RecorderService (Timestamped Samples)**
- Record stream of `PoseSample` to memory
- Export to JSON
- File size < 5MB for 5 minutes

OR

**Ticket 3.1 — 3D Position Calculation** (already partially implemented in this ticket)
- Enhanced testing with known intrinsics
- Validation of unprojection accuracy

## Files Created

**Created**:
- `PostureLogic/Sources/PostureLogic/Protocols/PoseDepthFusionProtocol.swift`
- `PostureLogic/Sources/PostureLogic/Services/PoseDepthFusion.swift`
- `PostureLogic/Tests/PostureLogicTests/PoseDepthFusionTests.swift`

## Architecture Notes

The PoseDepthFusion service is the critical bridge between raw sensor data and posture analysis:

```
PoseService (2D keypoints) ────┐
                                ├──> PoseDepthFusion ──> PoseSample
DepthService (depth samples) ──┘

PoseSample ──> MetricsEngine ──> RawMetrics ──> PostureEngine
```

This design:
- Encapsulates complexity of 3D unprojection
- Handles mode switching transparently
- Provides consistent output format for downstream engines
- Enables testing without real ARKit hardware

## Future Enhancements

Potential improvements for later sprints:
- **Torso angle calculation**: Needs baseline reference for vertical
- **Improved 2D metrics**: Better approximations without depth
- **Keypoint filtering**: Temporal smoothing of noisy positions
- **Hip inclusion**: Use hip positions for full torso analysis
