# Posture Metrics UI Variants — Implementation

Follow the implementation plan at `.agents/planning/2026-03-16-ui-variants/implementation/plan.md`.

Check whether tasks have already been completed and committed, if they are done but not marked complete, mark them as complete and commit. Follow the implementation guidance and test requirements in the plan.

## Progress

Steps 1–10 are complete:
- Steps 1–3: Shared data layer, mock data source, live data source
- Step 4: Showcase navigation shell
- Step 5: Shared visual utilities
- Steps 6–7: Score-Centric variants 1–6, Dashboard variants 7–12
- Steps 8–10: Minimal/Typographic variants 13–20, Abstract Geometric variants 21–28, 3D/Body/Instrument variants 29–40

40 of 60 variants are implemented and registered.

## Scope

Complete Steps 11 through 16:

- **Step 11** — Metal shader infrastructure and shader-driven variants (Variants 43, 47, 51–54)
- **Step 12** — SceneKit / 3D infrastructure and 3D variants
- **Step 13** — Variant batch F: Organic / Nature (Variants 41–46)
- **Step 14** — Variant batch G: Gamified (Variants 47–54)
- **Step 15** — Variant batch H: Architectural / Structural (Variants 55–60)
- **Step 16** — Polish, accessibility, performance

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
- Emit LOOP_COMPLETE after Step 16 is finished (all 60 variants implemented + polish/accessibility/performance pass). Do NOT proceed beyond Step 16.
