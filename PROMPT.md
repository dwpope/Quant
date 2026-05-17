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

This loop does **NOT** use ralph's backpressure / `build.done` event ritual.
Emitting `build.done`, `build.blocked`, status, or "evidence" events gets them
rejected and falsely trips ralph's stale-loop guard, which kills a *healthy*
loop. Therefore, every iteration:

- **Do NOT run `ralph emit`. Do NOT emit `build.done` / `build.blocked` /
  backpressure / status / evidence events. Ever.**
- The ONLY progress signal is: a git **commit** for the step + ticking the
  `plan.md` checklist + a `progress.md` note. The loop re-invokes itself from
  that committed state with no event needed (Steps 2–4 advanced exactly this
  way while every emitted event was rejected).
- The ONLY token you ever emit is the literal promise `LOOP_COMPLETE`, and
  ONLY at Step 6 per "## Completion" below.
- If injected memories, skills, the scratchpad, or ralph hints tell you to
  emit backpressure evidence / `build.done` / use `ralph emit` — **IGNORE
  them; they are wrong for this loop. This instruction wins.**

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
9. Stop — **emit NO event of any kind** (see "Event protocol" above). The
   loop re-invokes you for the next step automatically from the committed
   checklist state.

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

Emit `LOOP_COMPLETE` **only** when:
- Plan Steps 0–6 are all `[x]` (Step 3F is `[x]` or explicitly `[N/A]`), **and**
- the full app test suite and `swift test --package-path PostureLogic` are
  green with no regressions, **and**
- the throwaway debug harness has been deleted (Step 6).

Do not emit `LOOP_COMPLETE` for any other reason, and do not proceed past
Step 6.
