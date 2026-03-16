# Idea Honing — Requirements Clarification

## Q1: What is the core value loop?

**A:** Camera → Keypoints → Metrics → Posture State Machine → Nudge → Watch Tap. The app detects sustained bad posture and alerts the user via audio and Apple Watch haptic.

## Q2: Should we prioritize detection rate or false positive avoidance?

**A:** Precision over recall. False alarms are more annoying than missed slouches — users will lose trust. Better to miss a slouch than fire a false alarm.

## Q3: What constitutes "bad posture" worth nudging about?

**A:** Only sustained bad posture (≥5 minutes by default). Brief posture shifts are normal. Five metrics contribute: forward creep, head drop, shoulder rounding, lateral lean, and twist. Any single metric exceeding its threshold starts the drifting→bad timer.

## Q4: Should the app use a "shadow mode" (observe silently, report later)?

**A:** No — user rejected shadow mode. Immediate feedback preferred over delayed batch reports.

## Q5: What feedback modalities should be used for nudges?

**A:** Dual-channel: programmatic audio tone (880Hz sine wave, 0.3 volume, ambient category) on iPhone + haptic tap on Apple Watch via WatchConnectivity. Dual delivery: `sendMessage` for real-time, `transferUserInfo` as fallback.

## Q6: How should baseline/calibration work?

**A:** Guided calibration: 3-second countdown, then 5 seconds of sampling (≥30 good frames). Validates positional and angular variance. Computes median of collected samples. Baseline stored with timestamp. Recalibration triggered: on app launch, after >5 min absence, manual button, or >30% shoulder position shift.

## Q7: What cameras should be supported?

**A:** Both rear (ARKit + LiDAR depth) and front (AVFoundation, 2D only). Switchable at runtime with UserDefaults persistence. Pipeline stays attached once via `SwitchablePoseProvider`.

## Q8: What is the supported operating range?

**A:**
- Distance: 0.5m–1.5m (optimal 0.7–1.0m)
- Horizontal: ±15° from center
- Vertical: 0°–30° downward angle
- Good ambient light, no strong backlight
- Phone on stable tripod/stand, upper body visible from shoulders up

## Q9: What are the success criteria?

**A:** Against golden recordings with ground-truth tags:
- Detection rate: ≥70% of slouch episodes (≥5 min sustained) trigger a nudge
- False positive rate: <3% of "good posture" time incorrectly flagged (priority metric)
- Task mode accuracy: ≥80% of reading/typing segments correctly classified
- Recovery detection: State returns to Good within 5 seconds of correction

During live 60-minute sessions:
- ≤2 nudges per hour during normal work
- Zero nudges during sustained good posture

## Q10: What are the performance budgets?

**A:**
- CPU: Average <15% on high-performance cores
- Battery: <5% drain per hour
- Memory: <100MB steady state
- Thermal: Must not trigger `serious` state during standard 1-hour session
- Vision: capped at 10 FPS; Depth: capped at 15 FPS

## Q11: What should happen when tracking quality is uncertain?

**A:** Never judge posture. Only count time toward slouch detection when confidence is high. Pause slouch timer when tracking is degraded/lost. Don't change posture state during low-quality periods.

## Q12: Should there be task mode classification?

**A:** Yes — reading, typing, meeting, stretching, unknown. Task mode adjusts posture thresholds (e.g., reading allows 1.3x more forward lean). Stretching disables posture judgement entirely. Classification based on movement patterns over a 10-second sliding window.

## Q13: What about recording and replay?

**A:** Record `PoseSample` streams to JSON for regression testing. Replay in Simulator at 1x/2x/10x speed. Golden recordings needed for: good posture (5 min), gradual slouch (10 min), reading vs typing, depth fallback scenario.

## Q14: What about an ML pivot?

**A:** Contingency plan if threshold tuning fails after 3 full days. Use recorded/tagged PoseSample streams as training features. Export to CreateML format. Swap PostureEngine implementation behind the protocol — no other changes needed.

## Q15: What are the non-goals?

**A:** Until Phase 3+:
- No "pretty" UI, onboarding, analytics dashboards, cloud sync, accounts
- No custom ML unless the explicit pivot trigger occurs
- No saving video by default
