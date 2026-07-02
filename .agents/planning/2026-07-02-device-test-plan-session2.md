# Quant — Device Test Plan · Session 2 (2026-07-02)

Two tasks this session: **(A) neck metric re-tune** (now smoothed) and **(B) turn→yaw axis dialing**.
Stay in **Front (Face)** with the **dev values HUD open** throughout. (Supersedes the standalone axis-dialing doc — everything's here.)

---

## ⛳ GATE — do this first. Nothing counts until green.

- [ ] `⌘R` build + run onto device
- [ ] Camera = **Front (Face)**. If HUD `src` shows `2D`, toggle **Front (2D) → Front (Face)** once.
- [ ] Open the dev values HUD
- [ ] Confirm: `src: QUAT` (green) · `mode: frontFace` (green) · `ARFace run:Y  trk:<climbing>`

**If any gate row is wrong, STOP and report it.**

---

## 📖 LEGEND (rows you'll use)

| Row / control | Shows | Good reading |
|---|---|---|
| `src` | head source | `QUAT` (green) |
| `neck` | raw `neckHeight` → mapped `headDrop` | mapped **~0** at neutral, **orange** when it trips (`> 0.018`) |
| `gap` | `since:` / `max:` tracking gap | `since:0` |
| `axis map` (calibration overlay) | basis-rotation index | dial in Task B |
| `gain` / `max°` / `mirror` (calibration overlay) | head render controls | 1.0 / 110 / off |

---

## TEST A — Neck metric re-tune (validates the smoothing + sets the threshold)

**What changed:** the neck signal now runs through a One-Euro filter, so it should read **steady** at a fixed pose (it flickered ±0.01 before). Threshold is now `0.018`.

- **A1 — Steady check (validates the fix).** Hold a fixed head/neck pose for ~5 s and watch `neck` **mapped**.
  → Is it now **steady** (barely moving), or still flickering?  → **______**

- **A2 — Neutral.** Sit tall in good posture. Read `neck` **mapped**. Should be **~0**.
  → **RECORD: neutral = ______**
  - If it's noticeably off zero (e.g. ±0.02+), your saved baseline drifted — run a fresh calibration sitting tall, then re-read.

- **A3 — Mild slouch** (slightly forward/down), let it settle, read mapped.
  → **RECORD: mild = ______**   · goes orange?  **______**

- **A4 — Clearly bad** carriage (head craned down/forward), let it settle, read mapped.
  → **RECORD: bad = ______**   · goes orange (crosses `0.018`)?  **______**

- **A5 — Verdict.** Does `0.018` cleanly **trip at bad but stay quiet at neutral/mild**?
  → **______**  (If not: what value would sit between your mild and bad readings? **______**)

---

## TEST B — Axis dialing (fix "turn reads as lean")

**Goal:** find the `axis map` index where a head **turn → the figure yaws** (turns with you), instead of leaning/tilting.

**Setup:** in the calibration overlay set `gain` = 1.0, `max°` = 110, `mirror` = off. Face forward, at rest.

- **B1 — Sweep.** Step **`axis map`** from **0 upward**. At each index do **one slow left→right head turn**:

  | Figure does… | → |
  |---|---|
  | leans / tilts / nods | **wrong — next index** |
  | **turns left-right (yaw)** | **candidate — note the index** |

- **B2 — Confirm a candidate.** At each candidate index, also check:
  - Nod up/down → figure **pitches**?  **______**
  - Tilt ear-to-shoulder → figure **rolls**?  **______**

- **B3 — Mirror.** If turn→yaw but **inverted** (turn left → figure turns right), toggle **`mirror`** on.

- **B4 — Residual.** At your best index, do a **level** left-right turn. Does the head still **dip/tilt** slightly as it turns?
  → **RECORD: residual dip = ______** (none / small ~__°  / large)

---

## (Optional) TEST C — Lean direction (to inform a decision)

Lean your upper body **left**, then **right**, from center. Does the figure respond **both** ways, or mostly one way?
→ **______**  *(This decides whether I disable the "swivel-rejection" lean fade for symmetric lean — your call.)*

---

## 📋 REPORT BACK (fill the blanks)

```
TASK A (neck)
  A1 steady now? ____   A2 neutral = ____   A3 mild = ____ (orange? ____)   A4 bad = ____ (orange? ____)
  A5 does 0.018 work? ____   if not, better value = ____

TASK B (axis)
  best axis map index = ____   mirror = ____
  turn→yaw? ____   nod→pitch? ____   tilt→roll? ____
  residual dip on a level turn = ____

TASK C (optional)  lean both ways? ____
```

**What I do with it:**
- Task A → finalize `headDropThreshold`.
- Task B → bake the winning axis index + mirror as default; if there's residual dip, build the continuous basis-align fix sized to it.
- Task C → apply the lean choice (symmetric vs swivel-rejection).
