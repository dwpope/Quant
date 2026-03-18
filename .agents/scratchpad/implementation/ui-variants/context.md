# Implementation Context: Posture Metrics UI Variants

## Source
PDD directory at `.agents/planning/2026-03-16-ui-variants/`

## Summary
Implementing 60 posture monitoring UI variant views for a showcase feature in the Quant iOS app. Each variant displays real-time posture data (`PostureDisplayData`) through a unique visual metaphor. The variants are grouped into categories (Score-Centric, Dashboard, Minimal, etc.) and implemented in batches.

## Repo Patterns
- Swift/SwiftUI iOS app with `PostureLogic` Swift package for core logic
- PBXFileSystemSynchronizedRootGroup — new files auto-discovered by Xcode (no pbxproj edits)
- Variant views live in `Quant/Views/Showcase/Variants/{CategoryName}/`
- Shared data types in `Quant/PostureUI/`
- Tests in `QuantTests/`
- Build: `xcodebuild build -scheme Quant -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet`
- Unit tests: `swift test --package-path PostureLogic`
- Scheme for unit tests: `QuantNoWatchTests`

## Key Dependencies
- `PostureDisplayData` — canonical data model with metrics, state, nudge decision
- `PostureDisplayObserver` — `@EnvironmentObject` that all variant views read
- `PostureVisualStyle` — shared color/label utilities
- `PostureAnimations` — shared animation constants
- `MetricRatioBar`, `NudgeCountdownLabel`, `SettingsGearButton`, `PostureStateAmbientBackground`, `AbsenceOverlay` — reusable sub-views
- `VariantRegistry` — static array of all 60 variant descriptors; updated per batch
- `MockPostureDataSource` — drives simulation in showcase

## Acceptance Criteria (per variant)
1. View implements real-time mode (`.good` state with all 5 metrics)
2. View implements alert mode (`.drifting`/`.bad` with animated transition, worst offender focus, nudge countdown)
3. View handles `.absent` and `.calibrating` states with neutral visual
4. View includes settings gear entry point
5. View adapts to portrait and landscape orientations
6. View supports light and dark mode
7. Three `#Preview` blocks: good, alert, absent
8. Registered in `VariantRegistry` replacing placeholder

## Constraints
- Follow design documents faithfully (variant-catalog-1.md for Variants 1-20)
- All existing tests must pass
- No refactoring of unrelated code
- Preserve backwards compatibility of all public APIs
