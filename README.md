# Quant

A real-time posture monitoring iOS app that uses the front camera and Apple's Vision framework to track body positioning, detect drinking gestures for hydration logging, and nudge you when you slouch — all processed on-device with no server dependency.

Built with SwiftUI, ARKit, and Vision. Targeting iOS 17+.

## What It Does

Quant sits on your desk (phone on a stand) and watches your upper body through the front camera. It continuously compares your posture against a personal baseline you calibrate at the start of each session.

**Posture monitoring** — Tracks five metrics (forward lean, head drop, shoulder rounding, lateral lean, twist) with a traffic-light state machine that gives you a grace period to self-correct before nudging. Nudges are gated by cooldown timers, hourly caps, and acknowledgement detection to avoid nagging.

**Sip detection** — A three-signal scoring system (proximity, velocity profile, duration band) detects drinking gestures from upper-body pose data. Proximity is normalised by shoulder width for scale invariance; velocity distinguishes the lift-pause-lower pattern of drinking from static gestures like chin-resting.

**Training mode** — A sidecar data-collection pipeline captures labeled training data (feature vectors + 3s pose windows) for a future CreateML gesture classifier, with a timed annotation UI and JSONL/JSON export. The entire training path is additive — removing it touches zero production code.

**Thermal adaptation** — Frame rate scales dynamically with device temperature (10 → 5 → 2 FPS), with full pause at critical thermal state, so the phone doesn't overheat during long sessions.

## Architecture

```
PostureLogic/          ← Pure Swift Package, no UIKit/SwiftUI/ARKit
├── Pipeline.swift     ← Central orchestrator: frame → pose → metrics → state → nudge
├── Engines/           ← PostureEngine, NudgeEngine, SipDetector, MetricsEngine, etc.
├── Models/            ← Value types: PoseSample, Baseline, SipEvent, PostureState
├── Protocols/         ← PoseProvider, DebugDumpable, engine protocols
├── Services/          ← PoseService, DepthService, PoseDepthFusion, ThermalMonitor
└── Testing/           ← MockPoseProvider, TestScenarios (shipped in-package)

Quant/                 ← iOS app target
├── AppModel.swift     ← ViewModel hub: wires Pipeline to camera, UI, persistence
├── Views/             ← CalibrationView, DebugOverlay, SipTimeline, etc.
├── Views/Showcase/    ← 60 UI variant designs (Metal shaders, SceneKit, SwiftUI)
├── Services/          ← ARSession, FrontCamera, WatchConnectivity, AudioFeedback
└── Models/            ← SipStore, SipTrainingStore, SipLabelQueue

QuantWatch Watch App/  ← watchOS companion
```

**40,000+ lines of Swift** across 237 files, with **585 tests** across 63 test files.

## Technical Decisions

### Pure-logic Swift Package separation
All detection logic lives in `PostureLogic` — a Swift package with zero platform dependencies. The entire pipeline (state machines, signal processing, threshold evaluation) can be tested with `swift test` on macOS in seconds, no simulator required. This means CI runs are fast and every engine is independently testable with mock injection.

### Protocol-oriented engine design
Each engine conforms to a protocol (e.g. `PostureEngineProtocol`, `NudgeEngineProtocol`) and implements `DebugDumpable`, which exposes a `debugState: [String: Any]` dictionary for runtime inspection. This enables mock injection in tests and powers the debug overlay without coupling to engine internals.

### Three-signal sip detection with training-mode data collection
Rather than a simple proximity threshold (too many false positives from chin-resting, phone calls, adjusting glasses), the `SipDetector` scores three independent signals and requires a combined score above threshold. The training-mode architecture runs a completely separate data path — `SipTrainingBuffer` captures rolling pose windows, `SipTrainingRecord` stores detector scores at confirmation time, and `SipTrainingStore` persists to separate per-day files. This collects ground-truth data for a future ML classifier without polluting the production model.

### Traffic-light state machine with hysteresis
The `PostureEngine` transitions through good → drifting → bad states using time accumulation, not instantaneous threshold crossing. The drifting state acts as a buffer (default 60s) so the system doesn't nag on momentary slouches. Accumulated drift time freezes when tracking quality drops, preventing false alarms from camera occlusion.

### Combine fan-out for observation distribution
`Pipeline` publishes pose observations via a `PassthroughSubject`. Multiple consumers (SipDetector, SipTrainingBuffer, future ML models) subscribe independently — the Pipeline doesn't import or reference any of them. `AppModel` wires the subscriptions, keeping separation of concerns clean.

### Frame throttling with thermal adaptation
ARKit delivers 60 FPS but Vision body pose detection is expensive. A timestamp-based throttle in `Pipeline` runs detection at ~10 FPS, dynamically adjusted by `ThermalMonitor` (down to 2 FPS at serious thermal state, full pause at critical). This prevents ARFrame retention from causing memory spikes.

### Tracking quality with temporal smoothing
A 3-frame majority-vote window with hysteresis thresholds prevents single-frame Vision detection flickers from triggering false absence detection or freezing the posture engine. At 10 FPS, this adds ~300ms of latency — imperceptible in practice.

## Running

Open `Quant.xcodeproj` in Xcode 16+ and run on a physical device. The PostureLogic package resolves automatically.

### Tests

```bash
# PostureLogic unit tests (pure Swift, no simulator)
cd PostureLogic && swift test

# Full Xcode test suite (requires iOS simulator)
xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Test coverage includes unit tests for each engine in isolation, integration tests wiring multiple engines via Pipeline, golden recording replay tests for deterministic output verification, long-run stability tests, Codable migration tests for backward compatibility, and batch instantiation tests for all 60 UI variants.

## Supported Operating Range

- **Distance:** 0.5 – 1.5 m (optimal 0.7 – 1.0 m)
- **Horizontal angle:** ±15° from centre
- **Lighting:** ambient light, avoid strong backlight

## License

Private repository.
