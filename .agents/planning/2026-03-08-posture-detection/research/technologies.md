# Research: Technologies & Frameworks

## Vision Framework (Body Pose Detection)

- `VNDetectHumanBodyPoseRequest` — extracts 2D body keypoints from camera frames
- Returns `VNHumanBodyPoseObservation` with keypoints for 17 joints
- **Must throttle to ~10 FPS** — processing every frame is too expensive
- Y coordinates are flipped: use `1.0 - point.y` before using
- Works on both rear and front camera frames
- Simulator has no ARKit/LiDAR — must use `MockPoseProvider` for all Simulator testing

## ARKit (Rear Camera + Depth)

- `ARSession` with `ARBodyTrackingConfiguration` for rear camera
- Provides `ARFrame` with `capturedImage` (RGB) and `sceneDepth` (LiDAR depth map)
- Depth map is lower resolution than RGB — must scale coordinates
- `CVPixelBuffer` must be locked before reading depth values
- `ARSession` can silently fail after interruption — always check `trackingState`
- Depth values near frame edges are unreliable — ignore within 5% of edges
- `simd_float3x3` column-major: `fx = intrinsics[0,0]`, `cx = intrinsics[2,0]`

## AVFoundation (Front Camera)

- `AVCaptureSession` with `builtInWideAngleCamera` for front-facing camera
- **Critical**: Must set `connection.videoOrientation = .portrait` — without this, Vision sees landscape-oriented body (~87° twist offset)
- `startRunning()`/`stopRunning()` must run on dedicated serial queue, NOT main actor
- No depth data available — always `twoDOnly` mode
- Camera permission handling: `.notDetermined`, `.authorized`, `.denied`, `.restricted`

## WatchConnectivity

- `WCSession` for iPhone ↔ Apple Watch communication
- Dual-channel delivery: `sendMessage` (real-time) + `transferUserInfo` (fallback)
- Watch receives message and triggers haptic playback
- State tracking: isPaired, isReachable, totalSent, lastSentTime

## Audio Feedback

- Programmatic 880Hz sine wave generation (no external audio files needed)
- In-memory WAV with fade-in (10%) / fade-out (30%) envelope
- `.ambient` audio session category — respects system volume + mute switch
- 0.5s minimum play interval guard
- Configurable volume (default 0.3) and enable/disable toggle

## Key Data Types

- `CVPixelBuffer` — camera frame and depth map pixel data
- `simd_float3x3` — camera intrinsics matrix
- `SIMD3<Float>` — 3D positions
- `CGPoint` — 2D normalized keypoint positions (0–1)
- `TimeInterval` — timestamps throughout the pipeline

## Known Gotchas

| Issue | Solution |
|-------|----------|
| Vision pose detection returns flipped Y | Flip Y: `1.0 - point.y` before using |
| ARKit depth map lower res than RGB | Scale coordinates: `depthPoint = rgbPoint * (depthSize / rgbSize)` |
| `CVPixelBuffer` must be locked before reading | Always `CVPixelBufferLockBaseAddress(buffer, .readOnly)` and unlock after |
| Combine publishers retain self strongly | Use `[weak self]` in all `sink` closures |
| Simulator has no ARKit/LiDAR | Must use `MockPoseProvider` for all Simulator testing |
| `VNDetectHumanBodyPoseRequest` is slow | Throttle to 10 FPS max |
| ARSession can silently fail after interruption | Always check `trackingState` before trusting frame data |
| Depth values near edges unreliable | Ignore depth within 5% of frame edges |
| `simd_float3x3` column-major ordering | `fx = intrinsics[0,0]`, `cx = intrinsics[2,0]` (not `[0,2]`) |
| JSON encoding `TimeInterval` loses precision | Use `Int64` milliseconds for timestamps in recordings |
| SwiftUI view updates on background thread crash | Always dispatch to `@MainActor` before publishing |
| `ProcessInfo.thermalState` doesn't work in Simulator | Mock thermal states for testing |
| Front camera without portrait orientation | ~87° twist offset — set `videoOrientation = .portrait` |
