# Tiredness signals in Front Face: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Front Face mode reads the body upright.
- The posture log records yawns, eye closure, long blinks, head distance, time since the last break, movement, and the camera mode.
- This is log only: no nudge or line changes.

**Architecture:**
- **Body points:** Vision gets the ARKit frame's orientation, and the oriented keypoints are put into the 720×1280 reference units every line was tuned in.
- **Face samples:** blendshapes are sampled at the ARKit frame rate (60 fps) in `ARFaceTrackingService`, before the pipeline's ~10 fps gate, into a locked 30-second buffer.
- **Summaries:** the posture log asks the buffer for a pure summary of each 10-second window.

**Tech stack:** Swift, ARKit (`ARFaceAnchor.blendShapes`, `ARCamera.projectPoint`), Vision (`VNImageRequestHandler(cvPixelBuffer:orientation:)`), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-27-tiredness-front-face-design.md`

**When:** after Dave's Front (2D) head and seat session on build `3dfc8d6` + `f623ba3`, so that session's log stays clean. **Commit only on Dave's word.**

## Global Constraints

- **One clock:** frame time in seconds since 1970 (`FrameClock`). ARKit timestamps are converted once in the service, as now.
- **Front (2D) unchanged:** its frames, keypoints, lines, nudges and log lines are byte-for-byte as before. New log fields are present only when there's data.
- **Lines and nudges unchanged** in every mode.
- **Eye closed** = both `eyeBlinkLeft` and `eyeBlinkRight` ≥ **0.8**.
- **Long blink** = a closure lasting ≥ **0.3 s**.
- **Yawn** = `jawOpen` ≥ **0.6**, held ≥ **2.0 s**, counted once per opening. Our call; the builder may tune it after a quick capture.
- **Break** = an absence of ≥ **120 s**.
- **No face, no reading:** untracked frames are left out of every share. A closure interrupted by a face dropout longer than **0.2 s** is discarded, never counted.
- **Tests:**
  - package: `cd PostureLogic && swift test`
  - app: `xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests -destination 'id=8E04449A-94EF-4F79-BFCE-71FD480E718C' -parallel-testing-enabled NO`
  - Both stay green with **no new warnings**. New logic is test-first.
- **Stray files:** delete `Icon\r` files (`find . -name $'Icon\r' -delete`) if a build reports "Multiple commands produce" or CodeSign detritus.

## Review Focus

1. **Looking down narrows the eyes without closing them:** `eyeBlink` around 0.5–0.7 for minutes must give an eyes-closed share of 0. Test in Task 2.
2. **Thermal throttling makes ARKit frames uneven:** shares weigh by time, not frame count. Test in Task 2.
3. **The face is lost mid-blink or mid-yawn:** it's not counted. Test in Task 2.
4. **A Front (2D) metrics line gains no face fields** and is unchanged. Test in Task 4.
5. **Mirroring of the oriented ARKit image is not certain from documentation** (it decides left versus right shoulder):
   - Task 1 logs a one-off check comparing ARKit's projected face position with Vision's nose.
   - The first Front Face session's log settles it.
   - Unit test: the check's classification, in Task 1.

---

### Task 1: Front Face body points upright

**Files:**
- Modify: `PostureLogic/Sources/PostureLogic/Models/InputFrame.swift`
- Modify: `PostureLogic/Sources/PostureLogic/Models/FrameOrientation.swift`
- Modify: `PostureLogic/Sources/PostureLogic/Services/PoseService.swift` (`process`, `keypoints(_:in:)`)
- Modify: `Quant/Services/ARFaceTrackingService.swift`
- Test: `PostureLogic/Tests/PostureLogicTests/FrontFaceOrientationTests.swift` (new)

**Interfaces:**
- Produces:
  - `InputFrame.visionOrientation: CGImagePropertyOrientation` (init parameter, default `.up`; import ImageIO).
  - `FrameOrientation.referenceUnits(_ point: CGPoint, width: Int, height: Int) -> CGPoint`, for an **upright** frame of any aspect. It keeps each point's pixel offset from the centre and expresses it in the units of a 720-wide, 1280-tall frame scaled to the same width:
    - x unchanged
    - y = 0.5 + (y − 0.5) · (height/width) · (720/1280)
  - `PoseService.orientedSize(width: Int, height: Int, orientation: CGImagePropertyOrientation) -> (width: Int, height: Int)`: swaps the sides for `.left`, `.right`, `.leftMirrored` and `.rightMirrored`.
  - `FrontFaceMirrorCheck.classify(visionNoseX: CGFloat, projectedFaceX: CGFloat) -> FrontFaceMirrorCheck.Result`, where `Result` is `.matches`, `.mirrored` or `.unclear`, with a 0.1 tolerance.

- [ ] **Step 1: Write the failing tests**

```swift
func test_referenceUnits_leaveA720x1280FrameUnchanged() {
    let p = CGPoint(x: 0.3, y: 0.7)
    XCTAssertEqual(FrameOrientation.referenceUnits(p, width: 720, height: 1280), p)
}
func test_referenceUnits_keepHeightOverWidthRatios_on4by3() {
    // 0.2 across and 0.1 down on a 1440×1920 upright frame: 288 px across, 192 px down.
    // Read back in the 720×1280 reference frame's pixels, the down/across ratio must stay 192/288.
    let a = FrameOrientation.referenceUnits(CGPoint(x: 0.4, y: 0.5), width: 1440, height: 1920)
    let b = FrameOrientation.referenceUnits(CGPoint(x: 0.6, y: 0.6), width: 1440, height: 1920)
    // Same pixel ratio on the reference frame: 0.667 = (dy·1280)/(dx·720)
    XCTAssertEqual(Double((b.y - a.y) * 1280 / ((b.x - a.x) * 720)), 192.0 / 288.0, accuracy: 1e-6)
}
func test_orientedSize_swapsForQuarterTurns() {
    XCTAssertTrue(PoseService.orientedSize(width: 1920, height: 1440, orientation: .right) == (1440, 1920))
    XCTAssertTrue(PoseService.orientedSize(width: 1280, height: 720, orientation: .up) == (1280, 720))
}
func test_mirrorCheck() {
    XCTAssertEqual(FrontFaceMirrorCheck.classify(visionNoseX: 0.42, projectedFaceX: 0.45), .matches)
    XCTAssertEqual(FrontFaceMirrorCheck.classify(visionNoseX: 0.30, projectedFaceX: 0.68), .mirrored)
    XCTAssertEqual(FrontFaceMirrorCheck.classify(visionNoseX: 0.50, projectedFaceX: 0.50), .unclear) // centred: can't tell
}
func test_frontFrames_keepTheirKeypoints() {
    // An InputFrame with default orientation and a 720×1280 buffer: keypoints(_:in:) is the identity, as today.
}
```

The centred case is `.unclear` because both readings agree within tolerance.

- [ ] **Step 2: Run `swift test --filter FrontFaceOrientationTests`.** Expected: compile failure (no `referenceUnits`).

- [ ] **Step 3: Implement**
  - Add the field and the three functions above.
  - In `PoseService.process`, build the handler with `VNImageRequestHandler(cvPixelBuffer:orientation: frame.visionOrientation, options: [:])`.
  - In `keypoints(_:in:)`:
    - `visionOrientation != .up`: map each point with `referenceUnits` on `orientedSize`.
    - Otherwise: keep the existing landscape path untouched.
  - In `ARFaceTrackingService`:
    - Set `visionOrientation: .right` on every `InputFrame`. This is our call: an unmirrored upright frame matching Front (2D)'s `isVideoMirrored = false`. The mirror check below verifies it.
    - Once per session, on the first frame where a face is tracked and Vision's nose has confidence ≥ 0.5, compute `frame.camera.projectPoint(faceAnchor.transform.columns.3.xyz, orientation: .portrait, viewportSize: orientedSize)` / size. Publish the `classify` result for the log (Task 4 writes it).
    - If the result is `.mirrored`, the fix is a one-line change to `.leftMirrored`, made after the session.

- [ ] **Step 4: Run the package tests.** Expected: all green, including the existing `LandscapeFrameTests`.

- [ ] **Step 5: Leave uncommitted** (Dave's word). Note the device check for Dave's session: in Front Face, the debug panel's side lean has the same sign as in Front (2D) when he leans left.

### Task 2: Face signal summary (pure)

**Files:**
- Create: `PostureLogic/Sources/PostureLogic/Engines/FaceSignals.swift`
- Test: `PostureLogic/Tests/PostureLogicTests/FaceSignalsTests.swift`

**Interfaces:**
- Produces:
  - `public struct FaceSample: Equatable, Sendable`:
    - `t: TimeInterval`
    - `tracked: Bool`
    - `eyeBlinkLeft: Float`
    - `eyeBlinkRight: Float`
    - `jawOpen: Float`
    - `distance: Float?` (metres)
  - `public struct FaceSignalSummary: Equatable, Sendable`:
    - `trackedShare: Float`
    - `eyesClosedShare: Float?` (nil when nothing was tracked)
    - `longBlinks: Int`
    - `longestClosureMs: Int?`
    - `yawns: Int`
    - `distanceLow`, `distanceMedian`, `distanceHigh: Float?`
  - `public enum FaceSignals { public static func summary(_ samples: [FaceSample], from: TimeInterval, to: TimeInterval) -> FaceSignalSummary? }`
    - Returns nil when no sample falls in [from, to].
    - Shares are weighted by each sample's duration: the time to the next sample, capped at 0.1 s.
    - A closure or yawn counts in the window where it **ends**. Its start may lie before `from`; the buffer holds 30 s.
    - A closure or yawn still open at `to` waits for the next window.

- [ ] **Step 1: Write the failing tests** (samples at 60 fps unless stated):
  - `test_openEyes_noClosure`: blink 0.1 for 10 s → share 0, longBlinks 0, longestClosureMs nil.
  - `test_narrowedEyes_notClosed`: blink 0.7 for 10 s → share 0. (Review Focus 1)
  - `test_shortBlink_countsInShare_notAsLong`: one 0.15 s closure → longBlinks 0, longestClosureMs 150 ± 17, share ≈ 0.015.
  - `test_longBlink_counted`: one 0.4 s closure → longBlinks 1, longestClosureMs 400 ± 17.
  - `test_unevenFrames_weighByTime`: closed for 1 s at 60 fps, then open for 9 s at 15 fps → share 0.1 ± 0.01. (Review Focus 2)
  - `test_faceLostMidBlink_discarded`: 0.2 s closed, 0.3 s untracked, then open → longBlinks 0, and the untracked time is excluded from the share. (Review Focus 3)
  - `test_oneEyeClosed_isNotClosed`: left 0.9, right 0.2 → share 0.
  - `test_yawn_heldTwoSeconds_countsOnce`: jaw 0.7 for 3 s → yawns 1. Jaw 0.7 for 1.5 s → 0.
  - `test_yawnInterruptedByLostFace_notCounted`.
  - `test_closureEnding_inNextWindow`: closure from 9.8 s to 10.3 s → window [0, 10] longBlinks 0; window [10, 20] longBlinks 1.
  - `test_distanceSpread`: distances 0.5, 0.6, 0.7 → low 0.5, median 0.6, high 0.7.
  - `test_noSamples_nil`.

- [ ] **Step 2: Run `swift test --filter FaceSignalsTests`.** Expected: compile failure.

- [ ] **Step 3: Implement `FaceSignals.summary`.** Medians use the upper middle of an even count, as the posture log's `spread()` does.

- [ ] **Step 4: Run the package tests.** Expected: green.

### Task 3: Sample faces at the ARKit rate

**Files:**
- Create: `PostureLogic/Sources/PostureLogic/Engines/FaceSampleBuffer.swift`
- Modify: `Quant/Services/ARFaceTrackingService.swift`
- Test: `PostureLogic/Tests/PostureLogicTests/FaceSampleBufferTests.swift`

**Interfaces:**
- Consumes: `FaceSample` and `FaceSignals.summary` (Task 2).
- Produces: `public final class FaceSampleBuffer: @unchecked Sendable`:
  - `init(keep: TimeInterval = 30)`
  - `func append(_ s: FaceSample)`: drops samples older than `keep` before the newest.
  - `func summary(from: TimeInterval, to: TimeInterval) -> FaceSignalSummary?`
  - `func clear()`
  - It's guarded by an `NSLock`. `ARFaceTrackingService.faceSamples: FaceSampleBuffer` is a `let`, and the service calls `clear()` on `start()`.

- [ ] **Step 1: Failing tests:**
  - `test_keepsOnlyThirtySeconds`: append 40 s at 10 fps → a summary from 0 to 9 is nil.
  - `test_summaryMatchesPureFunction`.
  - `test_concurrentAppendAndRead`: `DispatchQueue.concurrentPerform` with 1,000 appends and reads, with no crash under `swift test --sanitize=thread`.

- [ ] **Step 2: Run them.** Expected: fail.

- [ ] **Step 3: Implement the buffer.** In `session(_:didUpdate:)`, on every ARFrame, before anything else returns, append one `FaceSample`:
  - **Tracked face:** `blendShapes[.eyeBlinkLeft]`, `[.eyeBlinkRight]` and `[.jawOpen]` as `Float`, and `distance` = the existing `cameraSpaceHeadPosition` length.
  - **No tracked face:** `tracked: false` with zeros.
  - **Timestamp:** `FrameClock.shared.calendarSeconds(fromUptime: frame.timestamp)`, the same one the `InputFrame` uses.

- [ ] **Step 4: Run the package tests, then build the app scheme.** Expected: green, with no new warnings.

### Task 4: The posture log writes it

**Files:**
- Modify: `Quant/Models/PostureLog.swift` (`PostureLogEvent`, `metricsEvents`, `metricsLine`, `settingsEvents`)
- Modify: `Quant/AppModel.swift` (`logFrame`)
- Test: `QuantTests/PostureLogTirednessTests.swift` (new)

**Interfaces:**
- Consumes:
  - `FaceSignalSummary` (Task 2)
  - `ARFaceTrackingService.faceSamples` (Task 3)
  - the mirror-check result (Task 1)
- Produces, as new `PostureLogEvent` optional fields:
  - **Metrics:** `eyesClosedShare`, `longBlinks`, `longestClosureMs`, `yawns`, `faceTrackedShare`, `faceDistanceLow`, `faceDistanceMedian`, `faceDistanceHigh`, `movementMedian`, `sinceBreakMinutes`
  - **Settings:** `camera: String?`, holding the `CameraMode` raw value
  - **Camera line:** `mirrorCheck: String?`, written once per Front Face session in a `camera` line
- Signature changes:
  - `metricsEvents(…, face: (_ from: TimeInterval, _ to: TimeInterval) -> FaceSignalSummary? = { _, _ in nil }, …)` is called only when a line is built, over the window's first frame time to `now`.
  - `settingsEvents(_:build:camera:now:)`: a camera change also emits a new line.

- [ ] **Step 1: Failing tests:**
  - `test_frontFaceWindow_carriesFaceFields`: a stub summary flows into the line.
  - `test_front2DWindow_hasNoFaceFields`: the default closure; the encoded JSON contains no `eyesClosed`, `yawns` or `faceDistance`. (Review Focus 4)
  - `test_movementMedian`.
  - `test_sinceBreak_resetsAfterTwoMinutesAway_notAfterThirtySeconds`:
    - present 0–600 s → about 10 minutes
    - absent 60 s → still counting from 0
    - absent 130 s → counts from the return
    - With no break yet, it counts from the first judged frame.
  - `test_settingsLine_carriesCamera_andChangesWithIt`.

- [ ] **Step 2: Run them.** Expected: compile failure.

- [ ] **Step 3: Implement.**
  - `sinceBreakMinutes` lives in the recorder. It's fed by the `state` already passed to `metricsEvents`, including absent frames: check in `logFrame` that absent frames reach it. If they don't, pass the state on another existing call.
  - In `AppModel.logFrame`:
    - pass `face:` only when `cameraMode == .frontFace`, as `{ arFaceService.faceSamples.summary(from: $0, to: $1) }`
    - pass `camera: cameraMode.rawValue`

- [ ] **Step 4: Run the app tests, then the package tests.** Expected: green, with no new warnings in the touched files.

- [ ] **Step 5: Update the README counts** (line 91: package and app test counts, lines and files).

### Done when

- Both suites are green and warning-free, and the Watch tests are untouched.
- `git status` shows only this plan's files.
- Dave is told the device checks for his first Front Face session:
  - his `dist` reading
  - the side-lean sign when he leans left
  - the log's `mirrorCheck` line, which I read
- Commit and push wait for his word.
