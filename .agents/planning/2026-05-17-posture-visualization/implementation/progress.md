# Progress: Posture Visualization

> Mutable loop state. Every iteration reads this first and appends to it before
> stopping. This file + `plan.md`'s checklist + `git log` are the **only**
> memory that survives a cold iteration.

## Current Step

**Step 0 — Branch + folder scaffolding** _(not started)_

## Working environment (fill in during Step 0, reuse thereafter)

- Verified simulator destination: _(TBD — e.g. `platform=iOS Simulator,id=…`)_
- Branch confirmed: _(TBD)_

## Type Map (populate in Step 0 — authoritative names from the actual codebase)

| Concept | Real type / field | File:line | Notes |
|---|---|---|---|
| Raw posture metrics | _(TBD: `RawMetrics` fields)_ | | design doc says `headForwardOffset` — confirm/substitute |
| Posture state enum | _(TBD: `PostureState` cases)_ | | which case = calibrating? |
| Tracking quality | _(TBD)_ | | range → opacity mapping |
| AppModel publisher(s) | _(TBD)_ | | how the VM subscribes |
| Pose keypoints | _(TBD: nose/ears/eyes accessors)_ | | source for yaw/pitch/roll |

**Field substitutions made** (record any design-doc name → real-field mapping):
- _(none yet)_

## RealityKit Attempt Ledger

> See `plan.md` Step 3. Increment `attempts` by 1 each Step 3/4 iteration that
> does NOT end with both a clean scene build AND progress on the step's
> done-criteria (compiles-but-no-progress still counts). Repeated identical
> blocking error → bail immediately. At `attempts == 2` (or repeat-failure),
> abandon RealityKit → tag `wip/realitykit-vis` → switch to Step 3F.

```
attempts: 0
budget: 2
last_error_class: (none)
status: not-yet-engaged   # not-yet-engaged | in-progress | shipped | exhausted
```

Attempt log:
- _(none yet)_

## Verification Notes

_(Append one block per completed step: tests written/run, build result,
commit hash, decisions, regressions.)_

## Completed Steps

_(none yet)_
