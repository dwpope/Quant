# Adversarial Bug Investigation: UI Responsiveness & Camera Layout

You are an adversarial QA agent. Your job is to critically investigate the existing codebase, identify root causes for the reported bugs below, implement fixes, and verify they work. Do NOT trust that existing code is correct — question every assumption.

## Reported Bugs

### Bug 1: Slow Segmented Controller Switch (Calibration Settings)

**Symptom**: Switching the segmented picker between "Rear (Depth)" and "Front (2D)" in Calibration Settings is noticeably slow / laggy.

**Files to investigate**:
- `Quant/Views/CalibrationSettingsView.swift` — contains the Picker with `.pickerStyle(.segmented)` that calls `appModel.switchCameraMode(to:)`
- `Quant/AppModel.swift` — `switchCameraMode(to:)` method (around line 438). Performs sequential stop → detach → attach → start on camera sessions
- `Quant/Services/ARSessionService.swift` — rear camera session lifecycle
- `Quant/Services/FrontCameraSessionService.swift` — front camera session lifecycle
- `Quant/Models/CameraMode.swift` — the `CameraMode` enum

**Investigation checklist**:
- [ ] Is the Picker's `.onChange` blocking the main thread with an `await` call?
- [ ] Is `switchCameraMode(to:)` doing heavy work synchronously on MainActor?
- [ ] Are session stop/start operations slow? Can they be overlapped or deferred?
- [ ] Does the segmented control animation stall because the UI thread is blocked?
- [ ] Profile the switching path — which operation takes the most time?

**Fix strategy**: The picker selection must feel instant. Move heavy camera session work off the critical UI path. Consider:
- Updating the published `cameraMode` property immediately so the UI reflects the change
- Performing the session tear-down/setup asynchronously without blocking the picker animation
- Using `Task { }` or `Task.detached` to avoid blocking the MainActor during session switching
- Adding a brief loading/transition state if the camera swap inherently takes time

### Bug 2: Camera View Doesn't Stretch to Screen Edges

**Symptom**: The camera preview (both front and rear) doesn't fill edge-to-edge on iPhone. There are gaps/bars visible.

**Files to investigate**:
- `Quant/Views/CameraPreviewView.swift` — rear camera uses `ARView(frame: .zero)` — suspicious initial frame
- `Quant/Views/FrontCameraPreviewView.swift` — front camera uses `AVCaptureVideoPreviewLayer` via custom `PreviewUIView`
- `Quant/ContentView.swift` — both previews use `.ignoresSafeArea()` (around lines 24-32)

**Investigation checklist**:
- [ ] Is `ARView(frame: .zero)` causing the rear camera to not resize properly?
- [ ] Does `PreviewUIView` properly update its `AVCaptureVideoPreviewLayer` bounds on layout changes?
- [ ] Is `.ignoresSafeArea()` applied at the right level in the view hierarchy?
- [ ] Are there any parent containers (VStack, ZStack, etc.) constraining the preview size?
- [ ] Does `videoGravity = .resizeAspectFill` work correctly with the current layout?
- [ ] Is there a `safeAreaInset` or padding being applied upstream?
- [ ] Check if the `UIViewRepresentable` implementations properly handle `updateUIView` for bounds changes

**Fix strategy**: Both camera views must be truly edge-to-edge with no gaps:
- Ensure `ARView` gets proper frame from SwiftUI layout (not stuck at `.zero`)
- Ensure `PreviewUIView` updates its preview layer frame in `layoutSubviews()`
- Verify `.ignoresSafeArea()` is on the outermost container, not buried inside a constrained parent
- Test on multiple screen sizes if possible

## Approach

For each bug:

1. **Read** all relevant files thoroughly — understand the current implementation before changing anything
2. **Diagnose** — identify the specific root cause(s). Write your findings to `.ralph/agent/scratchpad.md`
3. **Fix** — implement the minimal, targeted fix. Do not refactor unrelated code
4. **Verify** — build the project (`xcodebuild build -scheme Quant -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`) and run PostureLogic tests (`swift test --package-path PostureLogic`) to ensure no regressions
5. **Commit** each bug fix separately with a descriptive commit message

## Constraints

- Do NOT refactor code unrelated to the bugs
- Do NOT add new features or "improvements" beyond fixing these two issues
- All existing tests must continue to pass
- Preserve backwards compatibility of all public APIs
- If a fix requires a new file, justify why — prefer modifying existing files

## Success Criteria

- [ ] Segmented controller in Calibration Settings switches instantly (no visible lag)
- [ ] Camera preview fills the entire screen edge-to-edge in both front and rear modes
- [ ] Project builds successfully with no warnings related to changes
- [ ] All PostureLogic tests pass (`swift test --package-path PostureLogic`)
- [ ] Each bug fix is in its own commit
- [ ] Root cause analysis documented in `.ralph/agent/scratchpad.md`
- [ ] Output: <promise>LOOP_COMPLETE</promise> when all criteria are met
