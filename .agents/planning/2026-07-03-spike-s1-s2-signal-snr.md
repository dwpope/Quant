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
- [ ] **New:** `bl` row is **green** (`age Xm`). If it's orange **`NONE`**, run a fresh
      calibration sitting tall FIRST — with no baseline every baseline-relative row
      reads a fake perfect 0 (this is what silently invalidated session 2's Tests A/C:
      a relaunch drops any saved baseline older than 1h).

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
   → **RECORD: dist flicker = 84.7 – 84.8 cm**
2. `rawPitch` range over the 10s:
   → **RECORD: pitch flicker = 1.8 – 1.9 °**

---

## TEST 2 — Separation (the actual signal)

Give each pose ~3s to settle, then read. (These are raw rows — no baseline needed;
we difference the readings on paper.)

| Pose | `dist` (cm) | `rawPitch` (°) |
|---|---|---|
| Neutral (sit tall) | 85 | 0.7 |
| Mild slouch | 80.6 | 0.3 |
| Clearly bad (craned at screen) | 71.1 | 0.7 |
| Lean back (rest against chair) | 94 | 0.18 |

The lean-back row is the control: distance should *increase*, pitch should move
opposite to the bad-pose direction. If either doesn't, that's a finding.

---

## TEST 3 — False-positive probes (what must NOT move the signals)

- **Head turn** (level, like glancing at a second monitor): does `dist` hold roughly
  steady (±1–2 cm)? → **Yes**  (`rawPitch` will move some — note how much: 0.17 to -14°)
- **Phone bump** (tap/shift the phone slightly on its stand): how much does `dist`
  jump? → **1cm** *(this sizes the device-motion suppression work)*
- **Sit-and-slide** (scoot chair back ~10 cm, same posture): `dist` should grow by
  roughly the scoot distance → **yes, about 10cm**

---

## TEST 4 — Neck re-tune REDO (session 2's Test A, invalidated by the nil baseline)

With `bl` green (fresh calibration, sitting tall):

- Held pose ~5s: `neck` mapped steady now (One-Euro validation)? → **-0.3 for raw 0.0 for mapped**
- Neutral mapped = **0.028 for raw 0.0 for mapped** · Mild = **0.18 for raw 0.0 for mapped** (orange? No) · Bad = **0.0 for raw 0.0 for mapped** (orange? No)
- Verdict: does `0.018` trip at bad, stay quiet at neutral/mild? → **stay quiet**

**⚠️ 2026-07-03 RESULT VOID — display bug, not signal bug.** The mapped cell rendered
with 1 decimal place, so every value in the metric's real range (±0.05) displayed as
"±0.0". Fixed to 3 decimals. The raw readings above (−0.3 ↔ 0.028 ↔ 0.18 across
similar poses) also flag a source-stability question — watch raw on the re-read.

### TEST 4b — the same readings, on the 3-decimal build
- Held ~5s: mapped steady? → **steady 0.001 deviation**  raw steady? → **0.01 deviation**
- Neutral mapped = **0.0** · Mild = **0.10 for mapped** (orange? No) · Bad = **0.22** (orange? No)
- Verdict on `0.018`: → **Can push to a value like 0.24 but not seeing any orange getting triggered**

**✅ RESOLVED (2026-07-03):** neck metric VALIDATED — flicker 0.001 vs bad 0.22 ≈ 220×
SNR; One-Euro smoothing confirmed working. Actions taken: `headDropThreshold`
0.018 → **0.15** (midway mild 0.10 / bad 0.22; full test suite re-derived, 560 green).
The missing orange was a THIRD display bug: row-level `foregroundStyle` on a `GridRow`
doesn't render — trip styling moved onto the value cells (bold + orange). Verify on
next run: crane down until mapped > 0.15 → the neck numbers should go bold orange.

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
