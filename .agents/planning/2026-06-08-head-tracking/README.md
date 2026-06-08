# 3-Axis Head Tracking (2026-06-08)

Sub-stage of the Aware roadmap's **Stage 1 (posture)**. Follow-on to
`../2026-06-01-posture-correctness/`.

## Why this exists
The posture visualization's "head" pitch/yaw/roll are **body-skeleton proxies**,
not head tracking:
- yaw ← shoulder twist · pitch ← head depth offset · roll ← shoulder-line angle

Stage 1a accepted that substitution on purpose (its anti-goal forbade touching
public APIs). This stage removes the proxy by exposing the head geometry that
**Vision already detects every frame** (`nose, eyes, ears`) but that
`PoseDepthFusion` currently collapses into one point and discards.

## Key decision: no ARFaceAnchor
The subject is filmed by the **rear** camera (`ARWorldTrackingConfiguration`).
`ARFaceAnchor` requires the **front** TrueDepth camera and tracks a face *behind*
the device — wrong subject. Real head angles come from the rear-image facial
keypoints, optionally fused with the existing LiDAR `sceneDepth` for true pitch.

## Approach (one-liner)
Compute pitch/yaw/roll in `PoseDepthFusion` from `nose/eye/ear` keypoints → add
three fields to `PoseSample` → they ride the existing `latestSample` publisher to
`AppModel` → the ViewModel swaps its proxies for the real fields. No new camera
config, no new ARKit API, no new publisher.

## Estimate
MVP (raw head angles visible in UI, no new judging): ~5 files, ~150–200 LOC incl.
tests. The only genuinely new code is ~50 lines of trigonometry in
`PoseDepthFusion`; the rest is additive field plumbing.

Head-posture *judging* + nudges is a deliberate follow-on (plan Step 8).

## Files
- `implementation/plan.md` — authoritative execution order + done-criteria (Ralph-runnable)
- `implementation/progress.md` — mutable cold-start loop state

## Intent reference
`../2026-06-01-aware-roadmap/roadmap.md` (Stage 1).
