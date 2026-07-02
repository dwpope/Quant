# Quant — Device Test Plan (2026-07-02)

Two workstreams, one session: **(A) quaternion head-tracking dropout** and **(B) new ear-based neck metric**.
Stay in **Front (Face)** mode with the **dev values HUD open** the whole time.

---

## ⛳ GATE — do this first. Nothing below counts until all green.

- [ ] `⌘R` build + run onto the device
- [ ] Settings → camera = **Front (Face)**. If the HUD `src` row shows **`2D`**, toggle **Front (2D) → Front (Face)** once to force the face session to start.
- [ ] Open the dev values HUD
- [ ] Confirm the gate rows:
  - `src: QUAT` (green)
  - `mode: frontFace` (green)
  - `ARFace  run:Y  f:<climbing>  trk:<climbing>`

**If any gate row is wrong, STOP and report it — every test below is invalid until the gate is green.**

---

## 📖 HUD LEGEND — what each row means

| Row | Shows | Neutral / good | Meaning when off |
|---|---|---|---|
| `src` | head source this frame | `QUAT` (green) | `2D` (orange) = face quaternion lost, on Euler fallback |
| `mode` | camera mode | `frontFace` (green) | `OTHER` = not in face mode |
| `ARFace` | session diagnostics | `run:Y`, `f`/`trk` climbing | `run:N` = not started; `trk` frozen = no face tracked |
| `gap` | `since:` live / `max:` peak | `since:0` (green) | `since` climbs orange = holding from grace window; `max` = worst gap this session |
| `neck` | raw `neckHeight` → mapped `headDrop` | mapped **~0** at neutral | mapped **orange** = neck metric tripping (`> 0.06`) |
| `latLean` `twist` `fwdCreep` | other posture channels | move with you | stuck = dead channel |

---

## TEST 1 — Quaternion dropout (do this FIRST, while tracking is fresh)

**Goal:** measure the worst tracking gap on a normal turn → decides whether we widen the grace window again or build the QUAT↔2D crossfade.

1. Face forward. Confirm `gap  since:0  max:` is low (~0).
2. Turn your head **left → right → center** a few times, at your **natural desk turn range** (as if glancing at a second monitor).
3. Face forward again and read **`gap max:`**.
   → **RECORD: `max` = ______**
4. During the turns, note:
   - Did `src` flip to **`2D`**?  → **______**
   - Did the head figure **follow** your yaw, or **snap**?  → **______**

---

## TEST 2 — Neck recalibration (MANDATORY before Test 3)

**Why:** the neck metric changed what it reads. Your old baseline makes it inert — the `neck` row will show a big **negative** mapped value and never trip until you recalibrate.

1. Sit **tall, in good posture** (this becomes your neutral reference).
2. Run a **fresh calibration** (however you normally trigger it).
3. At neutral, read the `neck` row **mapped** value.
   → should be **~0**.  → **RECORD: neutral mapped = ______**
   - ⚠️ If it's a big negative (e.g. `−0.4`), calibration didn't take — retry. If it persists, report it.

---

## TEST 3 — Neck threshold tuning

**Goal:** find the right trip point. `0.06` is probably too high now — the ear travels less than the nose for the same head-drop.

1. At neutral: `neck mapped ≈ 0`, not orange. ✔
2. **Mild slouch** (slightly forward/down): read mapped.  → **RECORD: mild = ______**
3. **Clearly bad** carriage (head craned down/forward toward the screen): read mapped.  → **RECORD: bad = ______**
4. Does the row go **orange** (crosses `0.06`) at bad posture?  → **______**
   - If it **never** goes orange even when clearly bad, `0.06` is too high — that's the signal to lower it.

---

## TEST 4 — Quick regression (30 sec — confirm nothing else broke)

- Lean side to side → `latLean` moves? **______**
- Twist shoulders → `twist` moves? **______**
- Lean toward camera → `fwdCreep` moves? **______**
- Any row stuck / dead? **______**

---

## 📋 REPORT BACK (fill the blanks)

```
TEST 1  max = ____   src dropped to 2D? ____   followed / snapped? ____
TEST 2  neck neutral mapped = ____
TEST 3  mild = ____   bad = ____   orange at bad? ____
TEST 4  latLean ok? ____  twist ok? ____  fwdCreep ok? ____  anything dead? ____
```

**What I do with it:**
- Test 1 `max` → size the quaternion fix (widen grace vs. build crossfade).
- Test 2/3 values → set `headDropThreshold` to the right neck trip point.
- Test 4 → confirms the neck refactor didn't disturb the other scored metrics.
