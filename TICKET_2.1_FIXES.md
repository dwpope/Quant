# Ticket 2.1 — Critical Fixes for ARFrame Retention and Pose Detection

## Issues Identified from Device Testing

### 1. ARFrame Retention Memory Issue
**Symptom**: `ARSession is retaining 11-13 ARFrames` warning in logs

**Root Cause**: The Pipeline was creating a new async Task for every incoming camera frame (30-60 FPS), but Vision pose processing takes ~100-200ms. This created a backlog of concurrent tasks, each retaining an ARFrame in memory.

**Impact**:
- Memory pressure and potential crashes
- Degraded AR tracking performance
- Possible frame delivery stoppage

### 2. Tracking Always Shows "Lost"
**Symptom**: Debug UI constantly shows `Tracking: lost`

**Related To**: The frame retention issue may have been preventing Vision from properly processing poses.

### 3. High FPS Reading
**Symptom**: FPS showing 30.0 instead of ~10

**Clarification**: The FPS shown is the camera frame rate, not pose processing rate. This is normal.

## Fixes Applied

### Fix 1: Prevent Concurrent Pose Processing ✅

**File**: `PostureLogic/Sources/PostureLogic/Pipeline.swift`

Added concurrency control:
```swift
private var isPoseProcessing = false
private var poseProcessingDropped = 0

// In process method:
guard !isPoseProcessing else {
    poseProcessingDropped += 1
    return  // Drop frame if already processing
}

isPoseProcessing = true
```

**Result**: Only one pose detection task runs at a time, preventing ARFrame buildup.

### Fix 2: Release ARFrame References Earlier ✅

**File**: `PostureLogic/Sources/PostureLogic/Pipeline.swift`

Extract only needed data before async processing:
```swift
// Extract only what we need to avoid retaining the entire ARFrame
let timestamp = frame.timestamp
let hasPixelBuffer = frame.pixelBuffer != nil

// Process asynchronously without holding full frame
Task { [weak self] in
    // ...
}
```

**Result**: ARFrame can be released immediately after extracting essential data.

### Fix 3: Proper MainActor Isolation ✅

**File**: `PostureLogic/Sources/PostureLogic/Pipeline.swift`

Ensure UI updates happen on main thread:
```swift
await MainActor.run {
    self.latestPoseObservation = poseObservation
    self.trackingQuality = quality
    // ... other UI-bound updates
}
```

**Result**: Thread-safe updates without blocking frame processing.

### Fix 4: Enhanced Debug Logging ✅

**Files**:
- `PostureLogic/Sources/PostureLogic/Services/PoseService.swift`
- `PostureLogic/Sources/PostureLogic/Pipeline.swift`

Added detailed logging:
```swift
// PoseService logs:
print("⚠️ PoseService: No pixel buffer in frame")
print("⚠️ PoseService: Vision returned no results")
print("✓ PoseService: Detected \(keypoints.count) keypoints, confidence: \(confidence)")
print("❌ PoseService: Vision error: \(error)")

// Pipeline logs:
print("✓ Pose detected: \(obs.keypoints.count) keypoints, confidence: \(obs.confidence)")
print("✗ No pose detected")
```

**Result**: Clear visibility into what's happening with pose detection.

## Expected Behavior After Fixes

### Console Logs
You should now see one of these messages every ~100-200ms:

**Success case**:
```
✓ PoseService: Detected 17 keypoints, confidence: 0.92
✓ Pose detected: 17 keypoints, confidence: 0.92
```

**No person in frame**:
```
⚠️ PoseService: Vision returned no results
✗ No pose detected
```

**Errors** (if any):
```
❌ PoseService: Vision error: [error description]
✗ No pose detected
```

### Debug UI
- **Tracking**: Should show `good` when you're visible with shoulders and head detected
- **Tracking**: Should show `degraded` when partially visible or low confidence
- **Tracking**: Should show `lost` when no pose detected
- **FPS**: 30.0 is normal (camera rate, not pose processing rate)

### ARFrame Retention Warning
**Should NOT appear** anymore. If it still appears, please report immediately.

## Testing Checklist

After deploying these fixes, please test:

1. ✅ **No ARFrame retention warnings** in console
2. ✅ **Tracking quality changes** when you move in/out of frame
3. ✅ **Console shows pose detection logs** every ~100-200ms
4. ✅ **App remains responsive** during operation
5. ✅ **Memory usage stays stable** (no growing memory footprint)

### Specific Tests

**Test 1: Enter/Exit Frame**
- Start out of frame → Should log "Vision returned no results", Tracking: lost
- Step into frame → Should log "Detected X keypoints", Tracking: good/degraded
- Step out → Should return to "Vision returned no results", Tracking: lost

**Test 2: Partial Visibility**
- Show only face → Should detect some keypoints but tracking may be degraded
- Show shoulders + head → Should show tracking: good

**Test 3: Memory Stability**
- Run for 2-3 minutes continuously
- Monitor Xcode's memory debugger
- Memory should stabilize, not continuously grow
- No ARFrame retention warnings should appear

## What to Report

If issues persist, please capture:

1. **Console logs** - especially:
   - Any ARFrame retention warnings
   - PoseService log messages
   - Any Vision error messages

2. **Debug UI values**:
   - Tracking quality reading
   - Mode (should be depthFusion on LiDAR devices)
   - Depth confidence

3. **Behavior description**:
   - Does tracking ever change from "lost"?
   - Does it respond when you move in/out of frame?
   - Any app freezing or crashes?

## Technical Notes

### Why One Task at a Time?
Vision's `VNDetectHumanBodyPoseRequest` is CPU-intensive. Processing multiple frames concurrently:
- Saturates CPU
- Causes memory pressure
- Retains ARFrames longer than necessary

By processing one frame at a time and dropping intermediate frames, we:
- Reduce CPU usage to acceptable levels
- Release ARFrames immediately
- Still maintain ~10 FPS pose detection (adequate for posture monitoring)

### Frame Dropping is Intentional
The `poseProcessingDropped` counter tracks frames skipped while processing. This is **expected and correct**:
- Camera produces 30-60 FPS
- Pose detection takes ~100-200ms (5-10 FPS max)
- We drop ~20-50 frames/second, process ~10 frames/second
- This is sufficient for posture detection and prevents performance issues

## Files Modified

- `PostureLogic/Sources/PostureLogic/Pipeline.swift` - Concurrency control, ARFrame release
- `PostureLogic/Sources/PostureLogic/Services/PoseService.swift` - Debug logging
