# Aware — Staged Roadmap (2026-06-01)

> Sequencing doc above the per-feature plans. Each stage is finished and **posted
> about** before the next begins — one stage in flight at a time. This is the
> anti-half-finished-work discipline: a stage isn't done until its tests are green
> (or its demo is recorded) **and** the post is written.
>
> Strategy: get the **work-context** monitoring loop (posture → water → language)
> to a genuinely good state inside Aware, validate it, *then* extend to the
> lifestyle/keepsake context. Aware is the spatial flagship; this roadmap is also
> the source of the portfolio demo + POV.

## Why posture is Stage 1
It's the core of Aware and the source of the demo video — the highest-value asset
in the plan. Fixing a peripheral feature first while the flagship's centrepiece
reads wrong would be backwards.

Posture splits to stay *finishable* (tuning has no unit test, so it's the stage
most prone to sprawl):
- **1a — Correctness** (Ralph-runnable, testable): the bugs with a definite right
  answer.
- **1b — Tuning + demo** (manual, human + device): bounded by the deliverable —
  the 60-second demo you're happy to post. Mirrors the existing "Step 7" pattern.

---

## Stages

### Stage 1a — Posture correctness  → `2026-06-01-posture-correctness/`
Root causes (from code + the existing dev-notes):
- Pitch/roll use **absolute** geometry, not calibration-relative, when no
  `.calibrating` frame fires (e.g. app resumes in `.good`) → the "permanently
  tilted" look. `PostureVisualizationViewModel` captures `restPitch/RollDegrees`
  only on the transition *from* `.calibrating`.
- Head **yaw** is sourced from `PoseSample.shoulderTwist` (shoulder rotation),
  not a head-derived signal — the design doc specifies yaw from nose-vs-ear
  geometry.
- Axis directions/signs are untested → easy to regress during 1b tuning.

**Done =** unit tests green: a neutral sit resolves all channels to ~0° (with and
without an explicit `.calibrating` frame), yaw derives from head keypoints, and
each movement drives the correct channel in the correct direction. Full app suite
+ `swift test --package-path PostureLogic` green.
**Post:** "Why your posture demo looked tilted — calibration-relative rendering."

### Stage 1b — Posture tuning + demo  *(manual, not a loop)*
With correctness locked, tune the Mapping amplifications/caps by eye on-device via
the raw↔mapped HUD; record the 60s demo (calibration → good → slouch → recovery).
**Done =** a demo you'll post. **Post:** the demo + "Designing an honest posture
visualisation."

### Stage 2 — Sip counter: kill false positives  → `…-sip-detection-precision/`
Root causes (`PostureLogic/.../SipDetector.swift`):
- `proximityThreshold` 0.35 too permissive — any hand-near-face enters candidate.
- No minimum-candidate-age / debounce — can confirm on the first frame.
- `velocityThreshold` 0.008 tiny and non-directional — scratching/glasses pass.
**Done =** TDD: tests reproducing scratch / chin-rest / phone-to-ear are rejected
while real sips (golden recordings) still pass; tighter proximity, a 0.3–0.5s
candidate-age gate, sustained/directional velocity. Pure logic — Ralph-runnable
overnight. **Post:** "Killing false positives in a wrist-to-face detector."

### Stage 3 — Water vs. goals
On the now-reliable sip data: a hydration target + a gentle "behind today" nudge.
Honest by construction (no guilt zeros). **Post:** "Hydration as honest nudging."

### Stage 4 — Language (your own voice, at the desk)
Consent-clean speaking reflection on *your* voice only (pace, filler, assertiveness),
surfaced minimally. Rehearsal/reflection framing — **not** live JPM meetings.
**Post:** "A speaking coach that only listens to me."

### Stage 5 — Adele keepsakes / recall  *(later)*
The lifestyle context: `MemoryKit` (keep/recall) + `SurfaceKit` surfacing, fed by
the wearable. Only after the work-context loop is validated.

---

## How this rides your existing machinery
- **Source of truth = these git-tracked plans.** Ralph runs a stage by pointing
  repo-root `PROMPT.md` at that stage's `implementation/plan.md`.
- **Surfacing = the dashboard reads this roadmap + git** → shows the current
  stage's next action (it already does file-based "one next action"). No new
  plumbing.
- **Reminders = life capture only**, one-way into the dashboard later if wanted
  (EventKit script). No bidirectional sync — re-prioritise by editing the source.
- **Don't build tooling before Stage 1a.** The plan + dashboard-reads-git already
  gives "surface the next action" for free.
