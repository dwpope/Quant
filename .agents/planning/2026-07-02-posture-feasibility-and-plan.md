# Posture Tracking — Feasibility Verdict & Plan (2026-07-02)

## Verdict

**Feasible — but only after reframing what is being measured.** Meaningful "track bad
posture and nudge me" is achievable on the current codebase. What is *not* feasible is
the current implicit framing: five camera-relative skeleton deltas from a propped-up
front camera treated as posture truth. That framing is why months of gain-tuning never
converged — several of the scored signals cannot be made valid by tuning, because the
information isn't in the data.

**Iterate, don't restart.** The expensive, hard-to-rebuild parts are healthy:
PostureLogic is a cleanly separated Swift package with ~50 test files, golden-recording
replay infrastructure, a well-designed temporal state machine (drift 60s → bad → 300s →
nudge, hysteresis, cooldowns, task modes), and a working TrueDepth ARFaceAnchor pipeline.
The broken part is *which signals feed scoring* — a subtraction-and-rewire job, not a
rewrite.

---

## Evidence: why the current metrics can't be tuned into correctness

From the code audit (file:line verified) plus the 2026-07-02 device tests:

| Scored metric | What it actually measures | Fatal problem |
|---|---|---|
| `forwardCreep` (thr 0.03) | 2D shoulder-pixel-width growth | Camera-relative: a phone nudge of 3–29% width change scores as posture (stale-baseline gate is 30%, `StaleBaselineDetector.swift:26`). Also `>` not `abs()` — lean-back never caught, contradicting its own comment (`PostureEngine.swift:380-388`) |
| `headDrop` (thr 0.018) | ear-height above shoulders / shoulder width | Best of the five, but SNR ~1.3:1 on device (mild 0.012 / bad 0.025 vs ±0.01 flicker); silent ear→nose source fallback steps the signal (`PoseDepthFusion.swift:462-468`); threshold derived pre-denoiser, flagged provisional |
| `shoulderRounding` (thr 10°) | hips almost never visible → pseudo-angle from head-above-shoulder ratio (`PoseDepthFusion.swift:481-509`) | Looking down ≠ slouching, but reads as torso lean; double-counts the same gesture as `headDrop` |
| `lateralLean` (thr 0.08) | abs shoulder-mid x-offset | Unit chaos: normalized image coords in 2D mode, meters in depth mode, one threshold (`PoseDepthFusion.swift:215` vs `:337`); device test: responds one direction only |
| `twist` (thr 15°) | `asin(Δshoulder-y/width)` = shoulder-line **tilt** | Misnamed — not axial rotation; direction-blind on device (positive both ways); axial twist actually shows up as width foreshortening (= negative forwardCreep) |

Structural findings that no threshold value fixes:

1. **Any-metric-OR scoring** (`PostureEngine.swift:388-392`): the union of five marginal
   signals is a false-positive maximizer. One flaky channel poisons the whole verdict.
2. **The one anatomically meaningful forward-head signal is dead on the default path**:
   ARFaceAnchor head-to-camera translation is computed and discarded at
   `HeadOrientationDecomposition.swift:75-76`; `headForwardOffset` is hard-0 in
   `fuse2D`; `.frontFace` never enters `fuse3D`. Head pitch/yaw/roll quaternions exist
   but are visualization-only, never scored (`PoseSample.swift:31-42`).
3. **Everything is deviation from a 5s snapshot** — "good posture" is defined as
   "however you sat during calibration," silently expiring after 1h.
4. **Device motion reads as posture change** — no suppression exists; camera transform
   delta is available free on the AR paths and currently unused.
5. **Delivery is foreground-only by iOS design** (camera/ARKit stop on background/lock;
   screen pinned awake via `AppModel.swift:577`). Nudge = ambient audio ping (silenced
   by the mute switch) + Watch haptic. No `UNUserNotificationCenter` anywhere.

**What's already good:** the temporal state machine is the part best aligned with
actual ergonomics evidence (sustained duration, not instantaneous geometry, is the
modifiable risk factor); the Watch haptic channel; the replay/golden-recording test
infra; the One-Euro/critically-damped filtering layer; task modes.

---

## Reframe: what a front camera CAN honestly measure

Clinically validated postural angles (craniovertebral angle, cervical flexion,
kyphosis) need a **side view** — structurally unavailable. Front TrueDepth *can*
honestly measure:

- **Lean-in / viewing distance** (ARFace translation, metric, ~±1cm) — Apple ships
  exactly this as Screen Distance. Currently discarded.
- **Head pitch delta** (ARFace quaternion vs calibrated neutral) — already computed,
  smoothed, never scored.
- **Head drop** (ear-carriage, the redesigned metric) — marginal but usable once
  thresholded post-filter.
- **Presence + stillness + time** — sustained static sitting; the best-evidenced
  nudge trigger of all, and nearly immune to signal-validity problems.

The honest product is **"deviation from your calibrated neutral + time under load,"
a desk-session coach** — not a clinical posture instrument and not (with a phone
camera alone) a passive all-day monitor.

---

## Plan

### Phase 0 — Spikes (evidence before code)
- **S1 Lean-in SNR**: stop discarding `relative.columns.3` at
  `HeadOrientationDecomposition.swift:75`; HUD-log head-to-camera distance; record
  neutral / mild / bad separation on device. Expect ≥5:1 SNR (metric TrueDepth).
- **S2 Head-pitch SNR**: same protocol for ARFace pitch delta.
- **S3 AirPods background** (decides Phase 4): 20-line spike — does
  `CMHeadphoneMotionManager` keep delivering with app backgrounded/locked?
  (Posture Pal precedent suggests a viable path; verify current OS behavior.)

### Phase 1 — Signal honesty (subtract, then rewire)
- Remove from scoring: `shoulderRounding`, `twist`, `lateralLean` (keep computed for
  viz/telemetry; they were never valid verdict inputs).
- Score on: **lean-in distance** (S1), **head pitch delta** (S2), **headDrop**
  (threshold re-derived post-One-Euro), **presence/stillness timer**.
- Replace any-metric-OR with **2-of-N or weighted score** for the geometric channels;
  time-based triggers stay independent.
- **Device-motion suppression**: inter-frame `frame.camera.transform` delta →
  clamp quality to `.degraded` → reuses existing freeze at `PostureEngine.swift:162`.
- Fix ear→nose fallback discontinuity (freeze headDrop during source switch, don't step).
- Calibration hardening: outlier-rejecting robust mean; don't fail the run on one
  sub-quality frame; per-signal baselines with the new channels.

### Phase 2 — Trustworthy nudge experience
- **Sustained-sitting / movement-break coaching** as a first-class trigger
  (uses `movementLevel`, currently computed-and-ignored) — works even when geometry
  is degraded.
- Delivery: Watch haptic primary; add local notification so a locked phone still
  nudges at session end; audio stays opt-in.
- Surface the state machine honestly in UI (drift countdown → "nudge in Xs"), so the
  ~6-minute latency reads as designed patience, not lag.
- Session framing: "desk session" start/stop; absence detection already exists.

### Phase 3 — Demo (roadmap Stage 1b, unchanged)
- Finish axis-map dialing / continuous basis alignment for the figure (session-2 plan
  Test B) — a *render* concern, decoupled from scoring by design.
- Record the 60s demo: calibrate → good → slouch → nudge → recover.

### Phase 4 — Optional reach (only if S3 passes)
- AirPods head-pitch as second sensor: background-capable "passive mode" nudging
  head-pitch-only; phone camera becomes the rich foreground mode.
- Alternative/complement: Mac menu-bar companion (webcam runs fine all day on macOS)
  sharing PostureLogic via SPM.

### Not doing / not claiming
- No CVA, kyphosis, or "spine angle" claims — physically unavailable from front view.
- No more tuning of `twist`/`shoulderRounding`/`lateralLean` toward validity — retired
  from scoring rather than re-tuned.
- No full rewrite: PostureLogic package, replay infra, state machine, viz pipeline stay.

### Open items (couldn't verify this session — agent budget cut)
- CMHeadphoneMotionManager background-delivery details (S3 spike answers empirically).
- Competitive scan (Posture Pal / Upright retention lessons) — nice-to-have context,
  not plan-blocking.
