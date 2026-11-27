# Tiredness signals in Front Face mode: design (short)

Dave's conversation, 2026-11-26/27. Dave's decisions are marked as his; the rest are "our call".

## Why

Dave wants **a warning before his focus drops**. His dips feel like **yawning and getting sluggish**, which is sleepiness, the state driving-fatigue research measures. In that research the best early camera signs are:

- yawning
- the share of time the eyes are mostly closed (PERCLOS: at least 80% closed, over a minute or more)
- long, slow blinks (over about 300 ms)

Time on task and restlessness are general signs of fading attention, and Aware already knows both.

## Decisions

- **Combine signals rather than relying on blinks alone** (Dave: "Go with your recommendation"). The signals are time since the last break, the movement trend, yawns and eye closure.
- **Use Front Face mode, the TrueDepth face tracking, instead of Front (2D)** (Dave picked B: "if that means I will ultimately get more finegrained measurements"). It gives eye-closure and jaw-opening readings at 60 fps, plus metric head pitch and head-to-camera distance. Those last two also help the looking-down and craning problem.
- **Log only first,** as with the head and seat work. Nothing warns Dave until a session with his notes shows which signal rises first and how far ahead of the dip.
- **Order:** Dave's head and seat session on the current Front (2D) build comes first, so its log stays clean. This build comes after it.

## Approaches considered

- **A. Stay in Front (2D) and add Vision face landmarks.** It keeps the setup and tuning. Yawns would be reliable, but eye closure is doubtful: the eyes are small in a 720p frame, and 30 fps only just times a long blink.
- **B. Front Face mode. Chosen by Dave.** It gives finer eye, mouth and head readings. The costs are below.

## Costs of B, and how each is handled

1. **The body points are probably read sideways.** ARKit hands Vision its sensor-landscape frame with no orientation (`PoseService.swift:60`). A macOS Vision test during the landscape work (11-11) confirmed that Vision returns rotated points for a sideways person. Shoulders and ears feed head drop, side lean, shoulder sink and head size. **This is fixed first**, test-first: pass the frame's orientation (and front-camera mirroring) to Vision in Front Face mode, and check that keypoints come out upright.
2. **The posture lines were tuned in Front (2D).** The lines stay unchanged in this build. The first Front Face session is compared against Front (2D) sessions before anything is retuned.
3. **Upright only.** Landscape was built for Front (2D) only. Dave's recent logs are portrait (calibration lines), so nothing is lost today. Landscape in Front Face is out of scope.
4. **Battery and heat** at 60 fps with depth. Dave keeps the phone on a charger. The log records frame rate, so throttling would show up.
5. **The face must be visible.** When the face is lost (looking steeply down, turning away, glare), head angles already fall back to 2D after a grace window. Eye and mouth readings are simply missing for those frames, never counted as closed.
6. **Distance.** This is fine to about 1 m. The debug panel's `dist` row lets Dave check his seat before the session.

## What the build logs (log only)

- **The `settings` line gains the camera mode.** Logs don't record it today: Dave's mode was inferred from 30 fps timestamps.
- **The 10-second `metrics` line gains, in Front Face only:**
  - **Eye closure:** the share of frames with both eyes at least 80% closed (ARKit `eyeBlinkLeft`/`Right`). Our call; the builder may average both eyes.
  - **Long blinks:** the count of closures lasting 300 ms or more, and the longest closure in ms.
  - **Yawns:** the count of jaw openings (ARKit `jawOpen`) past a wide threshold, held 2 s or more. The builder sets the threshold from a quick capture; our call.
  - **ARKit head pitch and head distance** (low, median and high), next to the 2D head pitch and size from `3dfc8d6`.
- **In every mode:**
  - **Time since the last break.** A break is an absence of at least 2 minutes. Our call: longer than the 30 s that counts as "away".
  - **The movement median** for the window.

## Goals

- **One session in Front Face** with Dave's notes (yawning, feeling sluggish, looking down, craning, moving his seat). It answers whether the posture readings are sane, and which tiredness signal rises first and by how many minutes.
- **No change** to nudges or posture lines in Front (2D).

## Anti-goals

- **It warns during a long stretch of looking down at the keyboard.** Narrowed eyes when looking down must not read as closing. This is checked in the session; ARKit head pitch is logged alongside to tell them apart.
- **It breaks Front (2D) or its logs.** The new fields are present only when there's data, and the existing tests stay green.

## Left to the builder

- The jaw and eye thresholds, within the above.
- Where the blink and yawn counting lives. Our call: a pure, frame-clocked type in PostureLogic, tested like `SeatChangeDetector`.
- How blendshape values travel from `ARFaceTrackingService` to the pipeline. The current pattern is optional fields on `InputFrame` (`externalHeadAngles`).

## After this

There will be a later design for the warning itself: the line, the wording (for example "Getting sleepy. Time for a 2-minute walk?") and the Watch buzz. It will be set from what the session shows.
