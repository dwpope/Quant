# Agent Memory - SwiftUI Variants

## Project Structure
- Variant views live in `/Quant/Views/Showcase/Variants/<Category>/VariantNNView.swift`
- ShaderAmbient category: Variants 47-54 (possibly more)
- Shared components in `/Quant/PostureUI/` and `/Quant/Views/Showcase/`
- Metal shaders bridged via `/Quant/Views/Showcase/Shaders/MetalShaderBridge.swift`

## Swift Compiler Type-Check Pitfalls
- `(0..<n).map { i in ... }` inside computed properties can trigger "unable to type-check" errors. Use explicit `for` loops with `var result: [T] = []` instead.
- Mixing CGFloat/Double in arithmetic inside Canvas closures causes "ambiguous use of operator" errors. Pre-compute values with explicit type annotations before the closure, or annotate intermediate `let` bindings.
- Canvas closures that do too much inline math (e.g., `center.x + radius * cos(angle)`) should use pre-computed structs passed in from outside the closure.
- Keep view builder function bodies under ~25 lines; break into helper functions aggressively.

## Build Target
- Build with: `xcodebuild build -scheme Quant -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'`
- iOS 26.x simulators are available (iPhone 17 Pro, iPhone Air, etc.)

## Variant File Pattern
Every variant follows: import SwiftUI+PostureLogic, struct with @EnvironmentObject observer + @State showingSettings, isAbsent computed property, body with GeometryReader>ZStack>AbsenceOverlay>SettingsGearButton>.sheet>.animation, three #Preview blocks (Good/Alert/Absent).
