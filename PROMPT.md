# Posture Metrics UI Variants — Implementation

Follow the implementation plan at `.agents/planning/2026-03-16-ui-variants/implementation/plan.md`.

Check whether tasks have already been completed and committed, if they are done but not marked complete, mark them as complete and commit. Follow the implementation guidance and test requirements in the plan.

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
- Emit LOOP_COMPLETE after Step 6 is finished (all 6 Score-Centric variants + registry update closed). Do NOT proceed to Step 7.
