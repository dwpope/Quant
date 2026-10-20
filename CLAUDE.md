## Cowork Bridge

Dave uses Cowork (Claude desktop app) to manage his goals across career, family, and health. This Code session is one input into that system.

At the START of every session:
- Read ~/Documents/Claude/code-status.md to see priorities across all projects
- Read ~/Documents/Claude/plan.json for goal context
- Check this project's section in code-status.md for known bugs and next steps

At the END of every session:
- Update this project's section in ~/Documents/Claude/code-status.md with current state
- Append a session log entry with what was done
- Update "The One Thing" if this project's priorities changed
- If any plan.json task statuses changed, update them

The morning brief reads code-status.md at 6AM every weekday. Whatever you write there is what Dave sees as his code priorities for the day.

## Active project plan
Read ~/Documents/Claude/jev-integration-plan.md for the current Jev integration roadmap. Check which step is next before starting work.

**This is the next work on this project, decided 2026-09-22.** It takes precedence over the Aware backlog in code-status.md and over any other candidate: when a session is unsure what to do next, the answer is the next incomplete step in jev-integration-plan.md. All three systems agree by design — plan.json's `surfaced_focus` is `career-jev-6-real-use-hour` (the hour of real use the plan names as next), and code-status.md's "The One Thing" is that same hour. When the plan's next step changes, move both with it. If they ever disagree again, this section wins and the others should be corrected to match. (Last re-aligned 2026-10-20 at Dave's choice: the 10-06 weekly review had moved the focus to `career-linkedin`, which stays queued, and the 10-20 morning run had picked FamilyMedicalHistory.)

When ALL steps in jev-integration-plan.md are marked complete, remove this "Active project plan" section from CLAUDE.md automatically — the project is done and this reference should not persist. Leave the Cowork Bridge section above.
