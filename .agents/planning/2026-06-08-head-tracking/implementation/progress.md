# Head Tracking — Progress (mutable loop state)

**Single source of truth for "what's done" = this file + the `plan.md` checklist
+ `git log`.** Cold-start iterations read this first.

## Current Step
Step 0 — not started.

## Type Map
*(Populate in Step 0 — verified names/fields, do not assume.)*
- `PoseObservation` head-keypoint case names: _TBD (expected `nose, leftEye, rightEye, leftEar, rightEar`)_
- `PoseDepthFusion` helpers (`keypoint`, `unproject`, `findDepth`, `resolveHeadPosition`): _TBD (signatures + line refs)_
- `PoseSample` init signature + every `PoseSample(` call site: _TBD_
- ViewModel proxy lines to replace (`p.shoulderTwist`/`p.headForwardOffset`/shoulder-line roll): _TBD (expected ~204–217)_
- `latestSample` path Pipeline → AppModel (confirm no new publisher needed): _TBD_
- Working simulator destination: _TBD_

## Verification Notes
*(Append one per completed step: tests run, build result, commit hash,
decisions, sign conventions chosen, any regressions.)*

## Known blockers
*(none yet)*
