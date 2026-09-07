# Gravity-Levelled Head Axes — Device Validation (2026-07-03)

**What changed:** head angles + quaternion are now decomposed against a **levelled
reference frame** (world-up from gravity + the camera's horizontal heading) instead of
the tilted camera frame. The phone's prop angle can no longer leak a level turn into
pitch/roll — the −14° pitch-on-turn and "turn reads as lean at every axis index" bugs
are the same defect, and this build removes its cause. The old `portraitFixUp` knob is
gone; nothing about screen orientation enters the math anymore.

**Also in this build:** `headDropThreshold` = **0.15** (your Test 4b numbers), and the
orange trip cue now colors the value cells (bold orange) — row-level styling was a
silent no-op.

Stay in **Front (Face)**, dev values HUD open. ~10 minutes.

---

## ⛳ GATE

- [ ] `⌘R` build + run · Camera = **Front (Face)**
- [ ] `src: QUAT` · `mode: frontFace` · `ARFace run:Y trk:` climbing
- [ ] `bl` green (`age Xm`) — recalibrate sitting tall if orange `NONE`
- [ ] `dist` green

---

## TEST A — Axis purity on the HUD (no figure yet — numbers first)

Read the `rawYaw` / `rawPitch` / `rawRoll` rows (now = turn / nod / tilt):

- **A1 — Level turn** left↔right (like glancing at a second monitor):
  - `rawYaw` sweeps smoothly with the turn? → **______** (rough range: ±____°)
  - `rawPitch` stays ~flat? → **______** (worst excursion: ____°) ← *was −14° before*
  - `rawRoll` stays ~flat? → **______**
- **A2 — Nod** up/down: `rawPitch` sweeps (±____°), yaw/roll ~flat? → **______**
- **A3 — Tilt** ear-to-shoulder: `rawRoll` sweeps (±____°), yaw/pitch ~flat? → **______**
- **A4 — Signs** (these are now PREDICTIONS from the documented HeadAngles contract —
  confirm or refute): turn LEFT → rawYaw **negative** (matches? ____) · nod DOWN →
  rawPitch **positive** (____) · RIGHT ear to shoulder → rawRoll **negative** (____)

**A1–A3 clean = the basis fix is proven on device.** Signs are dialable; leaks are not.

---

## TEST B — The figure (default should now just work)

Calibration overlay: `gain` 1.0 · `max°` 110 · `mirror` off. The `axis map` default
is no longer identity — it's pre-set to the remap derived from the levelled frame
(the adversarial review derived it a priori). So:

- **B1 —** At the DEFAULT index (tap the reset if you've dialed it): turn→**yaw**?
  **____** · nod→**pitch**? **____** · tilt→**roll**? **____**
  - Any axis routed wrong → sweep as before and note the index that works: **____**
  - Any axis right-but-reversed → note which (that's a mirror/sign, not a routing bug): **____**
- **B2 —** At the working index, level turn: residual dip/tilt? → **______** ← *decides
  if we delete the stepper entirely*

---

## TEST C — S2 re-measure (head-pitch SNR, was blocked by the leak)

- Held pose ~10s: `rawPitch` flicker = **______ – ______ °**
- Neutral = **____°** · Mild slouch = **____°** · Clearly bad (craned) = **____°** · Lean back = **____°**

*(Pass bar unchanged: neutral→bad ≥ 5× flicker. If it passes, pitch-delta joins
lean-in + headDrop as scored signal #3.)*

---

## TEST D — 30s regression

- Crane down hard: `neck` mapped climbs past **0.15** and the numbers go **bold orange**? → **______**
- `dist` still tracking lean-in/back? → **______**
- `gap max:` after a few fast turns = **______** (dropout regression check)

---

## 📋 REPORT BACK

```
A1 turn:  yaw sweeps? __  pitch flat? __ (worst __°)  roll flat? __
A2 nod:   pitch sweeps? __   A3 tilt: roll sweeps? __
A4 signs: turnL=__  nodDown=__  tiltR=__
B  best index = __  mirror = __  residual = __
C  pitch flicker __–__°  neutral/mild/bad/leanback = __/__/__/__
D  neck orange past 0.15? __  dist ok? __  gap max = __
```
