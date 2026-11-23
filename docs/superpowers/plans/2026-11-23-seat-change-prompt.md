# Seat-change Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aware notices a probable seat change, either from repeated near-miss slouches or from an offset found just after Dave returns from away, and asks "Moved your seat?" (Recalibrate / Dismiss). The first build only logs where it would have asked.

**Architecture:** A pure `SeatChangeDetector` in PostureLogic watches each judged frame's state, slouch signals and metrics, and returns a suggestion. `Pipeline` owns the mode (off / log only / ask), the open question, its 2-minute timeout, holding nudges while it's open, and throwing away slouch time when it closes. The app persists the mode, logs `seat` lines, shows an in-app prompt, and relays the question to the Watch, which answers through notification actions.

**Tech Stack:** Swift 6, SwiftUI, Combine, XCTest, WatchConnectivity, UserNotifications.

**Spec:** `docs/superpowers/specs/2026-11-23-seat-change-prompt-design.md`

## Global Constraints

- **Clock:** frame time only, seconds since 1970 (`FrameClock`). No `Date()` in the detector or the pipeline logic; `ClockConventionTests` enforces this.
- **Signs:** head drop is **negative** when the head drops; shoulder sink is **positive** when lower; forward creep is **positive** when closer. Side lean uses `lateralLean`, which is a magnitude.
- **Only the slouch direction counts:** `headDrop < −x`, `forwardCreep > x`, `shoulderSink > x`, `lateralLean > x`.
- **Tolerance:** half of each line, read from the live `PostureThresholds` (`headDropThreshold`, `forwardCreepThreshold`, `sideLeanThreshold`, `shoulderSinkThreshold`). Never hard-coded.
- **Near-miss:** the state goes drifting → good with no `.bad` in between, and the reading's peak in the slouch direction stays ≤ 1.5× its line. The question is raised at **5 near-misses on the same reading within 300 s**.
- **On return:** after an absence of at least `absentResumeThreshold`, ignore the first 5 s. Take the median of each reading over 5–15 s and over 15–25 s. The reading is offset when both medians are past the tolerance.
- **Question timeout:** 120 s of frame time.
- **Mode values:** `off`, `logOnly`, `ask`. The default is **`logOnly`**.
- **Copy:** the title is "Moved your seat?"; the buttons are "Recalibrate" and "Dismiss".
- **Tests:** package `cd PostureLogic && swift test`. App: `xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests -destination 'id=8E04449A-94EF-4F79-BFCE-71FD480E718C' -parallel-testing-enabled NO`. Run it in the background and `pkill` it after "** TEST" appears. Both must be green with **no new warnings**.
- **Commits:** commit at each task's end **only if Dave has said to commit**. Otherwise leave the work uncommitted and say so. Never push without his word.

## Review Focus

1. **Recalibrating while the question is open.** The question must close, and the detector must reset to its after-return quiet. It must not ask again on the first frames against the new baseline. → Task 2, `test_recalibrating_closesQuestion_andResetsDetector`.
2. **Mode changed from Ask to Log only or Off while a question is open.** The question closes and nudges resume. → Task 2, `test_switchingModeOff_closesOpenQuestion`.
3. **A real slouch held until it turns bad.** No near-miss is counted at any point, and it never asks. → Task 1, `test_slouchThatTurnsBad_isNotANearMiss`.
4. **Calibrating, or no baseline.** The detector ignores frames, and a return while calibrating never asks. → Task 1, `test_noJudging_whileCalibrating`.
5. **A Watch answer arriving after the question closed** (timeout, or answered on the phone). It is ignored and never recalibrates. → Task 5, `test_lateWatchAnswer_isIgnored`.

---

### Task 1: SeatChangeDetector

**Files:**
- Create: `PostureLogic/Sources/PostureLogic/Engines/SeatChangeDetector.swift`
- Test: `PostureLogic/Tests/PostureLogicTests/SeatChangeDetectorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SeatChangeTrigger: Equatable, Sendable {
      case nearMisses(reason: NudgeReason, count: Int)   // reason ∈ headDrop, forwardCreep, sideLean, sink
      case onReturn(reasons: Set<NudgeReason>)
  }
  public struct SeatChangeSuggestion: Equatable, Sendable { public let trigger: SeatChangeTrigger; public let at: TimeInterval }
  struct SeatChangeDetector {
      init()
      /// One judged frame. Returns a suggestion at most once until `reset()` or the next return.
      mutating func observe(state: PostureState, signals: Set<NudgeReason>, metrics: RawMetrics?,
                            thresholds: PostureThresholds, at t: TimeInterval) -> SeatChangeSuggestion?
      /// After Recalibrate, Dismiss, timeout or away: forget near-misses, stay quiet until the next return.
      mutating func quietUntilNextReturn()
      mutating func reset()   // new baseline: forget everything, not quiet
      mutating func forgetNearMisses()   // log-only: start the count again, stay listening
  }
  ```

- [ ] **Step 1: Write the failing tests.** Use a helper `frame(_ state:, signals:, headDrop:, creep:, sink:, lean:, t:)` with thresholds at the defaults (`headDrop` 0.01875).
  - `test_fiveHeadDropNearMisses_inFiveMinutes_suggest`: 5 episodes of `.drifting` with signals `[.headDrop]` and headDrop −0.02, each followed by `.good`, 40 s apart. The 5th return to good yields `.nearMisses(reason: .headDrop, count: 5)`.
  - `test_fourNearMisses_doNotSuggest`.
  - `test_nearMissesSpreadOver301s_doNotSuggest`: 5 episodes, the first and the 5th 301 s apart.
  - `test_deepPeak_isNotANearMiss`: an episode whose headDrop reaches −0.03 (more than 1.5 × 0.01875 = 0.028125) doesn't count.
  - `test_slouchThatTurnsBad_isNotANearMiss`: drifting → bad → good, five times, gives nil.
  - `test_mixedReasons_countSeparately`: 3 headDrop and 2 forwardCreep near-misses give nil.
  - `test_suggestsOnce_thenQuietUntilNextReturn`: after a suggestion, 5 more near-misses give nil. After `quietUntilNextReturn()` and then an absence of ≥ 30 s and a return, near-misses count again.
  - `test_returnWithHeadOffset_suggestsOnReturn`: `.absent` for 31 s, then `.good` frames at 10 fps with headDrop −0.012 (past the 0.009375 tolerance) from 0 to 25 s. Gives `.onReturn(reasons: [.headDrop])` at t = return + 25.
  - `test_returnWithinTolerance_staysSilent`: the same with headDrop −0.005 gives nil.
  - `test_returnOffsetOnlyInSecondWindow_staysSilent`: −0.012 only from 15 to 25 s gives nil.
  - `test_uprightOffset_neverCounts`: on return, forwardCreep −0.05 and headDrop +0.02 give nil.
  - `test_shortAbsence_noReturnCheck`: an absence of 10 s, then an offset, gives nil.
  - `test_noJudging_whileCalibrating`: `.calibrating` frames and a return into `.calibrating` give nil.
  - `test_tolerances_followThresholds`: with `headDropThreshold` 0.04, headDrop −0.012 on return gives nil.

- [ ] **Step 2: Run them and see them fail.**
  Run `cd PostureLogic && swift test --filter SeatChangeDetectorTests`. Expected: compile failure, because `SeatChangeDetector` isn't defined.

- [ ] **Step 3: Implement `SeatChangeDetector`.**
  - Track the open drift episode as its reasons plus the peak per reason in the slouch direction. Close it on `.good` (a near-miss for each reason whose peak ≤ 1.5 × its line), or discard it on `.bad` or `.absent`.
  - Keep near-miss times per reason and drop those older than 300 s.
  - Track when `.absent` started. On the first non-absent, non-calibrating frame after an absence of ≥ `absentResumeThreshold`, start collecting frames from return + 5 s to return + 25 s, then judge the two 10-second medians.
  - Use a private `func slouchAmount(_ reason: NudgeReason, _ m: RawMetrics) -> Float` (positive = the slouch direction) and `func line(_ reason:, _ thresholds:) -> Float`.

- [ ] **Step 4: Run them and see them pass.** Same command. Expected: all pass.

- [ ] **Step 5: Commit, if Dave has said to.** `git add` both files, then `git commit -m "feat: a seat-change check that counts near-miss slouches and checks the sitting after a return"`.

---

### Task 2: Pipeline: mode, the open question, holding and forgetting

**Files:**
- Modify: `PostureLogic/Sources/PostureLogic/Pipeline.swift`. Wire this into `ingest` after `postureState` is set and before `nudgeEngine.evaluate`, and also into `judgeWithoutPose` so that away closes the question.
- Modify: `PostureLogic/Sources/PostureLogic/Engines/NudgeEngine.swift`. Add `func forgetSlouch()`.
- Delete: `PostureLogic/Sources/PostureLogic/Services/StaleBaselineDetector.swift`, `PostureLogic/Tests/PostureLogicTests/StaleBaselineDetectorTests.swift`, `Pipeline.baselineStaleness` and its 60 s check, `Pipeline.showRecalibrationPrompt` and `dismissRecalibrationPrompt()`, and `PostureEngine.pendingRecalibrationPrompt` and `consumeRecalibrationPrompt()`. Update the assertions in `PostureEngineAbsenceTests`, `PipelineTimelineTests`, `PipelineIntegrationTests` and `QuantTests/QuantTests.swift` that read them: delete those assertions only, and keep the tests' other checks.
- Test: `PostureLogic/Tests/PostureLogicTests/PipelineSeatChangeTests.swift`

**Interfaces:**
- Consumes: Task 1's `SeatChangeDetector`, `SeatChangeSuggestion`, `SeatChangeTrigger`.
- Produces:
  ```swift
  public enum SeatChangeMode: String, Codable, CaseIterable, Sendable { case off, logOnly, ask }
  public enum SeatChangeOutcome: String, Sendable { case recalibrate, dismiss, timeout, away, modeChanged }
  public struct SeatChangeQuestion: Equatable, Sendable { public let suggestion: SeatChangeSuggestion }
  // Pipeline
  public var seatChangeMode: SeatChangeMode            // default .logOnly; setting it to non-.ask closes an open question (.modeChanged)
  @Published public private(set) var seatChangeSuggestion: SeatChangeSuggestion?   // every suggestion, in any mode except .off
  @Published public private(set) var seatChangeQuestion: SeatChangeQuestion?        // open only in .ask
  @Published public private(set) var seatChangeClosed: SeatChangeOutcome?           // set each time a question closes
  public func answerSeatChange(_ outcome: SeatChangeOutcome)  // .recalibrate or .dismiss; ignored if none open
  // NudgeEngine
  func forgetSlouch()   // slouchedTime = 0, goodStreak = 0, nudgeDueIn = nil
  ```
  When `baseline` changes (a recalibration), the pipeline calls `detector.reset()` and closes any open question with `.recalibrate`.
  In `.logOnly` nothing is held and the detector does **not** go quiet. After each suggestion it forgets its near-misses (add `mutating func forgetNearMisses()` to Task 1's interface and test it in `test_forgetNearMisses_startsCountAgain`) and keeps counting. The log then shows every burst, which is the raw count the log-only session exists to measure.

- [ ] **Step 1: Write the failing tests** in `PipelineSeatChangeTests`. Drive the pipeline through `ingest` with injected samples and metrics, following the existing `PipelineTimelineTests` helpers.
  - `test_logOnly_publishesSuggestion_butNoQuestion_andNudgesUnchanged`: five head-drop near-misses. `seatChangeSuggestion` is non-nil, `seatChangeQuestion` is nil, and a following sustained slouch still fires at the usual time.
  - `test_ask_opensQuestion_andHoldsNudges`: in `.ask`, after the suggestion, a 90 s slouch gives `nudgeDecision` that is never `.fire`.
  - `test_question_timesOutAfter120s`: `seatChangeClosed == .timeout` at suggestion + 120 s, and not before.
  - `test_closing_forgetsSlouchTime`: a 90 s slouch while the question is open, then `.dismiss`. No fire within the next `slouchDurationBeforeNudge − 1` s of slouch.
  - `test_away_closesQuestion`.
  - `test_recalibrating_closesQuestion_andResetsDetector`: setting `baseline` closes it with `.recalibrate`, and the next frames don't suggest.
  - `test_switchingModeOff_closesOpenQuestion`: `.modeChanged`, and the nudges are no longer held.
  - `test_off_neverSuggests`.
  - `test_answer_withNoOpenQuestion_isIgnored`.

- [ ] **Step 2: Run them and see them fail.**
  Run `cd PostureLogic && swift test --filter PipelineSeatChangeTests`. Expected: compile failure, because `seatChangeMode` isn't defined.

- [ ] **Step 3: Implement.** Pass `silenced: nudgesSilenced || seatChangeQuestion != nil` to `evaluate`. Every close path sets `seatChangeClosed`, calls `nudgeEngine.forgetSlouch()` and `detector.quietUntilNextReturn()`, except recalibrate, which calls `detector.reset()`. Then delete the dormant pieces listed under Files.

- [ ] **Step 4: Run the whole package and see it pass.**
  Run `cd PostureLogic && swift test`. Expected: all pass, with the removed staleness tests gone, and no warnings.

- [ ] **Step 5: Commit, if Dave has said to.**
  `git commit -m "feat: the pipeline asks about a seat change, holds nudges while it asks, and drops the dormant stale-baseline checks"`.

---

### Task 3: The posture log: seat lines and the missing medians

**Files:**
- Modify: `Quant/Models/PostureLog.swift`
  - `PostureLogEvent` gains `trigger: String?`, `reason: String?`, `count: Int?`, `sideLeanMedian: Float?` and `shoulderSinkMedian: Float?`.
  - `metricsLine` fills the two medians using the same `spread` helper.
  - Add `static func seatEvent(...)`.
- Modify: `Quant/AppModel.swift`. Subscribe to `pipeline.$seatChangeSuggestion` and `pipeline.$seatChangeClosed`, and append their events.
- Test: `QuantTests/PostureLogSeatTests.swift`

**Interfaces:**
- Consumes: Task 2's `seatChangeSuggestion`, `seatChangeClosed` and `seatChangeMode`.
- Produces: log lines (frame time `t`).
  - `{"kind":"seat","value":"would-ask"|"asked","trigger":"nearMisses"|"onReturn","reason":"headDrop" or a comma list,"count":5}`. The value is `"would-ask"` in `.logOnly` and `"asked"` in `.ask`.
  - `{"kind":"seat","value":"closed:<outcome>"}`.
  ```swift
  static func seatEvent(_ suggestion: SeatChangeSuggestion, mode: SeatChangeMode) -> PostureLogEvent
  static func seatEvent(closed: SeatChangeOutcome, at t: TimeInterval) -> PostureLogEvent
  ```

- [ ] **Step 1: Write the failing tests.**
  - `test_nearMissSuggestion_inLogOnly_writesWouldAsk`: value `"would-ask"`, trigger `"nearMisses"`, reason `"headDrop"`, count 5, `t` equals the suggestion's `at`.
  - `test_onReturnSuggestion_listsReasonsSorted`: `[.sink, .headDrop]` gives `"headDrop,sink"`.
  - `test_closedLine`: `"closed:timeout"`.
  - `test_metricsLine_hasSideLeanAndSinkMedians`: follow `PostureLogTuningTests`' metrics helper. Lean values 0.01, 0.02, 0.03 give a median of 0.02.

- [ ] **Step 2: Run them and see them fail.**
  Run the app tests command with `-only-testing:QuantTests/PostureLogSeatTests`. Expected: compile failure.

- [ ] **Step 3: Implement** the fields, the two `seatEvent` builders and the `AppModel` subscriptions.

- [ ] **Step 4: Run the app tests and see them pass.** Run the full app command. Expected: "** TEST SUCCEEDED **", with no new warnings.

- [ ] **Step 5: Commit, if Dave has said to.** `git commit -m "feat: the posture log writes where the seat question would ask, and side lean and sink medians"`.

---

### Task 4: The setting and the phone prompt

**Files:**
- Modify: `Quant/AppModel.swift`
  - `@Published var seatChangeMode: SeatChangeMode`, persisted under `Keys.seatChangeMode` (raw value, default `.logOnly`) in the same way as `maxNudgesPerHour`, and pushed to `pipeline.seatChangeMode` on set and at launch.
  - `@Published private(set) var seatChangeQuestion: SeatChangeQuestion?`, mirrored from the pipeline.
  - `func answerSeatChange(_ outcome: SeatChangeOutcome)`: `.recalibrate` calls `recalibrate()`, which sets the baseline nil and so closes the question through Task 2. `.dismiss` calls `pipeline.answerSeatChange(.dismiss)`.
- Create: `Quant/Views/SeatChangePrompt.swift`: a card with the title "Moved your seat?" and two buttons, "Recalibrate" and "Dismiss".
- Modify: `Quant/ContentView.swift` and `Quant/Views/CalmScreen.swift`. Overlay `SeatChangePrompt` at the top while `appModel.seatChangeQuestion != nil`, on both the debug and Calm screens.
- Modify: `Quant/Views/CalibrationSettingsView.swift`. Add a "Seat-change question" picker with "Off", "Log only" and "Ask".
- Test: `QuantTests/SeatChangeSettingTests.swift`

**Interfaces:**
- Consumes: Task 2's `SeatChangeMode`, `SeatChangeQuestion`, `answerSeatChange` and `seatChangeMode`.
- Produces: `AppModel.seatChangeMode`, `AppModel.seatChangeQuestion` and `AppModel.answerSeatChange(_:)`, which Task 5 uses.

- [ ] **Step 1: Write the failing tests.**
  - `test_defaultMode_isLogOnly`: with no stored key.
  - `test_mode_persists_andReachesPipeline`: set `.ask`, then a fresh `AppModel` reads `.ask` and `pipeline.seatChangeMode == .ask`.
  - `test_dismiss_closesPipelineQuestion`: drive the pipeline to an open question in `.ask`, call `answerSeatChange(.dismiss)`, and check `pipeline.seatChangeClosed == .dismiss`.
  - `test_recalibrate_startsCalibration`: `needsCalibration == true`, and the question is closed with `.recalibrate`.

- [ ] **Step 2: Run them and see them fail.** Use `-only-testing:QuantTests/SeatChangeSettingTests`.

- [ ] **Step 3: Implement** the model, the view, the overlays and the picker.

- [ ] **Step 4: Run the full app tests and see them pass.**

- [ ] **Step 5: Commit, if Dave has said to.** `git commit -m "feat: a setting for the seat question (log only by default) and its prompt on the phone"`.

---

### Task 5: The Watch: the question with Recalibrate and Dismiss

**Files:**
- Modify: `Quant/Services/WatchConnectivityService.swift`
  - Add `static func seatQuestionMessage(open: Bool, id: TimeInterval) -> [String: Any]`, which gives `["type": "seatQuestion", "open": open, "id": id]`, where `id` is the suggestion's `at`.
  - Add a `func sendSeatQuestion(open:id:)` that uses `sendMessage`, the same way as `cameraPreviewMessage`.
  - Handle the incoming `"seatAnswer"` (`"answer": "recalibrate"|"dismiss"`, `"id"`) through a new `onSeatAnswer: ((SeatChangeOutcome, TimeInterval) -> Void)?`.
- Modify: `Quant/AppModel.swift`
  - Send open and closed as `seatChangeQuestion` changes.
  - Wire up `onSeatAnswer`. It calls `answerSeatChange` **only if** `id` matches the open question's `suggestion.at`; otherwise it ignores the answer.
- Modify: `QuantWatch Watch App/WatchSessionDelegate.swift`
  - Register a `UNNotificationCategory` with the identifier `"seatChange"` and the actions `"recalibrate"` ("Recalibrate") and `"dismiss"` ("Dismiss"), neither of them `.foreground`.
  - On `seatQuestion` open, play the nudge haptic and post a notification ("Moved your seat?", the category `"seatChange"`, `userInfo["id"]`). On close, remove it.
  - In `userNotificationCenter(_:didReceive:)`, map the action identifiers to `seatAnswer` messages. The default tap action sends nothing.
- Modify: `QuantWatch Watch App/NudgeMessage.swift`. Add `static func seatQuestionContent(id: TimeInterval) -> UNMutableNotificationContent`.
- Test: `QuantTests/SeatChangeWatchTests.swift` (the phone side), plus `QuantWatch Watch AppTests/SeatQuestionWatchTests.swift`.

**Interfaces:**
- Consumes: Task 4's `AppModel.answerSeatChange(_:)` and `seatChangeQuestion`.

- [ ] **Step 1: Write the failing tests.**
  - Phone: `test_seatQuestionMessage_shape`.
  - Phone: `test_watchAnswer_matchingId_dismisses`.
  - Phone: `test_lateWatchAnswer_isIgnored`. An answer whose `id` doesn't match, or that arrives with no question open, leaves `needsCalibration` unchanged and calls nothing.
  - Watch: `test_seatQuestionContent_hasCategoryAndTitle`: the category `"seatChange"`, the title "Moved your seat?" and `userInfo["id"]`.
  - Watch: `test_actionIdentifiers_mapToAnswers`: `"recalibrate"` gives `"recalibrate"`, `"dismiss"` gives `"dismiss"`, and `UNNotificationDefaultActionIdentifier` gives nil.

- [ ] **Step 2: Run them and see them fail.**
  - The phone tests run with `-only-testing:QuantTests/SeatChangeWatchTests`.
  - The Watch tests run with `xcodebuild test -project Quant.xcodeproj -scheme "QuantWatch Watch App" -destination 'platform=watchOS Simulator,name=<an available Apple Watch>' -only-testing:"QuantWatch Watch AppTests/SeatQuestionWatchTests"`.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run the full phone and Watch suites and see them pass,** with no new warnings.

- [ ] **Step 5: Commit, if Dave has said to.** `git commit -m "feat: the seat question on the Watch, answered with Recalibrate or Dismiss"`.

---

### Task 6: Replay acceptance and the frequency report

**Files:**
- Create: `PostureLogic/Tests/PostureLogicTests/SeatChangeReplayTests.swift`
- Create: `PostureLogic/Tests/PostureLogicTests/Fixtures/SeatChange20261123.swift`. This holds a Swift array literal of the `state` and `nudge` lines from `~/Documents/Claude/jev-sessions/posture-log-to-2026-11-23.jsonl` between 11:26:45 and 12:18:53: `t`, `value`, `headDrop`, `forwardCreep`, `shoulderSink`, `lateralShift`. Generate it with a one-off script and commit only the literal.
- Modify: `README.md`, to update the test counts.

**Interfaces:**
- Consumes: Task 1's `SeatChangeDetector`.
- Replay rule: rebuild frames from the state lines. A drifting frame's signals are the reason of the next `pending:<reason>` nudge line at the same `t` (± 0.5 s). Its metrics are the line's values, with `lateralShift` standing in for `lateralLean` (`abs`). Thresholds are the build-105 settings line (head drop 0.01875).

- [ ] **Step 1: Write the tests.**
  - `test_nov23_asksBeforeDaveRecalibrated`: the first suggestion is `.nearMisses(reason: .headDrop, count: 5)` with `at` within [11:42:20, 11:43:29). That's expected at 11:42:26, because the near-misses were at 11:40:35, 11:40:46, 11:40:58, 11:42:10 and 11:42:26.
  - `test_nov23_silentAfterRecalibration`: after calling `reset()` at 11:43:37, no suggestion through 12:18:53.
  - `test_frequencyReport_olderSessions`: runs only when the env var `SEAT_REPLAY_LOG` names a JSONL file, otherwise `XCTSkip`. It prints the suggestions per session (gaps over 600 s split sessions) and per hour. It asserts nothing.

- [ ] **Step 2: Run them.**
  Run `cd PostureLogic && swift test --filter SeatChangeReplayTests`. Expected: the first two pass and the third is skipped.
  - If `test_nov23_asksBeforeDaveRecalibrated` fails, adjust only within the spec's "left to the builder" numbers, then rerun all of Task 1's tests.

- [ ] **Step 3: Produce the report.**
  Run `SEAT_REPLAY_LOG=~/Documents/Claude/jev-sessions/posture-log-to-2026-11-23.jsonl swift test --filter test_frequencyReport_olderSessions`. Copy the per-session counts for 11-16 to 11-19 into the hand-back to Dave.

- [ ] **Step 4: Run both full suites, then update the README counts** (Swift lines and files, package tests, app tests and Watch tests).

- [ ] **Step 5: Commit, if Dave has said to.** `git commit -m "test: the seat question replayed on 11-23 asks at 11:42 and is silent after the recalibration"`.
