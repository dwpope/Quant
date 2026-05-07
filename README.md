# Quant

An iOS app that uses the device camera and Apple's Vision framework to monitor posture in real-time. Built with SwiftUI and targeting iOS 17+.

## What It Does

Quant sits on your desk (phone on a stand) and watches your upper body through the front camera. It tracks:

- **Posture metrics** — shoulder tilt, forward lean, and lateral offset, compared against a personal baseline you calibrate at the start
- **Sip detection** — recognises the head-tilt motion of drinking water so it can track hydration over time
- **Absence detection** — notices when you leave and return, with dwell timers and recalibration prompts
- **Thermal adaptation** — adjusts frame rate and feature usage based on device temperature so the phone doesn't overheat during long sessions

## Architecture

The core logic lives in `PostureLogic`, a standalone Swift package with no UIKit/SwiftUI dependencies:

```
PostureLogic/
├── Engines/        # PostureEngine, MetricsEngine, SipDetector, NudgeEngine, etc.
├── Models/         # PostureState, Baseline, SipEvent, InputFrame, etc.
├── Protocols/      # PoseProvider, DepthService, ThermalMonitor, etc.
├── Fusion/         # Pose + depth data merging
├── Calibration/    # Baseline capture and validation
└── Testing/        # MockPoseProvider, MockThermalMonitor, TestScenarios
```

The app layer (`Quant/`) handles camera access, SwiftUI views, and an `AppModel` that wires everything together.

### UI Variant Showcase

The app includes 60 different UI designs for displaying posture metrics, organised into families: score-centric, dashboard, minimal/typographic, abstract geometric, 3D instrument, organic/nature, shader-driven, gamified, and architectural. These live in `Quant/Views/Showcase/Variants/`.

## Supported Operating Range

- **Distance:** 0.5 – 1.5 m (optimal 0.7 – 1.0 m)
- **Horizontal angle:** ±15° from centre
- **Lighting:** ambient light, avoid strong backlight

## Running

Open `Quant.xcodeproj` in Xcode 16+ and run on a physical device or simulator. The PostureLogic package resolves automatically.

### Tests

```bash
# PostureLogic unit tests (350 tests, pure Swift, no simulator needed)
cd PostureLogic && swift test

# Full Xcode test suite (requires simulator)
xcodebuild test -project Quant.xcodeproj -scheme QuantNoWatchTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## CI / Orchestration

The repo uses [Ralph Orchestrator](https://github.com/mikeyobrien/ralph-orchestrator) for agentic CI/CD. Configuration is in `ralph.yml`; the current task prompt is in `PROMPT.md`.

## Project Structure

| Path | Purpose |
|---|---|
| `PostureLogic/` | Standalone Swift package — all detection and metrics logic |
| `Quant/` | iOS app target — SwiftUI views, camera, AppModel |
| `QuantTests/` | Xcode test target |
| `QuantWatch Watch App/` | watchOS companion (placeholder) |
| `.agents/planning/` | Feature plans and design docs |
| `SUPPORTED_RANGE.md` | Camera placement requirements |

## License

Private repository.
