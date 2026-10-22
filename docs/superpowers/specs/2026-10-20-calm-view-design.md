# Calm view: a glanceable main screen beside the debug one

_2026-10-20. Goal set by Dave: "design a perfect UI for this app. Think like an expert visual and
interaction designer. I'm still fine-tuning the measurements so need the debug mode primarily
visible but want this view as something I can switch to."_

## Intent

The debug screen (camera feed, diagnostics panel, cards, five icons) is for tuning, and stays
the default. The calm view is the screen Aware would ship with: what you see when you glance at
the phone propped up in front of you while you work.

## The moment it serves

The phone stands on the desk below the main screen, 50–80 cm away, front camera on you, screen
on for an hour or more. The Watch delivers the nudges. The phone's screen is in your peripheral
vision the whole time and is looked at directly only now and then, to answer:

1. Am I sitting well? (the posture, in a word and a shape)
2. Is it actually watching me? (live, paused, cooling down)
3. How long until it buzzes me? (the nudge countdown, only while one is coming)
4. How am I doing today? (the day's timeline and one summary line)

## Design decisions (Claude's calls; Dave rejected the column, approved the drawn figure with one change, to use his 3D model)

- **Your own 3D model** (2026-10-22, Dave: "use the 3d model i created and manipulate it to
  show the different posture states"). The hero is `quant_person.usdz` (from `Avatar.blend`),
  posed with the five parts below and coloured by posture, matte and softly lit, with the
  outline of its calibrated pose over it and a small nose so a turned head shows on an egg that
  looks the same from every side (the primitive figure had a nose tick for the same reason).
  The model's frame is Z up with its front at −Y; a torso pitch about +X leans it towards the
  camera, a roll about +Y tilts its top right, a head pitch about +X nods, a yaw about +Z turns
  the face right, and the head sinks into the shoulders with a head drop (`CalmModelPose`).
  **It is drawn one frame at a time, only when the pose changes** (`RealityRenderer`, iOS 18),
  moving between poses over half a second: a RealityKit view can't be paused and draws every
  frame (a hidden one has been measured at about 30% of the CPU), which on a screen left on
  for hours beside the camera is heat, and heat pauses detection. Sitting well it draws
  nothing. If the model or Metal is missing, the drawn figure below takes its place.
- **The drawn figure, kept as the fallback** (rethought 2026-10-21: Dave found the first
  design's column "means nothing"). A front view of head, neck and shoulders, standing in a faint
  outline of how you sat at calibration. Sitting well, you fill the outline; slouching, you leave
  it the way you moved. Every metric is a front camera's change since calibration, so each has a
  front-view shape: leaning in draws you bigger (closer), a head drop shortens the neck, a sink
  lowers you (out through the flat cut at the bottom, like a bust), a side lean tilts you about
  the hips, and a head turn turns the face. The outline's neck is your own, from calibration.
  Not a side profile: that would draw a rounded back and a forward head the camera can't
  measure. Each part shows how far past its line you are, eased so the line itself shows
  clearly (about two thirds of the part's change) and far past it stops growing, in steps of
  0.05 so a frame's jitter doesn't redraw the screen. Sitting well, the figure is exactly the
  outline and doesn't move. Away, the outline stands empty, dashed.
  *(The first design, kept for the record: a capsule column at the timeline's band height.)*
- **Brightness says how much it matters.** Sitting well is a dim green, the quietest the screen
  gets; a slouch lights up the figure in yellow, then red, with a glow. The edge of the eye notices a change
  in brightness before a change in colour, so a slouch is seen without looking, and sitting well
  isn't a lit panel in the corner of your eye for hours. The day's strip is dimmed the same way,
  so the slouches stand out on a quiet green.
- **Nothing jumps.** The two lines under the word keep their space whether they show or not, so
  the figure and the word stay put when a slouch starts or ends.
- **Dark, always.** Black background, white type, colour only on the figure and the countdown.
  The screen is on for hours: an OLED's black pixels are off, which means less power and less
  heat, and heat already pauses detection. It also keeps the glare out of your peripheral vision.
  Like StandBy, it ignores the system's light mode. Sheets opened from it still follow the
  system.
- **Calm in the periphery.** Peripheral vision picks up motion and brightness changes. The view
  is still while you sit well, with no ticking timers and no pulsing. The figure morphs between
  poses (0.8 s, none with Reduce Motion). Timers appear only while a slouch or a head turn is
  being counted, when attention is wanted anyway.
- **Words match the Watch and the timeline:** Sitting well / Slouching / Still slouching / Head
  turned / Away / Camera paused. Built from the same `PostureGlance` the Watch is sent, so the two
  can't disagree. One difference: a head turn while sitting well keeps the figure green and in
  its outline, only the head turned, as the timeline next to it records it, where the Watch
  shows it in yellow.
- **Burn-in.** A static screen for hours on OLED. The content moves a point round a 3 pt circle
  each minute (about 2.3 pt), eased over 2 s, as StandBy and Always-On do. You don't see it happen.
- **Honest about what it sees.** The top line says Live, Starting, Paused, Cooling down, or
  "Can't see you clearly" while tracking isn't good. In that last case the posture is held, not
  judged (the engine freezes it), so the figure and the word fade and the timers give way to
  "Held until the camera sees you clearly". The status bar is hidden, as on StandBy.
- **Four controls, labelled, toggles look toggled:** Silence (a menu, as in debug), Calibrate
  (the Watch's word; "Recalibrate" didn't fit at large text), Camera (shows the camera feed in the figure's place, to check framing, and is the same switch
  the Watch's Show camera flips), Settings. Debug-only tools (sip calibration, the 3D view,
  recording, Jev) stay in the debug view.
- **The switch** sits in the same corner in both views. In debug it's a leaf icon at the end of
  the diagnostics panel's top line (a sixth icon in the bottom row would push it past the screen's
  width at large text sizes). In calm it's a quiet "Debug" capsule at the top right with a 44 pt
  target. The choice is kept across launches. It starts in debug. The switch is instant: a
  crossfade would put both screens' camera previews on one session at once. A recording keeps
  going across the switch, shows as REC in the calm top line, and its share link survives.
- **States other than monitoring.** Calibration, camera permission and rear-camera problems
  show the existing screens under the calm view's top line, with Settings below them. While
  calibrating, the camera's view shows above the calibration screen (whatever the Camera control
  says), since that's when framing matters, and the top line says "Waiting for a clear view"
  until tracking is good. Critical heat shows "Cooling down" in the empty outline; serious heat shows
  "Warm · less accurate" in the top line.
- **The same glance as the Watch, steadied the same way.** The calm view reads
  `AppModel.calmGlance`: the Watch's `PostureGlance`, held to its last times within a second
  (rounding can flip a start between neighbouring seconds), taken each second and on each change
  of posture. The content is `Equatable`, so ten AppModel updates a second redraw it only when
  what it shows changes.
- **Landscape** puts the figure and word on the left, today and the controls on the right.

## Non-goals

- No change to detection, nudging, the Watch, or the debug view beyond the switch.
- The calm view isn't a tuning tool: no metrics, no numbers beyond time.
- The stored-data notice and the 3D view aren't in the calm view.

## Anti-goals

- A screen that flickers or draws the eye while you're sitting well.
- Colour as the only cue.
- Any calm-view state that hides that the camera has stopped.

## Review, 2026-10-20

A review agent read the change before hand-over and raised 15 points. Fixed: timers that could
flicker by a second (the glance wasn't steadied), "Live" over a frozen posture with tracking
degraded, a status bar likely black on black in light mode, calibrating without the camera's
view, the minute's shift jumping 5.5 pt, the share link lost on a switch, the problem screens
pointing at a Settings button that wasn't there, a full redraw on every frame, the Dynamic Type
cap missing the headline, the sip-label sheet able to cover calibration, a small switch target,
"Camera paused" at launch, two previews during the fade, and "Recalibrate" not fitting. Not
changed: the Silence menu's caption, which renders the same grey as the others.

## Still to check on a device

The renders came from the simulator, which has no camera. On a phone: the camera view in the
figure's place and above calibration, the hidden status bar, the Silence menu's look, and whether a
minute's 2.3 pt shift can be seen.

