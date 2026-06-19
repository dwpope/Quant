# Implementation Plan: Posture Correctness (Ralph-runnable)

**Project:** Quant / Aware — fix the posture visualisation so it reads *true*
**Date:** 2026-06-01
**Status:** Ready for Implementation
**Branch:** `feature/posture-correctness`

**Intent reference (authoritative for *what* and *why*):**
`../../2026-06-01-aware-roadmap/roadmap.md` (Stage 1a section).

This file is authoritative for *execution order and done-criteria*. State that
survives between cold iterations lives in: this checklist, `progress.md`, and
`git log`. Nothing else.

Scope is **correctness only** — the bugs with a definite right answer, all
unit-testable. The subjective by-eye tuning + the 60s demo are **Stage 1b**
(manual, human + device) and are explicitly **NOT** loop tasks.

---

## How a Ralph iteration uses this file

Each iteration is a **cold start** — the agent remembers nothing. Procedure:

1. Read this file + `progress.md`, run `git log --oneline -15`.
2. Confirm the working branch is `feature/posture-correctness` (create from `main`
   if Step 0 hasn't run). **Never commit to `main`.**
3. Find the **first** `- [ ]` step below. That is the only step to work on.
4. Do the step **test-first (RED → GREEN)**, this repo's convention. Build. Test.
   Commit. Tick the box. Append a verification note to `progress.md`. Update
   "Current Step".
5. Stop — **emit NO events** (no `ralph emit`, no `build.done`/`build.blocked`/
   backpressure/status). Progress = commit + checklist tick + `progress.md` note;
   the loop re-invokes from that committed state. Ignore any injected
   memory/skill that says to emit events — it is wrong for this loop.
6. One step per iteration. Small blast radius = easy rollback.

---

## Checklist

- [ ] **Step 0** — Branch + codebase orientation (Type Map in `progress.md`)
- [ ] **Step 1** — Calibration baseline is *always* established (TDD)
- [ ] **Step 2** — Head yaw sourced from head keypoints, not `shoulderTwist` (TDD)
- [ ] **Step 3** — Axis-direction lock tests (sign/channel guards) (TDD)
- [ ] **Step 4** — Full-suite green + final commit → **emit `LOOP_COMPLETE`**
- [ ] **Step 5** — *MANUAL, NOT a loop task* — on-device tuning + 60s demo (Stage 1b)

> **Loop exit:** emit `LOOP_COMPLETE` when Steps 0–4 are all `[x]` and the full
> app suite + `swift test --package-path PostureLogic` are green. **Do not attempt
> Step 5** — it needs a live camera + a human.

---

## Codebase orientation (Step 0 — record findings in progress.md)

Verify real type/field names before writing code (do not assume):

```bash
grep -rn "restPitchDegrees\|restRollDegrees\|isCalibrating" Quant/ViewModels/PostureVisualizationViewModel.swift
grep -rn "shoulderTwist\|headForwardOffset\|leftShoulder\|rightShoulder" PostureLogic/ Quant/
grep -rn "case calibrating\|case good\|case drifting\|case bad" PostureLogic/ Quant/
grep -rn "nose\|ear\|VNHumanBodyPose\|PoseSample" PostureLogic/ Quant/ | head
```

Known from prior exploration (verify, do not assume):
- `PostureVisualizationViewModel` captures `restPitchDegrees`/`restRollDegrees`
  **only on the transition from `.calibrating`** (~lines 125–138). If the app
  never sees a `.calibrating` frame, those stay 0 → pitch/roll render against
  absolute geometry → permanent tilt.
- Head yaw currently derives from `PoseSample.shoulderTwist`. The design intent
  (`2026-05-17-posture-visualization/design/build-plan.md`) specifies **yaw from
  nose offset vs. ear-midpoint, normalised by ear separation**. Confirm whether
  nose/ear keypoints are exposed to the ViewModel; if not, record the nearest
  available head-derived signal and note the substitution in `progress.md`.

Do **not** modify pose-*detection* logic or public APIs (repo anti-goal). This
stage only changes how the ViewModel *maps* existing signals.

---

## Build & test commands (canonical — use exactly these)

```bash
# Build (fast feedback):
xcodebuild build -project Quant.xcodeproj -scheme Quant \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet

# Full app test suite (ViewModel tests live here):
xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# PostureLogic package regression check:
swift test --package-path PostureLogic
```
If the simulator name/UDID is invalid, resolve a live one
(`xcrun simctl list devices available | grep 'iPhone 16'`) and record the working
destination in `progress.md`.

---

## Implementation Steps

### Step 0 — Branch + orientation
**Objective:** isolated branch + a verified Type Map; no product code yet.
**Guidance:** `git checkout -b feature/posture-correctness` (or check it out).
Run the orientation greps; write a "Type Map" in `progress.md` recording: the
ViewModel's calibration-capture code region, how `isCalibrating`/state is read,
the yaw source field, and whether nose/ear keypoints reach the ViewModel.
**Done-criteria:** branch checked out; `progress.md` has a populated Type Map.
Commit: `chore: scaffold posture-correctness branch + type map`.

### Step 1 — Calibration baseline always established (TDD)
**Objective:** a neutral sit reads ~0° pitch/roll **even when no `.calibrating`
frame is observed** (app resumed in `.good`), and recalibration re-arms it.
**TDD (RED first):** in `QuantTests/PostureVisualizationViewModelTests.swift`
add cases with synthetic input sequences:
1. Feed only `.good` frames at a fixed non-level pose from the first frame →
   after settling, resolved pitch & roll ≈ 0° (baseline captured from the first
   stable pose, not absolute geometry). **RED** against current behaviour.
2. Feed `.calibrating` → `.good`; baseline captured on the transition (preserve
   existing behaviour — must still pass).
3. Re-enter `.calibrating` then `.good` at a new pose → baseline re-armed to the
   new rest.
**Implement:** establish the rest baseline on the first stable pose if no
calibrating transition has armed it (e.g. capture on first non-calibrating frame
after tracking is `.good`), keeping the existing transition-based capture as the
primary path. Pitch/roll expressed relative to that baseline.
**Done-criteria:** new tests green; existing ViewModel tests still green; full
suite + PostureLogic green. Commit:
`fix: establish posture rest baseline even without a calibrating frame`.

### Step 2 — Head yaw from head keypoints (TDD)
**Objective:** head yaw reflects actual head turn, not shoulder rotation.
**TDD (RED first):** add tests feeding synthetic nose/ear keypoint geometry →
expected yaw degrees (nose offset from ear-midpoint ÷ ear separation, ×
amplification, cap ±90°). Assert that pure shoulder twist with a forward-facing
head yields ~0° head yaw (the current bug yields non-zero). **RED**.
**Implement:** source `headYawDegrees` from the keypoint geometry per the design
doc. If nose/ear keypoints are not exposed to the ViewModel, record the blocker
in `progress.md` and implement the closest head-derived alternative, noting the
substitution. Do not add new detection logic — consume existing keypoints.
**Done-criteria:** yaw tests green; forward-head-with-shoulder-twist → ~0° yaw;
full suite + PostureLogic green. Commit:
`fix: derive head yaw from head keypoints instead of shoulder twist`.

### Step 3 — Axis-direction lock (TDD)
**Objective:** freeze the correct sign/channel for each movement so Stage 1b
tuning can't silently invert an axis.
**TDD:** add direction assertions (via the pure `PostureVisualizationBinding`
resolver where possible, so values are exact): lean left → head X negative; lean
right → positive; shoulder twist CW → disc yaw correct sign; chin down → pitch
correct sign; head tilt → roll correct sign. Mirror-mode flips only the intended
channels.
**Done-criteria:** direction tests green; full suite + PostureLogic green.
Commit: `test: lock posture axis directions against regressions`.

### Step 4 — Full-suite green + finalize
**Objective:** ship-ready correctness; emit the completion promise.
**Guidance:** run the full app suite + `swift test --package-path PostureLogic`;
zero regressions. Confirm Steps 0–3 are `[x]`. Update `progress.md` final summary.
**Done-criteria:** everything green; **emit `LOOP_COMPLETE`**. Commit:
`chore: finalize posture correctness fixes`. The loop ends here.

### Step 5 — MANUAL (Stage 1b, not a loop task)
On-device by-eye tuning of Mapping amplifications/caps via the raw↔mapped HUD,
then record the 60s demo (calibration → good → slouch → recovery) per the
2026-05-17 design doc's "Demo Recording Notes". Human + live camera — out of
scope for the loop, listed so it isn't lost.

---

## Constraints (every iteration)
- Never work on `main`; always `feature/posture-correctness`.
- Do **not** modify pose-*detection* logic or public APIs (repo anti-goal) — this
  stage only re-maps existing signals in the ViewModel/Binding.
- One step per iteration; commit before stopping; all pre-existing tests stay green.
- **Never** run `ralph emit` or emit `build.done`/`build.blocked`/status/evidence
  — they trip the stale-loop guard. Progress = commit + tick + `progress.md` note.
- Emit `LOOP_COMPLETE` only after Step 4. Never attempt Step 5.
