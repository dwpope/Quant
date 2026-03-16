# Project Summary — Posture Detection App

## Directory Structure

```
.agents/planning/2026-03-08-posture-detection/
├── rough-idea.md                          # Initial concept
├── idea-honing.md                         # 15 Q&A requirements clarifications
├── research/
│   ├── architecture.md                    # Project structure, module dependencies, data flow
│   ├── technologies.md                    # ARKit, Vision, AVFoundation, WatchConnectivity, known gotchas
│   └── calibration-and-metrics.md         # Baseline calibration, metrics computation, state machine, nudge rules
├── design/
│   └── detailed-design.md                 # Standalone design document with all sections
├── implementation/
│   └── plan.md                            # 45 incremental steps with checklist
└── summary.md                             # This document
```

## Key Design Elements

- **Five-metric posture detection**: forward creep, head drop, shoulder rounding, lateral lean, twist — all as deltas from calibrated baseline
- **Precision-first approach**: 5-minute sustained bad posture before nudging; <3% false positive target
- **Dual camera support**: rear (ARKit + LiDAR depth) and front (AVFoundation 2D) with runtime switching
- **Protocol-based Swift Package**: all posture logic testable via `swift test`, swappable for ML later
- **Pipeline architecture**: PoseService → PoseDepthFusion → MetricsEngine → Smoother → PostureEngine → NudgeEngine
- **Dual nudge delivery**: audio tone (880Hz) + Apple Watch haptic via WatchConnectivity
- **Automatic mode switching**: DepthFusion ↔ TwoDOnly based on depth confidence with hysteresis

## Implementation Approach

The plan breaks down into **45 incremental steps** across 3 phases:

- **Phase 1 (Steps 1–28)**: MVP delivering camera → watch tap, plus front camera support and debug improvements. Steps 1–17 are the core MVP (all completed). Steps 18–28 add detection completeness, front camera, debug display, and twist fix.
- **Phase 2 (Steps 29–41)**: 3D depth fusion, recording/replay infrastructure, task mode classification, settings screen, setup validation.
- **Phase 3 (Steps 42–45)**: Long-run stability, thermal throttling, background mode research, Mac companion app.

Each step results in working, demoable functionality and includes test requirements alongside implementation.

## Current Status

- **Steps 1–19 completed** (MVP + detection completeness)
- **Step 28 completed** (twist fix)
- **Steps 20–27 in progress** (front camera support + debug improvements)
- **Steps 29–45 pending** (Phase 2 + Phase 3)

## Areas That May Need Further Refinement

- **2D shoulder-width thresholds for setup validation** (Step 40): exact values need empirical tuning against the supported range
- **Task mode classification accuracy** (Step 36): simple heuristic may need refinement with real data
- **Golden recording collection** (Step 34): requires dedicated on-device recording sessions
- **Background mode viability** (Step 44): iOS restrictions may limit options
- **ML pivot trigger** (Contingency): if threshold tuning fails after 3 days, CreateML classifier replaces PostureEngine behind protocol

## Next Steps

1. Review the detailed design at `design/detailed-design.md`
2. Check the implementation plan and checklist at `implementation/plan.md`
3. Continue implementation from the next unchecked step in the checklist
4. To start implementation with Ralph Loop:
   - `ralph run --config presets/pdd-to-code-assist.yml --prompt "<task>"`
   - `ralph run --config presets/spec-driven.yml --prompt "<task>"`
