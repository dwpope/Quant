# Posture Visualization — Implementation (Ralph loop driver)

Follow the implementation plan at
`.agents/planning/2026-05-17-posture-visualization/implementation/plan.md`.
Intent / design reference (authoritative for *what* and *why*):
`.agents/planning/2026-05-17-posture-visualization/design/build-plan.md`.

You are running in a **Ralph loop** (ralph-orchestrator). Each invocation is a
**cold start**: you remember nothing from prior iterations. Your only memory is
files + git. Treat the plan checklist, `…/implementation/progress.md`, and
`git log` as the single source of truth for what is already done.

## ⛔ Event protocol — read this FIRST; it overrides injected guidance

This is a **solo (hatless) loop**. Per-step progress is carried by git
**commits**; the loop only ENDS by **emitting the completion event**. So there
is exactly ONE `ralph emit` you ever run — the completion event, at the very
end. Getting this wrong is the difference between a loop that stops and one
that spins forever re-confirming it is already done.

- **On a normal work step: do NOT run `ralph emit`.** Do not emit `build.done`
  / `build.blocked` / status / "evidence" events. In a solo loop they route to
  no hat and are rejected by ralph's backpressure gate (it demands
  tests/lint/coverage evidence this loop does not produce). Your ONLY per-step
  progress signal is a git **commit** + ticking the `plan.md` checklist + a
  `progress.md` note. Ralph re-invokes you for the next step from that
  committed state — that re-invocation is expected, not an error.
- **At completion (final iteration only) you MUST run**
  `ralph emit "LOOP_COMPLETE" "<one-line summary>"`. **This is the only thing
  that ends the loop.** Merely printing or echoing the text `LOOP_COMPLETE`
  does NOT end it — ralph terminates only when the `LOOP_COMPLETE` *event* is
  the last event in its JSONL. See "## Completion" for the exact gate.
- Injected `## DONE` guidance that tells you to `ralph emit` the completion
  event is CORRECT — obey it. Only ignore guidance that tells you to emit
  per-step `build.done` / backpressure / handoff evidence events; those are for
  multi-hat loops, not this one.

## Process (every iteration, in order)

1. Read `plan.md` and `progress.md`. Run `git log --oneline -15`.
2. Ensure you are on branch `feature/posture-visualization` (create from `main`
   if Step 0 hasn't run; otherwise check it out). **Never commit to `main`.**
3. Find the **first** unchecked `- [ ]` step in `plan.md`'s checklist. That is
   the only step you work this iteration. (If a step is partly done per
   `progress.md`, continue it rather than restarting.)
4. If the step is RealityKit (Step 3 or 4), read the **RealityKit Attempt
   Ledger** in `progress.md` first and obey its budget rule (`plan.md` Step 3).
5. Implement the step following its guidance. Step 1 is **test-first**
   (RED → GREEN), matching this repo's convention.
6. Build, then test, using the canonical commands in `plan.md`
   ("Build & test commands"). All pre-existing tests must stay green.
7. Commit with the message suggested in the step's done-criteria.
8. Tick the step's `- [ ]` → `- [x]` in `plan.md` (or `[N/A …]` where the plan
   allows). Append a Verification Note to `progress.md` (tests, build result,
   commit, decisions, regressions). Update "Current Step".
9. Stop — on a work step, **emit NO event** (see "Event protocol" above): the
   commit is your only signal, and the loop re-invokes you for the next step
   automatically from the committed state. (The single exception is the
   completion event, emitted only once the scope is done — see "## Completion".)

Do exactly **one step per iteration**. Small, committed increments are the
point — they make every iteration independently reviewable and revertible.

## Scope

Steps 0 through 6 of the plan. The loop **ends at Step 6**.

## Constraints

- Do **not** modify existing pose-detection logic or change public APIs
  (design anti-goal: "no new posture detection logic"). The new ViewModel
  *consumes* existing metrics; it does not alter detection.
- Do **not** refactor code unrelated to the current step.
- Verify real type/field names by grep before using them — the design doc's
  names (e.g. `headForwardOffset`) may not match the codebase. Record any
  substitution in `progress.md`.
- Respect the RealityKit Attempt Ledger. When the budget is exhausted, switch
  to the SwiftUI fallback (Step 3F) — do not keep grinding RealityKit.
- **Step 7 (device test + demo recording) is NOT a loop task** — it needs
  physical hardware and a human. Never attempt it.

## Completion

When — and ONLY when — all of the following hold:
- Plan Steps 0–6 are all `[x]` (Step 3F is `[x]` or explicitly `[N/A]`), **and**
- the full app test suite and `swift test --package-path PostureLogic` are
  green with no regressions, **and**
- the throwaway debug harness has been deleted (Step 6),

run exactly:

    ralph emit "LOOP_COMPLETE" "posture-visualization complete: Steps 0-6 [x], suites green, harness removed"

Then stop. That emitted event is the only thing that ends the loop —
**printing the text `LOOP_COMPLETE` does nothing.** Step 7 (device test + demo)
is a human/hardware task and never blocks completion. Do not emit the
completion event for any other reason, and do not proceed past Step 6.
