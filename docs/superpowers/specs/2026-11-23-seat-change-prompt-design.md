# Seat-change prompt: design

Dave's design conversation, 2026-11-23. Approach A was his pick; the remaining details are marked "our call" where Claude proposed them and Dave agreed to the behaviour as a whole ("This looks good").

## Why

Aware judges posture against a calibration, which is a snapshot of how Dave sat when he calibrated. When he moves his seat, every reading shifts with it, so ordinary sitting reads as a slouch and nudges him wrongly.

Session 13 (2026-11-23) showed this:
- **11:34 to 11:43:** head drop kept dipping just past its line (window lows of −0.017 to −0.021, against a line of 0.01875) while its 10-second medians stayed between about −0.004 and −0.010. The state flicked between good and drifting about a dozen times without a nudge ever being reached. This is a run of near-misses, not a steady offset.
- **11:43:** Dave recalibrated by hand. In his words: "I had adjusted my seated position which meant slouching was getting triggered more frequently and inaccurately."
- The new calibration had his head 0.021 shoulder widths lower and his shoulders 8% wider.
- He had **not** left the camera's view: the log has no "away" before 11:43.
- After the recalibration, nothing came near a line for 35 minutes, and Dave confirms he sat well.

## What Dave wants

1. **On return.** When he comes back to the desk, Aware checks his settled sitting against the calibration.
   - Within a tolerable range: it keeps the calibration and stays silent. Dave's words: "dismisses automatically".
   - Outside it: it nudges him to answer **Recalibrate** or **Dismiss**.
2. **While present.** The same question is asked if he shifts without leaving and the slouch keeps near-missing on the same reading. This covers the 11:43 case. Dave picked **repeated near-misses** as this trigger (2026-11-23), matching what he felt: slouches "triggered more frequently". A steady offset in the medians was considered and dropped, because today's medians didn't show one.
3. **Log only first.** The first build runs the check silently and logs where it would have asked. Dave asked for a recommendation; Claude recommended this, and it is the plan unless Dave says otherwise. A setting switches it to asking, so going live needs no new build.

## Goals

- A seat change costs Dave one tap instead of a run of false nudges and a hand recalibration.
- No false slouch nudge arrives while the question is open.
- The test for "seat change" is checked against Dave's saved logs before it reaches his phone.

## Non-goals

- Recalibrating without asking. A steady offset can also be a slouch Dave has settled into, so the app asks; it never acts alone.
- Changing the slouch lines, the slouch timing or the nudge wording.
- The rear (depth) camera and Front Face modes. Front (2D) is what Dave uses. The check may run in the other modes if that comes free, but nothing is tuned for them.

## Anti-goals: this fails even if it works if…

- **It asks often when nothing moved.** A question every 20 minutes becomes noise, like the false nudges it replaces.
- **It hides real slouches.** If a real slump reads as "a new seat" and Dave taps Recalibrate, the slump becomes the reference. A slouch that comes and goes must not set off the question.
- **It recalibrates on a tap Dave didn't mean,** for example a stray tap on the Watch.

## Behaviour

### Tolerance: "within a tolerable range" (our call: half a line)

For each reading the slouch logic uses, the tolerance is half its line in the settings in force:

| Reading | Line (build 105) | Tolerance |
|---|---|---|
| Head drop | 0.01875 | 0.009 |
| Forward lean (shoulder width) | 0.06 | 0.03 |
| Side lean | 0.08 | 0.04 |
| Shoulder sink | 0.05 | 0.025 |

The tolerances are worked out from the live settings, not written in as constants, so they follow any change to a line. Twist and shoulder rounding are left out: twist in Front (2D) is really shoulder tilt, and neither moves with a seat change in the logs seen so far.

The half-line tolerance is used **only by the on-return check**, applied to 10-second medians: a reading is offset when its median is past the tolerance in at least 80% of the windows in the span. (Our call; the builder tunes it.)

**Only the slouch direction counts** (our call, from the builder check). After 11:43, forward lean's medians sat 0.03–0.047 on the upright side for stretches. Counting both directions would have asked then. A seat change that makes Dave read *better* doesn't cause false nudges.

### Trigger 1: on return

- **When:** Dave comes back after being away for at least `absentResumeThreshold` (30 s today). This is the same moment the pipeline already treats as a long absence (`PostureEngine`'s recalibration-prompt flag).
- **Span:** the first 20 s of judged frames after his return, ignoring the first 5 s while he settles. (Our call.)
- **Result:**
  - No reading offset: stay silent and keep the calibration. This is the auto-dismiss.
  - Any reading offset: ask the question.
- This replaces the existing "welcome back, tap to recalibrate" flag. That flag asks after every long absence and was never shown, so it would have asked far too often.

### Trigger 2: while present, repeated near-misses (Dave's pick)

- **What counts as a near-miss:** the state goes good → drifting because of a reading (`slouchSignals`) and comes back to good before the slouch is confirmed as bad, without that reading ever going far past its line. (Our call: its peak stays within 1.5× the line.)
- **When it asks:** 5 or more near-misses on the **same reading** within 5 minutes. (Our call; starting numbers, tuned from the log-only session.)
- A real slouch that keeps half-recovering can also set this off. That's accepted: the result is a question, never an automatic recalibration.
- **Not again straight away:** after Dismiss, it doesn't ask again until he next comes back from away.

### While the question is open

- **Slouch nudges are held.** The question is itself the nudge, and a slouch nudge on top would be the false one. (Our call: hold every nudge, head turn included, through the nudge engine's existing `silenced` input. The builder may narrow this to slouch nudges if head turn turns out to be unaffected by calibration.)
- **Timeout:** with no answer after 2 minutes, the question closes as if dismissed and nudging resumes. (Our call.)
- **Slouch time built up while the question is open is thrown away** on any outcome. `NudgeEngine` keeps adding slouched time while `silenced` and nudges straight away when the silence ends, so without this a Dismiss would be followed by the false nudge. (Our call, from the builder check.)
- **Recalibrate:** runs the existing recalibration (`AppModel.recalibrate()`, the 5-second capture) and closes the question.
- **Dismiss:** keeps the calibration, closes the question, and holds off as described under trigger 2.
- **Dave leaves while it's open:** the question closes. The return check runs again when he's back.

### How Dave sees and answers it

- **Delivery:** Dave's words: "nudged to answer or dismiss".
  - **Phone:** a new in-app prompt. The phone has no nudge banner today (a phone nudge is a sound), but the camera only runs with Aware open, so an in-app prompt is always on screen when this can happen. There's no new notification permission. (Our call.)
  - **Watch:** a buzz and a notification with a new category carrying **Recalibrate** and **Dismiss** actions. The Watch's nudge notification has no buttons today.
- **Wording (our call):** "Moved your seat?", with buttons **Recalibrate** and **Dismiss**.
- **Recalibrate on the Watch:** works only if the phone can see him to recalibrate, because calibration needs the camera. The Watch already has a recalibration request path (`WatchConnectivityService`), which this reuses.
- **Stray taps:** a Watch answer needs a deliberate button tap, never a tap on the notification itself.

### Logging

Every question is logged, along with which trigger raised it, the offsets that raised it, and how it ended (recalibrate, dismiss, timeout or away). That lets a later review count how often it asked and whether Dave agreed.

The `metrics` line also gains **side lean and shoulder sink medians** (it has only their highs today), so the replay can test every reading in the table, not just head drop and forward lean.

## Approaches considered

- **A. In the posture package, next to the slouch logic. Chosen by Dave.** A seat-change check replaces the dormant `StaleBaselineDetector`, which compares shoulder width against a 30% change plus a one-hour age, and whose result nothing reads. The pipeline publishes whether a question is open, the nudge engine holds while it is, and the app adds the prompt. It is chosen because the check can replay Dave's saved logs and be tuned before anything reaches his phone, and because the slouch timing already lives and is tested there.
- **B. In the app only.** Quicker to write, but holding nudges would mean working around the nudge engine, and nothing could be replayed. The first real test would be Dave at his desk.
- **C. Retune the existing detector from 30% to about 3%.** Cheapest, but it only sees shoulder width. It would miss today's case, a head-height shift, and it has no idea of "steady".

## Constraints

- **One clock:** use frame time, seconds since 1970 (`FrameClock`). The dormant detector measures the calibration's age with `Date()`; the replacement must not.
- **Front 2D's quirks:** keypoints have y running down, and head drop is **negative** when the head drops.
- **Tests:** the package tests (`swift test`) and the app tests (`QuantNoWatchTests`, with `-parallel-testing-enabled NO`) must stay green and warning-free. New logic is written test-first.
- **No new compiler warnings.** `a7d1927` left 2 in `PoseOverlayView.swift`; that fix is separate work, but this work must not add more.
- **Commit and push only on Dave's word.**

## Rollout: log only, then asking

- **A setting with three positions: Off, Log only, Ask.** The first build ships with **Log only**. Nothing is shown and nudges behave as today, but the posture log writes a `seat` line wherever the check would have asked, including the trigger, the reading, the count, and the medians.
- **After one session** (ideally an hour, with Dave noting roughly when he moved), Claude reads the log:
  - Does it fire where he moved?
  - Does it fire where he didn't?
  - How often? The aim is under once an hour.
- The numbers are adjusted if needed. Then Dave switches the setting to **Ask**; no new build is needed unless the numbers change.

## Acceptance before the log-only build ships

1. **2026-11-23, 11:34–11:43, replayed from the state lines:** the near-miss check asks before 11:43:29, when Dave recalibrated by hand. With 5 in 5 minutes it would ask at 11:42:26: the head-drop near-misses were at 11:40:35, 11:40:46, 11:40:58, 11:42:10 and 11:42:26, with two more at 11:34 that fall outside the window. The state lines carry every good↔drifting change, so this is replayable even though the medians aren't steady.
2. **2026-11-23, after 11:43:** it stays silent for the remaining 35 minutes.
3. **Synthetic:** a slouch held past the line until it turns bad never asks. Dropping the head once a minute, without any near-misses in a row, never asks.
4. **Frequency on older sessions:** the state lines go back to 10-08, so near-misses can be counted on the 11-16 to 11-19 sessions. Report the count per hour to Dave with the log-only build. That's a report, not a gate, because those sessions had real slouches too.

The on-return check can only be replayed on 11-21 and 11-23, the logs with `metrics` lines. It is judged mainly from the log-only session.

## Left to the builder

- The near-miss numbers (5 in 5 minutes, 1.5× the line) and the on-return 80% rule, within the acceptance checks.
- Where the check sits in the package and what it is called. `StaleBaselineDetector` goes.
- The banner's look on the phone, following the existing nudge banner.
- The Watch message format, using the existing recalibration request.
- Whether the question also shows on the Calm screen, beyond the banner.
