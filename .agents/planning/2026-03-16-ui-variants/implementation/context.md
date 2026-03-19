# Implementation Context: Posture Metrics UI Variants

## Source Type
PDD (Planning Design Document) directory at `.agents/planning/2026-03-16-ui-variants/`

## Original Request Summary
Build 60 unique SwiftUI variant views for displaying posture monitoring data, within an interactive showcase. The project includes: a shared data layer, mock/live data sources, a showcase navigation shell, shared visual utilities, and the 60 individual variant implementations organized into batches.

## Repo Patterns & Structure

### Project Layout
- **Main iOS app:** `Quant/` — Swift source files, views, services, models
- **PostureLogic package:** `PostureLogic/` — SPM package (Swift 5.9, iOS 17+) containing pipeline, models, engines, services
- **Tests:** `QuantTests/` (app unit tests), `PostureLogic/Tests/PostureLogicTests/` (package tests)
- **Xcode project:** `Quant.xcodeproj/`

### Key Existing Types (in PostureLogic)
- `RawMetrics` — struct with: timestamp, forwardCreep, headDrop, shoulderRounding, lateralLean, twist, movementLevel, headMovementPattern
- `PostureState` — enum: absent, calibrating, good, drifting(since:), bad(since:). Has `durationInCurrentState` computed property.
- `NudgeDecision` — enum: none, pending(reason:timeRemaining:), fire(reason:), suppressed(reason:)
- `PostureThresholds` — struct with threshold properties: forwardCreepThreshold, headDropThreshold, shoulderRoundingThreshold, sideLeanThreshold, twistThreshold, slouchDurationBeforeNudge, etc.
- `TrackingQuality` — enum: lost, degraded, good (Comparable)

### Key Existing App Types (in Quant/)
- `AppModel` (`@MainActor ObservableObject`) — publishes: `latestMetrics: RawMetrics?`, `postureState: PostureState`, `nudgeDecision: NudgeDecision`, `trackingQuality: TrackingQuality`. Has computed `postureThresholds: PostureThresholds`.

### Patterns
- SwiftUI + Combine for reactive data flow
- `@MainActor` on observable classes
- PostureLogic is a pure Swift package (no SwiftUI dependency)
- New PostureUI types go in `Quant/` app target (they import SwiftUI for the observer, but data models are pure Swift importing only PostureLogic)
- Tests for app types go in `QuantTests/`

## Integration Points
- New data layer types import `PostureLogic` for `RawMetrics`, `PostureState`, `NudgeDecision`, `PostureThresholds`, `TrackingQuality`
- `PostureDisplayData` and model types are pure Swift (no SwiftUI import) — unit testable
- `PostureDisplayObserver` imports SwiftUI for `@Published`/`ObservableObject`
- `LivePostureDataSource` (Step 3) will wrap `AppModel`
- All variant views read `PostureDisplayObserver` via `@EnvironmentObject`

## Acceptance Criteria (Steps 11–16)
- **Step 11**: Metal shader file (`PostureShaders.metal`), `MetalShaderBridge.swift`, wave distortion + noise color effect shaders, SwiftUI View extensions, fallback handling
- **Step 12**: SceneKit integration (`SceneKitViewBridge.swift`, `PostureSceneBuilder.swift`), 3D body model with metric-driven deformation
- **Step 13**: Variants 41–46 (Organic/Nature) — Wilting Plant, Tree of Life, Water Surface, Terrain Map, Weather System, Bioluminescence
- **Step 14**: Variants 47–54 (Gamified) — Neon Pulse, Health Bar, XP Level Ring, Pixel Art Body, Achievement Shields, Boss Health Bar, Rhythm Game, Tower Defense
- **Step 15**: Variants 55–60 (Architectural) — Blueprint Grid, Load Diagram, Circuit Board, Structural Frame, Isometric City, Construction Progress
- **Step 16**: Accessibility (VoiceOver, reduce motion), performance profiling, visual polish, variant thumbnails
- All 60 variants registered in `VariantRegistry` with correct IDs, names, categories
- All tests pass in `QuantTests/` target

## Constraints
- iOS 17+ deployment target
- No third-party dependencies for data layer
- Pure Swift for data models (import PostureLogic only)
- Tests must run without UI dependencies

## Design Documents
- Detailed design: `.agents/planning/2026-03-16-ui-variants/design/detailed-design.md`
- Variant catalogs: `variant-catalog-1.md` (1–20), `variant-catalog-2.md` (21–40), `variant-catalog-3.md` (41–60)
- Implementation plan: `.agents/planning/2026-03-16-ui-variants/implementation/plan.md`
