# Bug Fixes: UI Responsiveness & Camera Layout

Fix the two bugs reported in `Observed-bugs.md`.

## Bug 1: Slow Segmented Controller Switch (Calibration Settings)

**Symptom**: Switching the segmented picker between "Rear (Depth)" and "Front (2D)" in Calibration Settings is noticeably slow / laggy.

**Files to investigate**:
- `Quant/Views/CalibrationSettingsView.swift` — Picker with `.pickerStyle(.segmented)` calls `appModel.switchCameraMode(to:)`
- `Quant/AppModel.swift` — `switchCameraMode(to:)` method (~line 438). Performs sequential stop → detach → attach → start on camera sessions
- `Quant/Services/ARSessionService.swift` — rear camera session lifecycle
- `Quant/Services/FrontCameraSessionService.swift` — front camera session lifecycle
- `Quant/Models/CameraMode.swift` — the `CameraMode` enum

**Root cause likely**: The Picker's `.onChange` blocks the main thread with `await switchCameraMode(to:)`, stalling the segmented control animation while heavy camera session work runs on MainActor.

**Fix requirements**:
- The picker selection must feel instant — update `cameraMode` immediately so the UI reflects the change
- Move heavy camera session tear-down/setup off the critical UI path (use `Task { }` or similar)
- Add a brief loading/transition state if the camera swap inherently takes time

## Bug 2: Camera View Doesn't Stretch to Screen Edges

**Symptom**: The camera preview (both front and rear) doesn't fill edge-to-edge on iPhone. There are visible gaps/bars.

**Files to investigate**:
- `Quant/Views/CameraPreviewView.swift` — rear camera uses `ARView(frame: .zero)` — suspicious initial frame
- `Quant/Views/FrontCameraPreviewView.swift` — front camera uses `AVCaptureVideoPreviewLayer` via custom `PreviewUIView`
- `Quant/ContentView.swift` — both previews use `.ignoresSafeArea()` (~lines 24-32)

**Fix requirements**:
- Both camera views must be truly edge-to-edge with no gaps
- Ensure `ARView` gets proper frame from SwiftUI layout (not stuck at `.zero`)
- Ensure `PreviewUIView` updates its preview layer frame in `layoutSubviews()`
- Verify `.ignoresSafeArea()` is on the outermost container, not buried inside a constrained parent

## Process

1. Read all relevant files thoroughly before changing anything
2. Identify the specific root cause for each bug
3. Implement the minimal, targeted fix — do not refactor unrelated code
4. Build the project: `xcodebuild build -scheme Quant -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
5. Run tests: `swift test --package-path PostureLogic`
6. Commit each bug fix separately with a descriptive commit message
7. Record changed files and summary in `.ralph/agent/fresh-eyes-notes.md`

## Constraints

- Do NOT refactor code unrelated to the bugs
- Do NOT add new features beyond fixing these two issues
- All existing tests must continue to pass
- Preserve backwards compatibility of all public APIs
