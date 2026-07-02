# Axis Dialing — fix "turn reads as lean" (2026-07-02)

**Why now:** the quaternion head source finally stays live through a turn (dropout fixed).
So the `axis map` stepper is, for the first time, dialing the *real* render path. Every prior
attempt was on the dead 2D path — this one counts.

**The symptom:** turning your head left↔right makes the figure **lean/tilt** (roll+pitch)
instead of **turning** (yaw). That's a basis misalignment — your yaw is being routed into the
wrong output axes. Dialing the basis rotation should re-route it.

---

## ⛳ Gate (same as always)
- [ ] `src: QUAT` (green), `mode: frontFace`, `ARFace trk:` climbing
- [ ] Open the **calibration overlay** (the one with the `axis map` stepper, `gain`, `max°`, `mirror`)

## Setup
- [ ] `gain` = 1.0, `max°` = 110 (defaults), `mirror` = off
- [ ] Face forward, sit at rest so the figure starts neutral

---

## Dial the `axis map` stepper

Step the **`axis map`** index from **0 upward**. At **each** index, do **one slow left→right head turn** and watch the figure:

| What the figure does on a left-right turn | Meaning |
|---|---|
| Leans / tilts / nods (roll or pitch) | **Wrong** — skip to next index |
| **Turns left-right (yaw)** | **Candidate!** Note the index |

At each **candidate** index, confirm the other two motions too:
- [ ] **Nod** up/down → figure **pitches** (nods)?
- [ ] **Tilt** ear-to-shoulder → figure **rolls** (tilts)?

The best index maps **all three** correctly.

If turn→yaw but **inverted** (you turn left, figure turns right) → toggle **`mirror`**.

---

## 📋 Record & report

```
Best axis map index = ____     mirror on/off = ____
Turn → yaw?  ____   Nod → pitch?  ____   Tilt → roll?  ____
Residual on a LEVEL turn: does the head still dip/tilt slightly? ____  (~how many degrees? ____)
```

## What each outcome means
- **All three map cleanly, no residual** → I bake that index + mirror as the default. Done.
- **Turn→yaw works but a small dip/tilt remains on a level turn** → that's the expected
  off-cardinal remainder the discrete stepper can't reach. Report the residual size and I
  build the **continuous basis-align fix** (fine 3-axis offset) sized to it.
- **No index gives turn→yaw at all** → tell me the two *closest* indices and I build the
  continuous fix from scratch.

Don't grind all 24 if it's clearly hopeless — a quick left-right turn at each is enough to
reject the wrong ones. You're looking for the 1–2 where the head **turns** with you.
