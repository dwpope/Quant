# Spike S1+S2 — Lean-in Distance & Head-Pitch SNR (2026-07-03)

**Goal:** decide whether **head-to-camera distance** (S1, new `dist` HUD row) and
**head pitch** (S2, existing `rawPitch` row) have the signal-to-noise to become the
scored signals of Phase 1 — *before* any scoring code is written. This is the gate the
old neck metric never had (its SNR turned out ~1.3:1, measured only after the
threshold shipped).

**Pass bar:** neutral→bad separation ≥ **5×** the held-pose flicker, both signals.

Stay in **Front (Face)** with the **dev values HUD open** throughout. ~10 minutes.

---

## ⛳ GATE — nothing counts until green

- [ ] `⌘R` build + run onto device
- [ ] Camera = **Front (Face)**; if HUD `src` shows `2D`, toggle Front (2D) → Front (Face) once
- [ ] `src: QUAT` (green) · `mode: frontFace` (green) · `ARFace run:Y trk:` climbing
- [ ] **New:** `dist` row shows a **green cm value** (orange `--` = no tracked face yet)

**If any gate row is wrong, STOP and report it.**

---

## 📖 ROWS FOR THIS SESSION

| Row | Shows | Note |
|---|---|---|
| `dist` | head-to-camera distance, cm (metric, from ARFace translation) | **new this build** |
| `rawPitch` | source head pitch, degrees (pre-gain, camera-relative) | raw-only row — empty "mapped" cell is by design, not a dead channel |

Posture words below mean: **neutral** = sitting tall, your calibration posture;
**mild** = slight slouch/settle; **bad** = clearly craned down/forward at the screen.

---

## TEST 1 — Flicker (noise floor at a held pose)

Sit neutral, then hold as still as you can for ~10s. Watch both rows.

1. `dist` range over the 10s (e.g. "51.2–51.8"):
   → **RECORD: dist flicker = ______ – ______ cm**
2. `rawPitch` range over the 10s:
   → **RECORD: pitch flicker = ______ – ______ °**

---

## TEST 2 — Separation (the actual signal)

Give each pose ~3s to settle, then read. (These are raw rows — no baseline needed;
we difference the readings on paper.)

| Pose | `dist` (cm) | `rawPitch` (°) |
|---|---|---|
| Neutral (sit tall) | ______ | ______ |
| Mild slouch | ______ | ______ |
| Clearly bad (craned at screen) | ______ | ______ |
| Lean back (rest against chair) | ______ | ______ |

The lean-back row is the control: distance should *increase*, pitch should move
opposite to the bad-pose direction. If either doesn't, that's a finding.

---

## TEST 3 — False-positive probes (what must NOT move the signals)

- **Head turn** (level, like glancing at a second monitor): does `dist` hold roughly
  steady (±1–2 cm)? → **______**  (`rawPitch` will move some — note how much: ______°)
- **Phone bump** (tap/shift the phone slightly on its stand): how much does `dist`
  jump? → **______ cm** *(this sizes the device-motion suppression work)*
- **Sit-and-slide** (scoot chair back ~10 cm, same posture): `dist` should grow by
  roughly the scoot distance → **______**

---

## 📋 REPORT BACK

```
TEST 1  dist flicker = __ – __ cm     pitch flicker = __ – __ °
TEST 2  dist  neutral/mild/bad/leanback = __ / __ / __ / __
        pitch neutral/mild/bad/leanback = __ / __ / __ / __
TEST 3  turn: dist steady? __  pitch moved __°
        bump: dist jump __ cm     slide: tracked scoot? __
```

**What I do with it:**
- **Both pass the 5× bar** → Phase 1 proceeds: retire the invalid metrics, score on
  lean-in + pitch delta + headDrop + stillness (per
  `2026-07-02-posture-feasibility-and-plan.md`).
- **One passes** → Phase 1 scores on the passing signal; the other stays viz-only.
- **Neither passes** (unexpected — this is metric TrueDepth data) → stop and rethink
  before writing any Phase 1 code; the front-camera geometric approach would be down
  to headDrop + time-based coaching only.
- Test 3 numbers size the device-motion suppression thresholds either way.
