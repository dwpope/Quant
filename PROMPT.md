# Posture Metrics UI Variants — Implementation

Follow the implementation plan at `.agents/planning/2026-03-16-ui-variants/implementation/plan.md`.

Check whether tasks have already been completed and committed, if they are done but not marked complete, mark them as complete and commit. Follow the implementation guidance and test requirements in the plan.

## Progress

Steps 1–7 are complete (shared data layer, mock/live data sources, showcase shell, visual utilities, Score-Centric variants 1–6, Dashboard variants 7–12).

## Scope

Complete Steps 8, 9, and 10:

- **Step 8** — Variant batch C: Minimal / Typographic (Variants 13–20)
- **Step 9** — Variant batch D: Abstract Geometric (Variants 21–28)
- **Step 10** — Variant batch E: 3D / Body / Instrument (Variants 29–40)

## Design documents

- `.agents/planning/2026-03-16-ui-variants/design/detailed-design.md`
- `.agents/planning/2026-03-16-ui-variants/design/variant-catalog-1.md` (Variants 1–20)
- `.agents/planning/2026-03-16-ui-variants/design/variant-catalog-2.md` (Variants 21–40)
- `.agents/planning/2026-03-16-ui-variants/design/variant-catalog-3.md` (Variants 41–60)

## Process

1. Read the plan step thoroughly before starting implementation
2. Read the relevant variant catalog entries for the variants in that step
3. Implement the code following the plan's guidance
4. Build the project: `xcodebuild build -scheme Quant -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
5. Run tests: `swift test --package-path PostureLogic`
6. Commit with a descriptive message
7. Update the plan checklist to mark the step complete

## Constraints

- Follow the design documents faithfully
- All existing tests must continue to pass
- Do NOT refactor code unrelated to the current step
- Preserve backwards compatibility of all public APIs
- Emit LOOP_COMPLETE after Step 10 is finished (all 3D / Body / Instrument variants 29–40 + registry update). Do NOT proceed to Step 11.
