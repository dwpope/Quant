# Variant Catalog 1: Variants 1-20

**Score-Centric | Dashboard / Multi-Metric | Minimal / Typographic**

---

## Shared Data Contract

Every variant receives a single `PostureDisplayData` object containing:

```swift
struct PostureDisplayData {
    let metrics: MetricRatios        // 5 values, each 0.0...1.0+ (ratio to threshold)
    let postureState: PostureState   // .good, .drifting(since:), .bad(since:)
    let nudgeDecision: NudgeDecision // .none, .pending(reason:, timeRemaining:), .fire(reason:), .suppressed(reason:)
    let worstOffender: MetricKind?   // which of the 5 metrics is highest ratio
    let overallScore: Double         // 0.0 (worst) to 1.0 (perfect), derived from metrics
}

struct MetricRatios {
    let forwardCreep: Double      // raw / forwardCreepThreshold
    let headDrop: Double          // raw / headDropThreshold
    let shoulderRounding: Double  // raw / shoulderRoundingThreshold
    let lateralLean: Double       // raw / sideLeanThreshold
    let twist: Double             // raw / twistThreshold
}

enum MetricKind: String, CaseIterable {
    case forwardCreep, headDrop, shoulderRounding, lateralLean, twist
}
```

All variants must implement:
- **Real-time mode** (`.good` state): display all 5 metrics simultaneously
- **Alert mode** (`.drifting`/`.bad` state): animated transition to worst offender focus + nudge countdown
- **Settings gear icon**: single tap target to open controls sheet
- **Orientation adaptation**: portrait and landscape layouts
- **Dark/light mode**: system-adaptive via semantic SwiftUI colors

---

## Score-Centric Variants (1-6)

These variants prioritize a single, dominant visual element that communicates overall posture quality at a glance. Individual metrics are secondary, revealed on closer inspection or during alert transitions.

---

### Variant 1: Precision Gauge

**Category:** Score-Centric

**Concept:** A large, classic speedometer-style gauge dominates the screen. A physical needle sweeps from a green "Excellent" zone on the left through yellow "Drifting" to a red "Poor" zone on the right. The metaphor is immediate -- your posture has a precise, measurable reading, like an instrument you can tune.

**Real-time mode:**
The gauge occupies the top 60% of the screen. The semicircular dial spans roughly 240 degrees with tick marks at regular intervals. The needle position maps directly to `overallScore` (1.0 = needle fully left in green, 0.0 = fully right in red). Below the gauge, five small horizontal capsule indicators are arranged in a single row, one per metric. Each capsule is a thin rounded rectangle filled proportionally to its metric ratio, colored green-to-red along the fill. Metric labels use abbreviated names (FC, HD, SR, LL, TW) in `.caption` weight below each capsule. The current numeric score (e.g., "87") is displayed in a large `.system(size: 48, weight: .bold, design: .rounded)` font at the center of the gauge arc, just above the needle pivot. The gear icon sits in the top-right corner as a 24pt SF Symbol `gearshape.fill` with `.secondary` foreground style.

**Alert mode:**
When state transitions to `.drifting`, the needle animates smoothly to the yellow zone over 0.6s using `.spring(response: 0.6, dampingFraction: 0.7)`. The gauge bezel subtly pulses with a yellow glow using a repeating `opacity` animation (0.3 to 0.7, 1.2s period). The five capsule indicators fade to `.quaternary` opacity except the worst offender, which scales up 1.3x and gains a pulsing border. A countdown label appears below the score number: "Nudge in 4:32" in `.subheadline` weight, colored to match the gauge zone. On transition to `.bad`, the needle jumps to the red zone, the bezel glow shifts to red with a faster pulse (0.8s), and the worst offender capsule gains a shake animation (offset oscillation). The score number shifts to red and the countdown text becomes "Nudge now" when `.fire` is reached.

**Key SwiftUI techniques:**
- `Canvas` for drawing the gauge arc, tick marks, and colored zones (uses `context.fill` with angular gradient paths)
- `AngularGradient` for the smooth green-yellow-red color band on the dial
- Custom `Shape` conformance for the needle (a narrow tapered `Path`)
- `.rotationEffect` driven by `overallScore` for needle animation
- `TimelineView(.animation)` for smooth needle tracking
- `.shadow(color:radius:)` for the bezel glow effect
- `GeometryReader` for responsive sizing

**Landscape adaptation:**
The gauge shifts to the left 55% of the screen, maintaining its semicircular form but slightly reduced in diameter. The five metric capsules reflow into a vertical stack on the right 40% of the screen, each capsule now wider and taller with full metric names ("Forward Creep", "Head Drop", etc.) and numeric ratio values. The gear icon remains top-right.

**Distinguishing feature:** The physical needle mechanism -- it has inertia. The needle doesn't jump to new values; it swings with a spring-damped physics simulation, overshooting slightly and settling. This gives the interface a tangible, analog instrument quality that no other variant replicates. Small imperfections in the needle movement (slight wobble at rest mapped to `movementLevel`) reinforce the physical metaphor.

---

### Variant 2: Triadic Rings

**Category:** Score-Centric

**Concept:** Three concentric rings, inspired by the Apple Watch Activity Rings, fill clockwise to represent posture quality. The outer ring is the overall posture score, the middle ring tracks the worst offender metric specifically, and the inner ring is a "time in good posture" streak indicator. The visual language is immediately familiar to any Apple Watch user.

**Real-time mode:**
Three concentric rings are centered in the upper 65% of the screen. The outer ring (thickest, ~16pt stroke) represents `overallScore`, filling clockwise from the 12 o'clock position. Its color is an adaptive gradient: green (score > 0.7), transitioning through yellow (0.4-0.7) to red (< 0.4). The middle ring (~12pt stroke) represents the worst offender metric ratio inverted (1.0 - ratio, so a full ring means that metric is fine). Its color is a distinct hue (teal/cyan) to differentiate from the outer ring. The inner ring (~8pt stroke) tracks continuous time in `.good` state, filling to represent the fraction of a configurable "streak goal" (e.g., 30 minutes); its color is a warm orange/amber. Inside the innermost ring, the numeric score appears in `.system(size: 56, weight: .heavy, design: .rounded)`. Below the rings, a horizontal row of five small circular badges (one per metric) shows each metric's ratio as a mini ring fill (single ring, 4pt stroke, ~28pt diameter). Each badge is labeled beneath with a 2-letter abbreviation. The gear icon is top-right.

**Alert mode:**
On `.drifting`, the outer ring's unfilled portion (the gap) begins to pulse with a soft glow animation, drawing attention to how much is missing. The middle ring animates to reflect the worst offender, and its label appears inside the ring stack below the score number: "Head Drop" in `.callout` weight. A circular countdown timer appears as a fourth, outermost thin ring (~4pt stroke, dashed `StrokeStyle`) that depletes counterclockwise, showing `timeRemaining` visually. The small metric badges dim except the worst offender, which gains a scale-pulse animation (1.0 to 1.15, repeating). On `.bad`, the outer ring's color locks to red, the countdown ring flashes, and a haptic-suggesting "vibration" animation (rapid small rotation oscillation, +/-2 degrees) applies to the entire ring stack.

**Key SwiftUI techniques:**
- `Circle().trim(from:to:)` with `.stroke(style: StrokeStyle(lineWidth:lineCap: .round))` for each ring
- `.rotationEffect(Angle(degrees: -90))` to start fill from 12 o'clock
- `AngularGradient` applied as the stroke color for the gradient fill effect
- `.animation(.easeInOut(duration: 0.8), value: score)` for smooth ring fill transitions
- Overlay `ZStack` for centering the score text inside rings
- `withAnimation(.spring())` for alert mode transitions
- `.sensoryFeedback(.impact, trigger:)` (iOS 17+) for haptic pairing

**Landscape adaptation:**
The ring stack moves to the left 50% of the screen. The five metric badges reflow into a 5-row vertical list on the right 45%, each row showing the mini ring, full metric name, and a numeric percentage value. The countdown ring (in alert mode) remains attached to the main ring stack. Padding adjusts so the rings don't clip at reduced height.

**Distinguishing feature:** The triple-ring encoding packs three distinct temporal dimensions into one glanceable graphic: instantaneous overall quality, instantaneous worst-metric severity, and cumulative streak duration. No other variant encodes time-in-state as a primary visual element. The streak ring provides positive reinforcement -- watching it fill during good posture is motivating.

---

### Variant 3: Battery Drain

**Category:** Score-Centric

**Concept:** The screen displays a large phone battery icon that "charges" with good posture and "drains" with bad posture. The metaphor is visceral: bad posture is literally draining your body's battery. The fill level maps to `overallScore`, and the battery color shifts from green (full) to yellow (mid) to red (empty) just like a real iOS battery indicator.

**Real-time mode:**
A large battery outline (rounded rectangle with a small nub on the right side, drawn as a custom `Shape`) occupies the center 55% of the screen, oriented horizontally. The interior fill level corresponds to `overallScore`: 1.0 = full, 0.0 = empty. The fill color uses the system battery palette: green above 0.6, yellow 0.3-0.6, red below 0.3. Inside the filled portion, five thin vertical divider lines segment the battery into five zones, one per metric. Each zone's individual fill height (within the overall fill) varies slightly based on that metric's ratio, creating a subtle undulating top edge to the fill rather than a flat line -- this encodes all five metrics in the fill shape itself. Below the battery, a single-line label reads the overall percentage in `.system(size: 36, weight: .semibold, design: .monospaced)` (e.g., "78%"). Beneath that, a row of five small SF Symbol icons represents each metric: `arrow.up.forward` (forward creep), `arrow.down` (head drop), `arrow.turn.right.down` (shoulder rounding), `arrow.left.arrow.right` (lateral lean), `arrow.triangle.2.circlepath` (twist), each tinted by their individual ratio color. The gear icon is top-left.

**Alert mode:**
On `.drifting`, the battery fill begins a slow drain animation -- the fill level visually decreases by a few percent every second (cosmetic, returns to actual value on recovery), selling the "draining" metaphor. A small lightning bolt icon (`bolt.fill`) appears inside the battery, flashing yellow, indicating the system has noticed. The worst offender's zone within the battery highlights with a brighter fill and a downward-draining animation specific to that segment. A countdown appears below the percentage: "Low posture warning in 3:45" styled like an iOS low-battery notification. On `.bad`, the battery enters "critical" mode: the fill is red, the lightning bolt turns red, and the entire battery pulses with a red glow. The label shifts to "CRITICAL" in red. On `.fire`, a brief "shutdown" animation plays: the screen dims momentarily (opacity flash to 0.8 and back).

**Key SwiftUI techniques:**
- Custom `Shape` struct for the battery outline (rounded rect + terminal nub path)
- `Rectangle().frame(width: fillWidth)` clipped to the battery shape for the fill
- `Canvas` for drawing the per-metric undulating fill top edge (bezier curve path across 5 control points)
- `.matchedGeometryEffect` for the lightning bolt entrance
- `TimelineView(.periodic(every: 0.1))` for the drain animation during drifting
- `.symbolEffect(.pulse)` (iOS 17+) on the lightning bolt SF Symbol

**Landscape adaptation:**
The battery rotates to vertical orientation (nub on top), positioned on the left 40% of the screen. The five metric icons reflow into a vertical column on the right with full metric names and numeric ratios next to each icon. The percentage label moves inside the battery near the bottom of the fill. This vertical battery in landscape resembles an actual phone battery indicator on its side, reinforcing the metaphor.

**Distinguishing feature:** The per-metric undulating fill edge. Rather than a flat fill line, the top of the battery fill is a smooth curve with five control points, each driven by a metric ratio. This means a single glance at the battery fill shape encodes all five metrics: a dip in the middle might indicate shoulder rounding is the problem, while a dip on the left signals forward creep. No other variant encodes metric breakdown in the geometry of a single fill shape.

---

### Variant 4: Arc Meter

**Category:** Score-Centric

**Concept:** A single, wide sweeping arc stretches across the top of the screen, transitioning from green on the left to red on the right. A glowing marker dot sits on the arc at the position corresponding to `overallScore`. The design is radically simple -- one curve, one dot, one score. It resembles a minimalist fuel gauge or the arc atop a thermostat display.

**Real-time mode:**
A thick arc (~20pt stroke, spanning roughly 180 degrees) sweeps across the top third of the screen. The arc is drawn with a `LinearGradient` along its stroke: leading edge is green, center is yellow, trailing edge is red. A bright circular marker (18pt diameter, white fill with colored shadow matching the arc color at that position) sits on the arc at the position corresponding to `overallScore`. The marker has a subtle outer glow (`.shadow(color: .green, radius: 8)` when score is high, shifting to red when low). Below the arc center, the score displays as a large number in `.system(size: 72, weight: .ultraLight, design: .rounded)` -- the ultra-light weight keeps it elegant despite the large size. Below the score, five metric names are listed vertically in a compact stack, each preceded by a small colored circle (SwiftUI `Circle().frame(width: 8, height: 8)`) indicating that metric's status: green (ratio < 0.5), yellow (0.5-0.8), red (> 0.8). The gear icon is a small element at the exact center-bottom of the arc.

**Alert mode:**
On `.drifting`, the arc marker begins a gentle back-and-forth oscillation around its position (+/- 3% of arc length, 2s period), suggesting instability. The marker's glow intensifies and shifts toward yellow/red. The metric list below transforms: the worst offender slides up and scales to `.title2` size with its full name and ratio value, while the other four metrics compress into a single "4 metrics OK" summary line in `.caption` gray. A thin countdown bar appears directly below the arc, a horizontal line that shortens from full width to zero as `timeRemaining` depletes, colored to match the current zone. On `.bad`, the marker locks to the red zone, its glow becomes an aggressive pulsing red halo (radius oscillating 4-16pt), and the countdown bar flashes. The score number tints red.

**Key SwiftUI techniques:**
- `Circle().trim(from: 0.25, to: 0.75)` scaled and positioned to create the arc, stroked with `AngularGradient`
- Custom `View` for the marker dot, positioned using `GeometryReader` + trigonometric calculation (`cos`/`sin` of the angle derived from score)
- `.offset(x:y:)` computed from the arc's geometry for marker placement
- `withAnimation(.interpolatingSpring(stiffness: 100, damping: 10))` for marker movement
- `.blur(radius:)` layered behind the marker for the glow effect
- `HStack` / `VStack` with `.transition(.move(edge: .bottom).combined(with: .opacity))` for the metric list reorganization in alert mode

**Landscape adaptation:**
The arc stretches fully across the wider landscape screen, becoming a shallower curve (less curvature, more like a gentle hill). The marker and score remain centered. The metric list repositions to the right side as a vertical column, taking advantage of the extra horizontal space. The countdown bar spans the full landscape width below the arc.

**Distinguishing feature:** The ultra-minimalist information density. This is the only variant that uses a single stroke and a single dot as the primary data visualization. Everything else is subordinate typography. The arc functions almost like a horizon line with the sun (marker) sitting on it -- a deeply calming visual when posture is good, and immediately alarming when the dot slides toward red. The absence of visual complexity is the feature.

---

### Variant 5: Numeric Countdown

**Category:** Score-Centric

**Concept:** Typography IS the interface. A massive number dominates the entire screen -- the posture score from 100 (perfect) down to 0 (worst). As posture degrades, the number literally counts down like a launch countdown or a ticking clock. The font size, weight, color, and even the typeface tracking shift with the score, making the number itself the visualization.

**Real-time mode:**
The score number fills the center of the screen in `.system(size: 160, weight: .bold, design: .rounded)`. At score 100, the number is rendered in a calm green with generous letter spacing (`.tracking(8)`). As the score drops, the font properties continuously interpolate: weight thickens toward `.black`, color shifts through yellow to red, tracking tightens (from +8 to -2, making digits crowd together as if under pressure), and the font size subtly grows (160pt to 180pt) so the number feels like it's pressing outward. Below the large number, a single line of `.caption` text identifies the current state: "Posture: Good" / "Posture: Drifting" / "Posture: Poor". Below that, five metric labels are laid out as a horizontal `HStack` of small "chips" (rounded rectangle backgrounds), each showing the metric abbreviation and a tiny numeric ratio. Chips are colored by their metric status. The gear icon is top-right, rendered in `.ultraThinMaterial` to stay subtle against the dominant typography.

**Alert mode:**
On `.drifting`, the number begins a slow, visible countdown animation -- each integer decrement is shown as the old digit slides up and out while the new digit slides in from below (a split-flap / odometer effect using `.transition(.asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top)))`). This counting-down effect is cosmetic and dramatic, decrementing roughly one per second until it reaches the actual current score, then holding. The worst offender's chip expands into a full label below the number: "Head Drop 0.87" in `.title3`. The nudge countdown appears as a second, smaller number to the right of the main score, separated by a thin vertical divider, in `.system(size: 48, design: .monospaced)` showing seconds remaining. On `.bad`, the main number turns solid red, the background gains a subtle red vignette (`RadialGradient` overlay, 5% opacity), and the counting animation accelerates. On `.fire`, the number flashes three times then holds at its value.

**Key SwiftUI techniques:**
- `Text("\(score)")` with dynamically interpolated `.font`, `.foregroundStyle`, `.tracking`, and `.scaleEffect` modifiers driven by the score value
- `ContentTransition.numericText()` (iOS 17+) for the animated digit transitions
- `.contentTransition(.numericText(countsDown: true))` for the countdown direction
- `Color(hue: Double(score) / 360.0, saturation: 0.8, brightness: 0.9)` for continuous color mapping
- `.animation(.snappy, value: score)` for responsive feel
- `.background(.ultraThinMaterial)` on the gear icon for readability

**Landscape adaptation:**
The large number shifts to the left 60% of the screen. The metric chips reflow into a vertical list on the right 35%, each chip becoming a wider row with the full metric name, a thin progress bar, and numeric value. The countdown number (in alert mode) repositions below the main number rather than beside it, to avoid width conflicts.

**Distinguishing feature:** The contentTransition numericText countdown effect. No other variant makes the score change itself into theater. The digits physically rolling over like an odometer -- each one individually animating as it changes -- creates urgency without any charts, shapes, or icons. The number IS the UI, and watching it count down creates a gut-level motivation to correct posture before it reaches zero.

---

### Variant 6: Traffic Light

**Category:** Score-Centric

**Concept:** A literal traffic light with three vertically stacked circles: green (good), yellow (drifting), red (bad). Only one light is "on" at a time, matching the current `PostureState`. The metaphor is universal and requires zero learning -- everyone knows what a traffic light means. The implementation goes beyond a static icon by making each light a living, information-rich element.

**Real-time mode:**
A vertical stack of three large circles (each ~90pt diameter) is centered on screen, enclosed in a rounded rectangular "housing" with a dark gray fill (`.primary.opacity(0.1)`) and subtle inner shadow. The green light (top) is fully illuminated when state is `.good`, with a bright green fill and a soft radial glow extending beyond its bounds. The yellow and red lights are "off" -- dark gray fill with a faint colored tint so they're visible but clearly inactive. Within the illuminated green light, five tiny concentric rings (one per metric) are drawn, each ring's completeness showing that metric's ratio. This packs all five metrics into the active light without cluttering the overall design. Below the traffic light housing, a label reads "All Clear" in `.headline` green text. The gear icon sits at the top of the housing, styled as a small circular button resembling a real traffic light's mounting hardware.

**Alert mode:**
On `.drifting`, the green light fades out over 0.5s (opacity 1.0 to 0.15) while the yellow light fades in (0.15 to 1.0) with a warm amber glow. The transition includes a brief moment where both lights are partially lit (crossfade), mimicking a real traffic signal change. Inside the yellow light, only the worst offender's ring is drawn, prominently, with the metric name in tiny text below the ring. The other four metrics' rings fade to the housing background. A countdown arc draws around the yellow light's circumference (a `trim`-animated circle border), depleting as `timeRemaining` decreases. The label changes to "Caution: Head Drop" (or whichever metric). On `.bad`, the yellow fades and the red light illuminates with an aggressive red glow. The red light's interior shows the worst offender ring fully filled (ratio at/above 1.0) and the countdown arc is replaced by a pulsing border. The label reads "Correct Now" in red. On `.fire`, the red light flashes (opacity toggle, 0.5s period) three times.

**Key SwiftUI techniques:**
- `Circle().fill(isActive ? color : Color.gray.opacity(0.2))` for each light
- `.overlay { Circle().stroke(...).trim(from: 0, to: countdownProgress) }` for the countdown arc
- `RadialGradient` overlay on the active light for the glow effect (extends beyond the circle via negative padding + `clipped(false)`)
- `.matchedGeometryEffect(id: "activeMetric", in: namespace)` for animating the worst offender ring between lights during state transitions
- `RoundedRectangle` with `.innerShadow` (custom modifier using inset + blur) for the housing
- `.animation(.easeInOut(duration: 0.5), value: postureState)` for light transitions

**Landscape adaptation:**
The traffic light rotates to horizontal orientation (three circles in an `HStack`), matching how real traffic lights are sometimes mounted horizontally. The housing becomes a horizontal rounded rectangle. The label moves below the housing. The metric information (rings inside the active light) maintains its layout. Extra horizontal space is used to add brief text labels above each light: "Good", "Caution", "Alert" in `.caption2`.

**Distinguishing feature:** The matchedGeometryEffect-driven worst-offender ring that physically travels between lights during state transitions. When posture degrades from good to drifting, the concentric metric ring for the worst offender doesn't just appear in the yellow light -- it visually migrates from the green light to the yellow light, flying across the gap between circles with a fluid animation. This connects the state change to a continuous visual narrative rather than a discrete swap.

---

## Dashboard / Multi-Metric Variants (7-12)

These variants give equal or near-equal visual weight to all five metrics simultaneously. They favor information density over single-score simplicity, appealing to users who want to see exactly which metrics are off and by how much.

---

### Variant 7: Five-Bar Equalizer

**Category:** Dashboard / Multi-Metric

**Concept:** Five vertical bars rise from the bottom of the screen like an audio equalizer or spectrum analyzer. Each bar represents one posture metric, and its height corresponds to that metric's ratio (taller = worse). When posture is good, the bars are low and calm. When posture degrades, the offending bars spike upward, creating an immediately readable visual pattern. The musical metaphor suggests that good posture is about finding the right "mix."

**Real-time mode:**
Five vertical rounded rectangles are evenly spaced across the screen width, rising from the bottom. Each bar's height is proportional to its metric ratio: a ratio of 0.0 produces a bar at minimum height (~20pt, a baseline nub), while a ratio of 1.0 fills to about 75% of the screen height. Bar color uses a continuous vertical gradient within each bar: green at the base transitioning to yellow at 50% height and red at the top, so whatever height the bar reaches determines its perceived color naturally. Each bar has a label below it in `.caption` weight with the metric's abbreviated name. Above each bar, a small floating label shows the numeric ratio in `.caption2.monospacedDigit`. The bars have a slight corner radius (8pt) and a thin border in `.quaternary` foreground style. The overall background is clean (system background color). The gear icon is top-right. A subtle horizontal dashed line at the threshold level (ratio 1.0 height) spans all five bars, labeled "Threshold" in `.caption2` gray, giving context to the bar heights.

**Alert mode:**
On `.drifting`, all bars except the worst offender desaturate (shift toward gray using `.saturation(0.3)`). The worst offender bar gains a pulsing glow effect (colored shadow that oscillates in radius) and its top edge gains a small animated "flame" effect -- a few small circles with `.blur` that drift upward and fade out, drawn via `Canvas`, suggesting the bar is "overheating." The floating numeric label above the worst offender scales up to `.body` size and gains the metric's full name. A countdown bar appears at the very top of the screen as a thin horizontal strip (4pt height, full width) that depletes from right to left, colored yellow for drifting. On `.bad`, the worst offender bar visually "breaks through" the threshold line -- a small crack/shatter effect at the threshold line drawn via `Canvas` (radiating line segments). The countdown strip turns red. The glow on the worst bar intensifies. On `.fire`, all bars briefly spike to maximum height then snap back, creating a visual "shockwave."

**Key SwiftUI techniques:**
- `RoundedRectangle(cornerRadius: 8)` with `.frame(height: barHeight)` for each bar, inside a `VStack` with `Spacer()` above to push bars to the bottom
- `LinearGradient(colors: [.green, .yellow, .red], startPoint: .bottom, endPoint: .top)` applied as fill, masked to the bar's current height
- `Canvas` for the flame particles and shatter effect (drawing small circles/lines with per-frame updates)
- `TimelineView(.animation)` driving the `Canvas` for particle animation
- `.saturation()` modifier for desaturating non-offending bars
- `HStack(spacing:)` with equal-width distribution for the five-bar layout

**Landscape adaptation:**
The five bars gain more horizontal breathing room in landscape, each bar becoming wider (from ~50pt to ~80pt). The threshold line, labels, and countdown bar maintain their positions. The extra width per bar allows the abbreviated labels to expand to full metric names below each bar. The bars' maximum height is reduced proportionally to the shorter landscape screen height.

**Distinguishing feature:** The vertical equalizer metaphor with the "flame" and "shatter" effects. The flame particles drifting off the top of an offending bar create an unmistakable "this is too hot" signal visible from across a room. The shatter effect at the threshold line gives a satisfying (and alarming) visual moment when a metric exceeds its limit. No other variant uses particle effects tied to individual metric bars.

---

### Variant 8: Donut Breakdown

**Category:** Dashboard / Multi-Metric

**Concept:** A large donut chart occupies the screen, divided into five arc segments of equal angular width (72 degrees each). Each segment represents one metric, and the segment's radial thickness (the "width" of the donut ring at that position) varies based on the metric's ratio: thin when the metric is good, thick when it's bad. The donut is a single cohesive shape that gives an instant gestalt of posture quality -- a uniform thin ring means all metrics are good; a lumpy, asymmetric ring means trouble.

**Real-time mode:**
The donut is centered in the top 65% of the screen. Each of the five segments spans 72 degrees. The outer radius of each segment varies: at ratio 0.0, the segment has a thin ring width (~12pt); at ratio 1.0, the ring thickens to ~40pt. This creates a donut whose outer edge is smooth when all metrics are equal but becomes lumpy/organic when metrics diverge. Each segment is filled with a distinct color from a five-color palette (teal, indigo, orange, mint, pink) chosen for distinguishability in both light and dark modes. Small labels radiate outward from each segment's midpoint, connected by thin leader lines, showing the metric name and ratio. Inside the donut hole, the overall score displays in `.system(size: 44, weight: .semibold, design: .rounded)` with a small "Posture Score" subtitle below it. The gear icon sits inside the donut hole, below the score, as a small tappable element.

**Alert mode:**
On `.drifting`, the worst offender's segment animates outward -- its outer radius grows an additional 15pt beyond its ratio-based thickness, physically "bulging" out of the donut. A radial pulse animation emanates from this segment (a thin arc that expands outward and fades, repeating every 2s). The other four segments dim to 50% opacity. The leader line for the worst offender thickens and its label scales up, gaining the countdown text: "Head Drop -- Nudge in 3:22". Inside the donut hole, the overall score is replaced by the worst offender's ratio in large text with the metric name. On `.bad`, the bulging segment turns red regardless of its assigned color, the radial pulse accelerates to every 1s, and the entire donut gains a slow rotation animation (360 degrees over 30s), creating a sense of urgency as the bad segment sweeps around.

**Key SwiftUI techniques:**
- Custom `Shape` struct computing five arc paths with variable outer radii, using `Path.addArc` with per-segment radius calculation
- `Canvas` as an alternative implementation for complex multi-radius donut rendering with smooth bezier interpolation between segments
- `.fill` with distinct colors per segment
- `GeometryReader` for centering and scaling to available space
- `.overlay` with `ForEach` for positioning leader lines and labels using trigonometric offset calculation from segment midpoint angles
- `.scaleEffect` and `.offset` animations for the bulge effect
- `.rotationEffect` with `Animation.linear(duration: 30).repeatForever(autoreverses: false)` for the bad-state rotation

**Landscape adaptation:**
The donut shifts to the left 50% of the screen. The leader lines and labels are replaced by a vertical legend list on the right 45%: five rows, each with a colored circle swatch, metric name, progress bar, and numeric ratio. This avoids the leader lines crossing over each other in the constrained landscape height. The donut hole score remains centered within the donut.

**Distinguishing feature:** The variable-thickness donut ring that creates an organic, lumpy shape when metrics diverge. Unlike a standard pie chart with fixed-width slices, this donut's silhouette itself encodes information -- you can read posture quality from the shape's outline alone without examining colors or labels. The "shape of the shape" is the data.

---

### Variant 9: Horizontal Rails

**Category:** Dashboard / Multi-Metric

**Concept:** Five horizontal progress bars are stacked vertically, one per metric, resembling train tracks or sliding rails. Each bar fills from left to right proportional to its metric's ratio. The layout is deliberately simple and scannable -- a vertical list of horizontal bars is one of the most readable data formats, like a bar chart turned on its side. The design emphasizes clarity and fast scanning over visual flair.

**Real-time mode:**
Five horizontal bars occupy the central portion of the screen, each separated by ~20pt of vertical space. Each bar is a rounded rectangle track (~12pt height, full width minus padding) with a secondary-color background (the track) and a filled portion from the left whose width corresponds to the metric ratio. The fill color is green when ratio < 0.5, yellow when 0.5-0.8, and red when > 0.8, with smooth interpolation between stops. To the left of each bar, the metric name appears in `.subheadline.weight(.medium)`, left-aligned, taking up ~120pt of width. To the right of each bar, the numeric ratio appears in `.subheadline.monospacedDigit`. A thin vertical marker line sits at the 1.0 (threshold) position on each bar, drawn as a 1pt-wide line in `.secondary` color, extending the full height of the bar. Above the five bars, a summary line reads "Posture: Good" in `.title3` weight, colored appropriately. The gear icon is top-right. Below the five bars, a subtle small text shows time in current state.

**Alert mode:**
On `.drifting`, the worst offender bar visually separates from the group: it gains a background highlight (`.thinMaterial` rounded rectangle behind it), scales up slightly in height (12pt to 18pt), and its label gains `.bold` weight. The other four bars fade to 60% opacity. The filled portion of the worst bar begins a subtle animation: a shimmering highlight sweeps across it from left to right repeatedly (a gradient mask that slides horizontally), drawing the eye. A countdown label appears directly below the worst offender bar: "Nudge in 4:15" in `.caption` with a small timer icon (`timer` SF Symbol). On `.bad`, the worst bar's fill extends beyond its track boundary -- the fill rectangle literally overflows, extending rightward past the track's rounded rectangle with a `clipShape` removed for that bar only, creating a visual "overflow" effect. The bar's color is solid red, and the shimmering highlight becomes a pulsing opacity. The summary text changes to "Correct: Head Drop" in red.

**Key SwiftUI techniques:**
- `GeometryReader` within each bar to calculate fill width as a fraction of available width
- `RoundedRectangle(cornerRadius: 6)` for both the track background and the fill overlay
- `.frame(width: ratio * geometryWidth)` for fill sizing, with `.animation(.spring(), value: ratio)`
- `Rectangle().fill(LinearGradient(...)).mask(...)` sliding via `.offset(x:)` with repeating animation for the shimmer effect
- `VStack(spacing: 20)` for the five-bar stack
- `.background(.thinMaterial)` for the alert-mode highlight
- `.clipShape` conditionally applied for the overflow effect in bad state

**Landscape adaptation:**
The five bars spread across the full landscape width, which means much longer bars with more room for the fill to travel. The metric labels move above each bar (rather than beside it) to maximize bar length. The bars can optionally switch from stacked vertical to a 2-row + 3-row grid if the landscape height is too constrained, detected via `GeometryReader` height check. The summary and countdown labels reposition to the top-left.

**Distinguishing feature:** The "overflow" effect when a metric exceeds its threshold. The filled bar literally breaking out of its track boundary is a novel visual metaphor for "this metric has exceeded its limit." It's unexpected and immediately communicates severity. Combined with the shimmer highlight on the worst offender, this variant makes the problem bar impossible to miss even in peripheral vision.

---

### Variant 10: Radial Dial Array

**Category:** Dashboard / Multi-Metric

**Concept:** Five small circular dials are arranged in a pentagonal formation, one per metric. Each dial is a miniature gauge with a rotating needle. The arrangement creates a radar-station or mission-control aesthetic -- five independent instruments that together tell the complete story. When all needles point to the left (low ratio), everything is fine. When needles swing right, trouble is brewing.

**Real-time mode:**
Five circular dials (~80pt diameter each) are arranged in a regular pentagon pattern centered on screen. Each dial has: a circular bezel (thin border, `.secondary` color), interior tick marks at 0%, 25%, 50%, 75%, 100% positions (tiny lines radiating inward from the bezel), a needle (thin tapered line from center rotating clockwise from 7 o'clock at ratio 0.0 to 5 o'clock at ratio 1.0, spanning a 300-degree sweep), and a small colored dot at the needle's tip. The background of each dial is a subtle `AngularGradient` from green (left) through yellow (center) to red (right), at very low opacity (0.08) so it tints rather than overwhelms. Below each dial, the metric name appears in `.caption2`. In the geometric center of the pentagon (equidistant from all five dials), the overall score displays in `.system(size: 36, weight: .semibold, design: .rounded)`. The gear icon is top-right.

**Alert mode:**
On `.drifting`, the worst offender's dial scales up from 80pt to 120pt diameter using `.scaleEffect` with a spring animation, while the other four dials scale down to 60pt, shifting outward to accommodate. The enlarged dial's bezel gains a colored glow (yellow for drifting), and its background gradient opacity increases to 0.25, making the green-to-red zone clearly visible. The enlarged dial gains a new element: a countdown arc along its bezel that depletes like a timer. The metric name below it changes to full name + "Drifting" label. The center score is replaced by the countdown time in `.title3.monospacedDigit`. On `.bad`, the enlarged dial's bezel turns red, the needle pins to the right side (or beyond, with a small bounce effect), and the four small dials' needles "sympathetically" swing slightly right (adding 10% to their visual display, even if their actual ratios haven't changed) to suggest system-wide stress. On `.fire`, the worst dial "cracks" -- a hairline fracture `Path` draws across the dial face.

**Key SwiftUI techniques:**
- `ZStack` with precise `.offset(x:y:)` positioning for the pentagon layout, offsets computed trigonometrically: `x = radius * cos(angle)`, `y = radius * sin(angle)` where angle increments by 72 degrees
- Custom `View` for each dial encapsulating the bezel, ticks, needle, and gradient
- `.rotationEffect(Angle(degrees: needleAngle))` for needle animation
- `.scaleEffect` with `.animation(.spring(response: 0.5, dampingFraction: 0.6))` for alert scaling
- `Path` for the fracture line, revealed with `trim(from: 0, to:)` animation
- `ForEach(MetricKind.allCases)` driving the five dials with per-metric data binding

**Landscape adaptation:**
The pentagon reshapes into a horizontal row of five dials (an `HStack`) since the landscape aspect ratio doesn't support a tall pentagon well. Each dial gets slightly larger (~90pt) thanks to the extra width. The center score moves above the row. When a dial enlarges in alert mode, it grows upward and the row compresses the other four to fit. The landscape row arrangement resembles a car dashboard instrument cluster, reinforcing the "cockpit" feel.

**Distinguishing feature:** The pentagonal spatial arrangement and the sympathetic needle response. The five-dial pentagon is a unique geometric layout no other variant uses, and the "sympathetic swing" -- where all needles shift slightly when one metric goes bad -- creates the impression of an interconnected system under stress. It communicates that posture metrics are related, not independent.

---

### Variant 11: Digital Cockpit

**Category:** Dashboard / Multi-Metric

**Concept:** An aircraft instrument panel rendered in a heads-up display (HUD) aesthetic: dark background, thin glowing lines, and multiple small gauges arranged in a structured grid. The design references an F-16 cockpit or a modern car's fully digital dashboard. It combines an attitude indicator (the overall posture "attitude"), an altimeter (posture score), and five small auxiliary gauges for individual metrics.

**Real-time mode:**
The screen is divided into a grid layout. The top half contains a large central "attitude indicator": a circle (~180pt diameter) split horizontally. The upper half is a blue/cyan gradient ("sky"), the lower half is a brown/amber gradient ("ground"). A horizontal white line across the middle represents level. This line tilts based on `lateralLean` and shifts vertically based on the combined forward/back metrics, giving an instant gestalt of body orientation just like an aircraft attitude indicator. Flanking the attitude indicator on the left is a vertical "altimeter" strip -- a scrolling tape of numbers where the current position corresponds to `overallScore` (100 at top, 0 at bottom), with a triangular pointer marking the current value. On the right is a vertical "heading" strip showing time in current state as a scrolling tape. The bottom half of the screen contains five small rectangular gauges (each ~60pt x 40pt) in a horizontal row, styled as digital readouts: metric abbreviation in `.caption2` above, a small horizontal bar fill, and numeric value below in `.caption.monospacedDigit`. All elements use a thin stroke style with `.cyan`/`.green` coloring on dark backgrounds, simulating phosphor/LED displays. The gear icon is styled as a small HUD element in the top-right: a hexagonal outline with a gear SF Symbol inside.

**Alert mode:**
On `.drifting`, the attitude indicator's horizon line tilts more aggressively (amplifying the lean visual), and a yellow "CAUTION" banner slides down from the top of the attitude indicator circle (`.transition(.move(edge: .top))`). The altimeter tape begins scrolling downward to match the dropping score. The worst offender's bottom gauge flashes with a yellow border (opacity toggle, 0.7s period) and expands to double width, pushing its neighbors to compress. A HUD-style text overlay appears: "ADVISORY: HEAD DROP" in an angular sans-serif style (`.system(.caption, design: .monospaced)`), positioned like a HUD callout with a leader line to the offending gauge. The countdown appears as "T-4:15" in HUD typography. On `.bad`, the attitude indicator's sky turns red, "CAUTION" changes to "WARNING" in red, the altimeter tape scrolls faster, and the worst gauge's flash accelerates. On `.fire`, a "PULL UP" style full-width red banner flashes across the attitude indicator -- a direct aviation reference that communicates maximum urgency.

**Key SwiftUI techniques:**
- `Canvas` for the attitude indicator (drawing filled arcs, clipped to a circle, with rotation transforms for tilt)
- `ScrollViewReader` + `ScrollView` (disabled for user interaction, position-driven) for the altimeter/heading tapes, or `Canvas` with offset drawing for smoother performance
- `TimelineView(.animation)` for continuous updates to the tape positions
- `.font(.system(.caption, design: .monospaced))` throughout for the HUD typeface
- `Color.cyan.opacity(0.9)` as the primary HUD color, with `Color.green` for secondary elements
- `.preferredColorScheme(.dark)` forced regardless of system setting (cockpits are always dark)
- `Path` for leader lines, drawn as angled segments connecting callout text to gauge elements

**Landscape adaptation:**
The cockpit truly comes alive in landscape. The attitude indicator moves to the center, flanked by the altimeter tape on the left and heading tape on the right (standard aviation T-arrangement). The five metric gauges move to a row along the bottom edge, each wider and more detailed. Extra HUD elements can appear: a thin horizon reference line spanning the full width behind all elements, compass-style degree markings along the top edge. The landscape layout is actually the PRIMARY layout for this variant -- portrait is the compressed version.

**Distinguishing feature:** The attitude indicator that maps body orientation to aircraft orientation. No other variant creates a spatial metaphor where forward creep = nose down, lateral lean = bank angle, and overall score = altitude. This gives the user an intuitive spatial sense of their posture -- "I'm banking left and losing altitude" maps directly to "I'm leaning left and my posture is degrading." The aviation HUD aesthetic is visually striking and completely unique among the variants.

---

### Variant 12: Split Flap Display

**Category:** Dashboard / Multi-Metric

**Concept:** An airport departure board / Solari board with mechanical split-flap characters. Each metric is a "row" on the board, and its value is displayed as split-flap digits that physically flip through intermediate characters to reach the target value. The mechanical clatter aesthetic (implied through animation timing) makes data changes feel physical and weighty. The overall posture state is the top row, displayed as a flipping word: "GOOD", "DRIFTING", or "BAD".

**Real-time mode:**
A dark panel (`.black.opacity(0.9)` or dark material) fills the screen, styled to look like a mechanical display board with subtle horizontal ribs between rows. The top row, spanning the full width, displays the posture state as split-flap text: "GOOD" in green-tinted characters, each letter made of an upper and lower half (two `Rectangle` views with text, separated by a thin gap) that flip via 3D rotation when changing. Below, five rows display the metrics, each row containing: the metric name in fixed-width split-flap characters on the left (e.g., "FWD CREP", "HEAD DRP", "SHLDR RND", "LAT LEAN", "TWIST   " -- padded to 8 characters), and the ratio value as a three-digit split-flap number on the right (e.g., "087", "034", "102"). Numbers above 100 indicate threshold exceeded. Each character cell has a dark gray background with a slight top-half / bottom-half separation and a 1pt horizontal line in the middle representing the flap hinge. Characters use `.system(.title3, design: .monospaced)` in a warm amber/yellow color (classic Solari board palette). Below all rows, a thin bottom strip shows the time. The gear icon is rendered as a split-flap character "[S]" (settings) in the top-right, maintaining the aesthetic.

**Alert mode:**
On `.drifting`, the top row flips from "GOOD" to "DRIFTING" character by character, left to right, with each character cycling through several intermediate characters (A-Z roll) before landing on the correct one, staggered by 0.15s per character to create the classic cascading flap sound rhythm. The worst offender's row highlights: its background lightens slightly, and a small right-pointing triangle appears at the left edge (a marker flap). The countdown appears as a new row inserted between the state row and the metric rows: "NUDGE IN  04:32" with the seconds digits continuously flipping. On `.bad`, the state row flips to "BAD" (only 3 characters, so fast), and the entire board's tint shifts from amber to red. The worst offender's value digits flip rapidly, cycling continuously through numbers to create a sense of urgency (displaying the actual value but "buzzing" through +/- 5 on each frame). On `.fire`, all rows simultaneously flip to read "CORRECT POSTURE NOW" spread across the rows, then flip back to actual values after 2 seconds.

**Key SwiftUI techniques:**
- Custom `SplitFlapCharacter` view using `rotation3DEffect(.degrees(angle), axis: (1, 0, 0))` on the top and bottom halves to simulate the physical flap rotation
- `.perspective(0.3)` on the 3D rotation for realistic foreshortening
- `Timer.publish` or `TimelineView` for staggering character flip animations
- `.clipShape(Rectangle())` on each half to clip the text during the flip
- `ZStack` layering the current character behind the flipping-away character for the reveal
- `.shadow(color: .black.opacity(0.3), radius: 2, y: 2)` on the top flap to cast a shadow on the bottom half
- `AsyncSequence` or actor-based animation sequencer for the staggered character cascade timing

**Landscape adaptation:**
The board stretches to full landscape width, allowing longer metric names without abbreviation ("FORWARD CREEP", "HEAD DROP", "SHOULDER ROUNDING", "LATERAL LEAN", "TWIST"). The character cells grow slightly wider. Rows can space out more vertically. The countdown row has room for "NUDGE IN 04 MINUTES 32 SECONDS" with additional flap characters. The extra width makes the Solari board aesthetic even more convincing.

**Distinguishing feature:** The character-by-character cascading flip animation with intermediate character cycling. Each split-flap character doesn't just switch -- it rolls through A, B, C, D... until it reaches the target letter, and each successive character in a word starts its roll slightly after the previous one. This creates the distinctive "ch-ch-ch-ch-ch" visual rhythm of a real Solari board. The 3D rotation with perspective foreshortening on each individual flap half is a technical achievement that makes the mechanical metaphor convincing. No other variant has this level of kinetic, physical animation character.

---

## Minimal / Typographic Variants (13-20)

These variants strip away charts, gauges, and data visualization in favor of radical simplicity. They communicate posture quality through color, motion, typography, and negative space. They are the most glanceable variants -- readable from the farthest distance -- but sacrifice metric-level detail in their resting state.

---

### Variant 13: Single Word

**Category:** Minimal / Typographic

**Concept:** The entire screen displays a single word -- "GOOD", "DRIFTING", or "BAD" -- in massive typography that fills the viewport edge to edge. The word IS the interface. Color, font weight, letter spacing, and animation convey severity. When posture is good, the word sits in calm, spaced-out green letters. When bad, the letters compress, turn red, and tremble. Individual metrics are hidden until alert mode, when the worst offender's name fades in below the state word.

**Real-time mode:**
The word "GOOD" is centered vertically and horizontally, rendered in `.system(size: dynamicSize, weight: .ultraLight, design: .rounded)` where `dynamicSize` is calculated via `GeometryReader` to make the word span approximately 85% of the screen width. The color is a calm, muted green (`.green.opacity(0.8)`). Letter spacing is generous (`.tracking(20)`) giving the word a serene, breathable quality. Below the word, at approximately 65% vertical position, five small dots are arranged in a horizontal line, each representing a metric. Each dot is a `Circle(frame: 6)` colored green/yellow/red based on its metric ratio. These dots are the only indication of individual metrics -- ultra-minimal. The gear icon is a small circle with an SF Symbol in the top-right corner, rendered at 40% opacity to stay invisible until needed. The background is the system background color, clean and empty.

**Alert mode:**
On `.drifting`, the word transitions from "GOOD" to "DRIFTING" using `.contentTransition(.interpolate)`. Simultaneously: the color shifts to amber/yellow, the font weight animates from `.ultraLight` to `.light`, the tracking tightens from 20 to 10 (letters moving closer together), and the entire word gains a very slow horizontal drift animation (offset oscillation, +/- 5pt over 4s), physically embodying the word "drifting." The five dots below resolve: the worst offender's dot scales up to 12pt and gains a label that fades in below it with the metric name. A countdown appears as small text at the bottom of the screen: "4:32" in `.caption.monospacedDigit`. On `.bad`, the word changes to "BAD" -- shorter, so it renders at a much larger dynamic size, filling even more of the screen. Weight jumps to `.bold`, color to red, tracking goes negative (`-3`), letters overlapping slightly. The word gains a tremor animation (rapid small random offsets, +/- 2pt, every 0.1s). The background gains a very subtle red tint (`Color.red.opacity(0.03)`). On `.fire`, the word flashes to maximum opacity and the worst offender's name replaces "BAD" momentarily ("HEAD DROP") before reverting.

**Key SwiftUI techniques:**
- `ViewThatFits` or `GeometryReader` for calculating the maximum font size that fits the screen width
- `.contentTransition(.interpolate)` (iOS 17+) for smooth text morphing between words
- Interpolated `.font(.system(size:weight:design:))` -- since weight can't be smoothly animated natively, use two overlaid `Text` views with reciprocal opacity to crossfade between weights
- `.tracking()` modifier animated with `.animation(.easeInOut(duration: 0.8))`
- `TimelineView(.animation)` with random offset generation for the tremor effect
- `.minimumScaleFactor(0.5)` as fallback for edge cases in text sizing

**Landscape adaptation:**
The word remains centered but benefits from the wider screen: "GOOD" and "BAD" can render at even larger sizes. "DRIFTING" fits comfortably at a size comparable to portrait "GOOD". The five metric dots spread out further along the horizontal axis. The countdown text moves from bottom-center to bottom-right. The wider landscape format makes the single-word design even more impactful -- it resembles a billboard.

**Distinguishing feature:** The physical animation matching the semantic word. "DRIFTING" literally drifts side to side. "BAD" trembles. "GOOD" is still and serene. The animation IS the meaning -- a synesthetic design where the motion of the word reinforces its content. No other variant uses animation semantics this directly tied to the word being displayed.

---

### Variant 14: Breathing Dot

**Category:** Minimal / Typographic

**Concept:** A single circle occupies the center of the screen. When posture is good, it gently expands and contracts in a calm breathing rhythm (4 seconds in, 4 seconds out), colored in a soft green. As posture degrades, the breathing becomes irregular, the color shifts, and the dot's behavior becomes agitated. This variant is almost meditative -- it encourages the user to match their breathing to the dot's rhythm, creating a biofeedback loop.

**Real-time mode:**
A single filled circle (starting diameter ~120pt) is centered on screen. Its size oscillates smoothly: 120pt to 150pt and back over an 8-second cycle (4s expand, 4s contract), using `.animation(.easeInOut(duration: 4).repeatForever(autoreverses: true))`. The fill is a `RadialGradient` from a bright center (`.green.opacity(0.9)`) to a softer edge (`.green.opacity(0.3)`), giving it a soft, glowing quality. A very faint outer ring (1pt stroke, 10% opacity) pulses in anti-phase (expanding when the dot contracts and vice versa), creating a subtle ripple. The five metrics are encoded in the dot's periphery: five tiny satellite dots (6pt diameter) orbit at a fixed radius (~100pt from center), each positioned at a pentagonal vertex. Each satellite's opacity maps to its metric ratio (low ratio = barely visible, high ratio = fully visible). The gear icon is top-right, styled as a thin outlined circle with a gear inside. No text labels appear -- this is the most minimal variant.

**Alert mode:**
On `.drifting`, the breathing rhythm destabilizes: the cycle shortens (8s to 5s) and becomes asymmetric (fast inhale at 1.5s, slow exhale at 3.5s), creating an anxious breathing pattern. The dot's color gradient shifts from green toward yellow. The dot's path gains a slight wobble -- its center position oscillates by +/- 8pt randomly, as if the dot can't hold still. The worst offender's satellite dot grows to 12pt and gains a connecting line (thin stroke) to the main dot, visually tethering it. A small numeric countdown appears just below the main dot in `.caption.monospacedDigit` at 40% opacity. On `.bad`, the breathing becomes rapid (3s total cycle), the color shifts to red, and the wobble increases to +/- 15pt. The dot's shape distorts: instead of a perfect circle, it becomes slightly elliptical, stretched in the direction of the worst offender's satellite (using `.scaleEffect(x:y:)` with asymmetric values). On `.fire`, the dot freezes mid-expansion and "shatters" -- a brief `Canvas`-drawn particle burst radiating outward, then reforms immediately.

**Key SwiftUI techniques:**
- `Circle().fill(RadialGradient(...))` with `.frame(width: breathSize, height: breathSize)` driven by a `@State` variable toggled in `onAppear` with repeating animation
- `.offset(x: wobbleX, y: wobbleY)` driven by `TimelineView(.animation)` with noise function for organic wobble
- `.scaleEffect(x: xScale, y: yScale)` for the elliptical distortion in bad state
- `Canvas` for the shatter particle burst (drawing circles at random angles with decreasing opacity)
- Five `Circle()` views positioned via `.offset` at pentagonal coordinates for satellite dots
- `.opacity(metricRatio)` on each satellite for the ratio encoding
- `withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: inhaleDuration))` for custom breathing ease curves

**Landscape adaptation:**
The breathing dot remains centered. The landscape aspect ratio gives more room for the satellite dots to spread outward to a larger orbital radius (~130pt), making them more distinguishable. In landscape, the satellites can optionally show tiny labels (2-letter abbreviations) since there's more peripheral space. The countdown text (in alert mode) moves to the right of the dot rather than below it.

**Distinguishing feature:** The breathing rhythm as data channel. The dot's breathing rate and symmetry encode posture quality in a way that bypasses visual analysis entirely -- the user can perceive the breathing pattern in peripheral vision or even with eyes mostly closed. The shift from calm 8s breathing to anxious 3s breathing triggers a somatic response; users may literally feel the urgency in their own breathing cadence. This is the only variant designed to affect the user physiologically.

---

### Variant 15: Thin Line

**Category:** Minimal / Typographic

**Concept:** A single horizontal line spans the screen at its vertical center. When posture is good, the line is straight, thin, and calm. As individual metrics degrade, the line responds: it tilts (lateral lean), bows downward (head drop/forward creep), develops waves (shoulder rounding), twists into a zigzag (twist), and eventually fragments into broken segments. One line encodes all five metrics simultaneously through its geometric deformation.

**Real-time mode:**
A single horizontal line (2pt stroke, system label color) spans from the left edge to the right edge of the screen at the vertical midpoint. The line is drawn via `Canvas` as a series of connected bezier curves with control points that respond to metrics. When all metrics are at 0.0, the control points all sit on the horizontal center, producing a perfectly straight line. The five deformations map to metrics:
1. **Forward Creep** (ratio 0-1): the line's center sags downward (center control point drops by up to 40pt)
2. **Head Drop** (ratio 0-1): the line's left third droops down (control point at x=33% drops by up to 30pt)
3. **Shoulder Rounding** (ratio 0-1): the line develops a broad sinusoidal wave (2 full waves across the width, amplitude up to 20pt)
4. **Lateral Lean** (ratio 0-1): the entire line tilts, left end up and right end down (or vice, direction based on lean sign), by up to 15 degrees
5. **Twist** (ratio 0-1): high-frequency zigzag noise is added to the line (8 sharp peaks, amplitude up to 10pt)

These deformations compose additively. Below the line, five small text labels are spaced across the width, each below the region of the line that its metric affects, in `.caption2` at 30% opacity. The gear icon is top-right. The line updates continuously via `TimelineView(.animation)`.

**Alert mode:**
On `.drifting`, the line's stroke width increases from 2pt to 4pt. The region of the line most affected by the worst offender gains a colored glow (yellow shadow, radius 8pt, applied selectively by drawing a second, blurred copy of just that segment). The label for the worst offender increases to `.caption` size and full opacity, gaining the metric name and value. A small countdown appears at screen center-bottom: "4:32" in `.caption.monospacedDigit`. On `.bad`, the line begins to physically fragment: the `Canvas` introduces gaps in the stroke (3-5 breaks in the line, each 8-15pt wide) that grow wider over time. The line's color shifts to red. The gaps appear at the worst offender's region first, then spread. The fragmented line segments tremble slightly (random offset noise per segment). On `.fire`, the line fully shatters -- all segments scatter outward in a brief animation (each segment gets a random velocity and angle), then reassemble over 1.5 seconds.

**Key SwiftUI techniques:**
- `Canvas { context, size in ... }` for all line drawing, using `Path` with `addCurve(to:control1:control2:)` for the smooth deformations
- Control point calculations: `let y = baseY + forwardCreepSag + headDropDroop + sin(x * waveFreq) * roundingAmplitude + zigzagNoise`
- `TimelineView(.animation)` for continuous redraw as metric values change
- `context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, dash: gapPattern))` for fragmentation (dynamic dash pattern)
- `context.addFilter(.shadow(...))` applied to a sub-path for the selective glow
- `.rotation3DEffect` and `.offset` on individual line `Canvas` segments (if using separate views) for the shatter animation

**Landscape adaptation:**
The line spans the wider landscape width, which actually improves the visualization -- the deformations have more horizontal room to express themselves, making the sinusoidal waves and zigzag patterns more visually distinct. The metric labels spread out beneath the line with more space between them. The line's visual impact increases in landscape because it truly dominates the horizontal axis of the screen.

**Distinguishing feature:** The compositional deformation encoding -- five metrics mapped to five distinct geometric transformations of a single line, applied additively. A trained eye can read all five metrics simultaneously from the line's shape: sagging = forward creep, left droop = head drop, waviness = shoulder rounding, overall tilt = lateral lean, jaggedness = twist. No other variant encodes multiple data dimensions in the geometric deformation of a single visual element. The line is both the canvas and the data.

---

### Variant 16: Gradient Wash

**Category:** Minimal / Typographic

**Concept:** The entire screen is a full-bleed color gradient that shifts from cool tones (blues, greens) when posture is good to warm tones (oranges, reds) when posture is bad. There are no shapes, no charts, no numbers in the default state -- just color filling every pixel. The effect is ambient, like a mood lamp. Individual metrics influence the gradient's direction, blend points, and secondary hues, creating subtle variations that encode detailed information in what appears to be "just a color."

**Real-time mode:**
The full screen is filled with a `MeshGradient` (iOS 18) or `LinearGradient` fallback. The gradient has four control points (corners). When all metrics are at 0.0: top-left is soft teal, top-right is cool blue, bottom-left is mint green, bottom-right is sage. The overall impression is calming and cool. As `overallScore` decreases, the four corner colors interpolate toward warm tones: top-left shifts to amber, top-right to orange, bottom-left to coral, bottom-right to red. Individual metrics influence specific corners:
1. **Forward Creep** shifts the top-center region warmer (top-left and top-right blend toward yellow)
2. **Head Drop** warms the bottom-left corner specifically
3. **Shoulder Rounding** warms the bottom-right corner
4. **Lateral Lean** introduces an asymmetry: one side warms faster than the other
5. **Twist** adds a rotational quality: the gradient's angle tilts by up to 30 degrees

The result is that the gradient's exact appearance encodes all five metrics in its color distribution, even though it appears to be "just a color wash." A small, nearly invisible score number (`.system(size: 14, weight: .light)` at 15% opacity) sits in the bottom-left corner for users who want a precise value. The gear icon is top-right at 20% opacity, appearing only on tap (the entire screen is a tap target to briefly reveal the icon and score at full opacity). Five very faint metric labels (8% opacity) are positioned at the screen region each metric influences.

**Alert mode:**
On `.drifting`, the warm tones increase in intensity and the gradient begins a slow, continuous animation: the corner colors drift through their warm palette (amber to orange to coral and back) over 10-second cycles, creating a lava-lamp-like slow shift that's visible in peripheral vision. The region of the screen corresponding to the worst offender becomes noticeably warmer than surrounding areas -- a "hot spot." The score number in the bottom-left increases to 50% opacity and displays the worst offender name. A thin countdown bar appears at the very bottom of the screen (2pt height, full width, white at 60% opacity, depleting from right to left). On `.bad`, the gradient locks into aggressive warm tones (orange, red, crimson), the slow animation accelerates (4-second cycles), and a pulsing effect layers on top: the entire screen gently brightens and dims (opacity of a white overlay oscillates 0% to 5%). The hot spot for the worst offender becomes a visible circular warm region using a radial overlay. On `.fire`, the screen flashes bright (white overlay at 30% for 0.3s) then settles into deep red.

**Key SwiftUI techniques:**
- `MeshGradient` (iOS 18) with 3x3 grid of control points for smooth multi-directional gradient: `MeshGradient(width: 3, height: 3, points: [...], colors: [dynamicColor1, dynamicColor2, ...])`
- Fallback for iOS 17: layered `LinearGradient` views at varying angles with `.blendMode(.normal)` and partial opacity
- `Color(hue:saturation:brightness:)` with computed hue values based on metric ratios for precise color control
- `.ignoresSafeArea()` for true edge-to-edge fill
- `TimelineView(.animation)` for the continuous color drift animation, updating gradient colors each frame
- `withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true))` for the slow lava-lamp drift
- `.onTapGesture` to briefly reveal score and gear icon with `.animation(.easeOut(duration: 0.3))` in and delayed auto-fade

**Landscape adaptation:**
The gradient fills the landscape screen identically -- the four-corner color mapping naturally adapts to any aspect ratio. The wider format actually enhances the ability to distinguish the left-right asymmetry from lateral lean. The metric labels spread out more in the wider format. The countdown bar at the bottom benefits from the greater width. No layout changes needed -- the gradient IS the layout.

**Distinguishing feature:** The complete absence of shapes, lines, or conventional data visualization. This is the only variant where the entire screen is "just" a color gradient. The information is encoded entirely in hue, saturation, brightness, and spatial color distribution. Users develop an intuitive sense: "my screen feels warm, I should sit up." The variant functions more like an ambient room light than a dashboard, which is a fundamentally different interaction modality from every other variant.

---

### Variant 17: Clock Face

**Category:** Minimal / Typographic

**Concept:** A large digital clock dominates the screen, showing the current time. Posture quality is communicated through the clock's visual treatment: background color, font style, and decorative elements shift based on posture state. The insight is that a clock is something users already glance at constantly -- by embedding posture data into the clock display, the posture information gets "free" attention without competing for it. The clock IS the posture monitor.

**Real-time mode:**
The current time displays in `.system(size: 96, weight: .thin, design: .rounded)` centered on screen. The time format follows the user's locale (12h or 24h). Below the time, the date appears in `.title3.weight(.light)`. The posture data is encoded in the clock's environment:
- **Background**: a full-screen gradient that follows the same cool-to-warm logic as Variant 16, but subtler (pastel tones), so the clock remains highly readable. At full good score, the background is a clean system background with a very faint cool tint.
- **Clock color**: the time text color subtly shifts -- at perfect posture it's the primary label color, and as posture degrades it shifts toward the amber/red spectrum.
- **Underline decoration**: a thin horizontal line beneath the time (1pt, 60% opacity) acts as a subtle progress bar. Its fill (from left to right) represents `overallScore`. Its color matches the current posture state color.
- **Five small indicators**: arranged in an arc above the time (like hour markers on an analog clock at the 10, 11, 12, 1, 2 positions), five small dots (6pt) represent the metrics. Each dot's color maps to its metric ratio (green to red).

The gear icon is positioned where the "3 o'clock" position would be on an analog clock, maintaining the clock metaphor. The overall effect is that of a stylish desk clock widget that happens to also show posture.

**Alert mode:**
On `.drifting`, the clock's background warms noticeably. The underline bar's unfilled portion begins to gently pulse. The worst offender's dot above the clock scales up to 10pt and a label appears below it in `.caption2` with the metric name. A subtle new element appears: a thin circular arc (like a clock hand sweep area) behind the time text, spanning an angle proportional to the countdown time, in yellow at 10% opacity. As `timeRemaining` depletes, this arc shrinks, like a clock hand sweeping toward zero. The date text changes to show the nudge countdown: "Nudge in 4:32" in `.caption` below the date. On `.bad`, the background shifts to a warm wash, the clock text turns red, the underline bar fill drops to its current low level in red, and the sweep arc turns red and pulses. The date line reads "Correct: Head Drop". On `.fire`, the time digits flash three times (opacity toggle) and a brief full-screen red flash occurs.

**Key SwiftUI techniques:**
- `Text(Date.now, format: .dateTime.hour().minute().second())` with `TimelineView(.periodic(every: 1))` for live time display
- `.foregroundStyle(Color.interpolate(from: .primary, to: .red, fraction: alertLevel))` -- custom `Color` extension for interpolation
- `Canvas` for the sweep arc behind the time text
- `.background` with animated gradient for the ambient color treatment
- `Circle().trim(from: startAngle, to: endAngle)` for the countdown sweep arc
- `.environment(\.locale, Locale.current)` for locale-aware time formatting
- `GeometryReader` for positioning the five indicator dots in an arc above the text

**Landscape adaptation:**
The clock shifts to the left 55% of the screen, rendered at a slightly smaller but still dominant size. The right 40% becomes a vertical column showing the five metrics with full names, small bar indicators, and numeric values -- a detail panel that appears when the wider format allows it. This makes the landscape version a "clock + dashboard" hybrid. The sweep arc and underline remain with the clock on the left.

**Distinguishing feature:** The time display as a Trojan horse for posture data. By using the current time as the primary visual element, this variant ensures the user looks at the screen for utility (checking the time) and receives posture information as a side effect. No other variant embeds posture data into an independently useful display. The posture information is ambient and ambient only -- there's no moment where the user thinks "let me check my posture"; instead, every time check is automatically a posture check.

---

### Variant 18: Emoji Mood

**Category:** Minimal / Typographic

**Concept:** A single large emoji in the center of the screen expresses the current posture state. Good posture shows a happy, relaxed face; drifting posture shows concern; bad posture shows distress. The emoji changes are animated with playful transitions. This is the most accessible variant -- every user on Earth understands emoji faces instantly, transcending language, culture, and data literacy.

**Real-time mode:**
A single emoji character renders at massive size: `.system(size: 120)`. The emoji selection maps to `overallScore`:
- Score 0.9-1.0: face with open-mouth smile (relaxed and happy)
- Score 0.7-0.9: slightly smiling face (content)
- Score 0.5-0.7: neutral face (concerned, starting to drift)
- Score 0.3-0.5: worried face (drifting toward bad)
- Score 0.1-0.3: grimacing face (bad posture)
- Score 0.0-0.1: face with crossed-out eyes (worst state)

The emoji sits centered in the top 60% of the screen. Below it, a single line of text reads the current state in `.title3` (e.g., "Feeling Good" / "Getting Uncomfortable" / "Ouch"). Below that, five horizontal capsule indicators (identical to Variant 1's capsules) show individual metric ratios in a compact row. The background is clean system background. The gear icon is top-right. A gentle floating animation applies to the emoji: it bobs up and down by 5pt over a 3-second cycle when posture is good, giving it a lively, character-like quality.

**Alert mode:**
On `.drifting`, the emoji transitions to its new expression with a brief "flip" animation: the current emoji scales to 0 on the Y axis (`.scaleEffect(y: 0)`) over 0.2s, swaps to the new emoji, then scales back to 1.0 over 0.2s, creating a coin-flip reveal. The bobbing animation shifts to a side-to-side wobble (swaying). The text changes to identify the worst offender: "Your Head is Dropping" / "Leaning Forward" etc. in a conversational tone. The capsule for the worst offender highlights and expands. A countdown appears below the text: "Nudge in 4:32". On `.bad`, the emoji flip animation is faster (0.15s per half), and the new emoji gains a rapid shake animation (offset oscillation +/- 5pt at 10Hz for 0.5s) upon arrival, as if the emoji itself is in distress. The text turns red and reads something urgent: "Sit up! Forward Creep." The background gains a faint warm tint. On `.fire`, the emoji rapidly cycles through three distressed faces (0.3s each) then settles on the worst one, accompanied by a screen flash.

**Key SwiftUI techniques:**
- `Text(currentEmoji).font(.system(size: 120))` with `.id(currentEmoji)` to trigger transitions
- `.transition(.asymmetric(insertion: .scale(scale: 1, anchor: .center), removal: .scale(scale: 0, anchor: .center)).combined(with: .opacity))` for the flip effect
- `.animation(.spring(response: 0.3), value: currentEmoji)` for responsive changes
- `.offset(y: bobbingOffset)` with repeating animation for the floating effect
- `.rotationEffect(Angle(degrees: wobbleDegrees))` for the alert-mode sway
- `.phaseAnimator([0, 1, 2], trigger: fireTriggered)` (iOS 17+) for the cycling faces on fire

**Landscape adaptation:**
The emoji shifts to the left 40% of the screen. The text and capsule indicators reflow to the right 55% as a vertical stack: state text at top, five capsules as full-width rows with metric names and values, countdown at bottom. The emoji maintains its large size and animations. The landscape layout puts the emotional indicator (emoji) and the analytical data (metrics) side by side.

**Distinguishing feature:** The anthropomorphic emotional communication channel. This is the only variant that uses a humanlike emotional expression as the primary data visualization. Humans are hardwired to read faces -- the user's mirror neurons fire when they see a distressed face, creating an empathetic response ("I should fix this, the face is upset") that's more motivating than any data chart. The conversational text ("Your Head is Dropping" rather than "Head Drop: 0.87") further personalizes the feedback.

---

### Variant 19: Concentric Ripples

**Category:** Minimal / Typographic

**Concept:** Concentric circles emanate from the center of the screen, like ripples on a still pond. When posture is good, the ripples are evenly spaced, slow, and perfectly circular. As posture degrades, the ripples become irregular, speed up, distort into ellipses, and overlap chaotically. The metaphor is that good posture is a calm pond; bad posture disturbs the water.

**Real-time mode:**
A series of 5-8 concentric circle outlines expand outward from the screen center in a continuous animation. New circles spawn at the center every 2 seconds (good state), expanding outward at a steady rate and fading out as they reach the screen edges. Each circle is a thin stroke (`1.5pt`, system label color at decreasing opacity: inner circles at 40%, outer at 5%). The circles are perfectly round and evenly spaced. The overall effect is meditative, like watching ripples on glass-calm water. At the center, where ripples originate, the overall score appears in `.system(size: 32, weight: .light, design: .rounded)` -- small relative to the ripple pattern, suggesting the ripples are the primary visual. Five tiny colored dots sit at the center, arranged in a tight cluster beneath the score, one per metric, following the same green-yellow-red encoding. The gear icon is top-right at low opacity. The background is system background color.

**Alert mode:**
On `.drifting`, the ripple behavior changes: spawn rate increases from every 2s to every 1.2s (more ripples on screen at once), and the ripples begin to distort. The worst offender's metric type determines the distortion:
- Forward Creep: ripples become elliptical, stretched vertically (y-scale > x-scale)
- Head Drop: ripples' center point drifts downward over time (origin shifts toward bottom)
- Shoulder Rounding: ripples gain a wobble in their radius (slight sinusoidal radius variation, making them look like gear outlines)
- Lateral Lean: the origin shifts left or right, so ripples emanate off-center
- Twist: ripples rotate as they expand, creating a spiral-like pattern (each ring is slightly rotated relative to the inner one)

The stroke color shifts from label color toward yellow. The center score scales up to `.title2` and the worst offender's dot grows with a label. A countdown fades in below the center cluster. On `.bad`, the spawn rate hits every 0.6s, creating dense, overlapping rings. Multiple distortions compose (since multiple metrics may be bad). Stroke color shifts to red. Ripples gain varying stroke widths (1-4pt, randomized per ring), breaking the uniformity. On `.fire`, a single large shockwave ring (8pt stroke, bright red) expands rapidly from center to edges in 0.5s, then the pattern resets to calm.

**Key SwiftUI techniques:**
- `TimelineView(.animation)` driving a `Canvas` that maintains an array of active ripple rings, each with: spawn time, current radius, opacity, distortion parameters
- `Canvas { context, size in }` drawing each ring as an elliptical `Path` with variable radius, rotation, and center offset
- `Path.addEllipse(in: CGRect)` or parametric ellipse via `addCurve` for distorted rings
- Array management: append new ripple every N seconds, remove when opacity < 0.01
- `withAnimation(.linear(duration: 0.5))` for the shockwave ring
- `context.opacity = max(0, 1.0 - (currentRadius / maxRadius))` for natural fade-out

**Landscape adaptation:**
Ripples expand to fill the wider landscape viewport, naturally using the extra width. The concentric circles become wider ellipses that fit the landscape aspect ratio (or remain circles that extend beyond the shorter edges, clipped naturally). The center cluster with score and metric dots remains centered. The wider format makes the distortion effects more dramatic and visible, especially the lateral-lean off-center origin and the twist spiral.

**Distinguishing feature:** The per-metric distortion vocabulary. Each of the five metrics maps to a distinct geometric distortion of the circular ripples (elliptical stretch, center shift, radius wobble, lateral shift, rotation). These distortions compose additively, so the exact visual pattern of the disturbed ripples is a unique "fingerprint" of the current posture problem. An experienced user could identify which metric is off purely from the ripple distortion pattern without reading any numbers. No other variant maps metrics to deformations of a repeating animated pattern.

---

### Variant 20: Kanji / Symbol

**Category:** Minimal / Typographic

**Concept:** A single abstract symbol occupies the screen center -- not a specific kanji character, but a custom-drawn glyph that morphs continuously between states. In the "good" state, it resembles a balanced, symmetrical form (like a stable structure or balanced scale). As posture degrades, the symbol distorts, tilts, fragments, and reforms into an unstable, chaotic shape. The metaphor is universal symbolism: visual balance = physical balance.

**Real-time mode:**
A custom-drawn symbol is rendered via `Canvas` at approximately 200pt x 200pt, centered on screen. The "good" state symbol is a symmetric form: imagine a vertical stroke intersected by a horizontal stroke, with small balanced "wings" or serifs at the endpoints -- resembling a plus sign with decorative elements, or a simplified human figure with outstretched arms (an abstract "da Vinci man"). The strokes are 3pt width, system label color at 80% opacity. The symbol has a subtle breathing animation: its scale oscillates between 0.98 and 1.02 over 6 seconds. The five metrics influence the symbol's form continuously through geometric parameters:
1. **Forward Creep**: the vertical stroke's top leans forward (the top endpoint shifts right)
2. **Head Drop**: the vertical stroke shortens from the top (top endpoint moves downward)
3. **Shoulder Rounding**: the horizontal stroke bows downward (curves into a frown shape via control point)
4. **Lateral Lean**: the entire symbol tilts (rotation applied, up to 20 degrees)
5. **Twist**: the horizontal stroke's endpoints twist in opposite vertical directions (left end up, right end down, creating a perspective/twist effect)

When all metrics are 0, the symbol is perfectly symmetric and still. As metrics increase, the deformations accumulate, and the symbol becomes visibly "wrong" -- leaning, drooping, twisting. Below the symbol, a single line of small text (`.caption`, 30% opacity) reads the overall state. Five tiny marks at the symbol's five deformation points are colored by their respective metric ratios. The gear icon is top-right.

**Alert mode:**
On `.drifting`, the symbol's deformations amplify (metrics multiplied by 1.5 for visual effect). The stroke style changes: the smooth strokes gain a slight hand-drawn quality by adding low-amplitude high-frequency noise to the path (random offset per path point, +/- 1pt), making the symbol look like it was drawn with a trembling hand. The stroke color shifts toward amber. The worst offender's deformation is highlighted by drawing that specific stroke component in a brighter color (yellow) while the rest dims. A text label appears below the symbol identifying the offender, and a countdown follows. On `.bad`, the deformations amplify further (2x), the hand-tremor noise increases (+/- 3pt), and portions of the strokes begin to break apart -- dash gaps appear in the stroke style, as if the symbol is fragmenting. The color shifts to red. The breathing animation becomes erratic (random scale changes, 0.95-1.05 at rapid intervals). On `.fire`, the symbol fully disassembles: each stroke component separates and drifts apart with physics-based animation (gravity + random initial velocity), then reassembles over 2 seconds with a spring animation, landing back in its current (deformed) position.

**Key SwiftUI techniques:**
- `Canvas { context, size in }` for all symbol drawing, constructing the glyph from individual `Path` segments (vertical stroke, horizontal stroke, wing elements)
- Path control points driven by metric values: `let topX = centerX + forwardCreep * maxDeformation`
- `Path().addCurve(to:control1:control2:)` for the bowing horizontal stroke
- `context.rotate(by: Angle(degrees: leanAngle))` for the tilt
- Perlin noise or simple random offset function for the hand-drawn tremor effect
- `StrokeStyle(lineWidth: 3, dash: [dashLength, gapLength])` with dynamic dash pattern for fragmentation
- `TimelineView(.animation)` for continuous path updates
- Spring-based `withAnimation` for the disassembly/reassembly

**Landscape adaptation:**
The symbol remains centered and maintains its ~200pt bounding box, which works in both orientations. In landscape, the extra horizontal space is used to add subtle text annotations at each deformation point: small labels that read "Forward", "Head", "Shoulders", "Lean", "Twist" positioned near the part of the symbol they affect, fading in at 20% opacity. These labels help new users learn the symbol's deformation vocabulary. The countdown and state text move to the right of the symbol rather than below.

**Distinguishing feature:** The continuously morphing abstract symbol that encodes all five metrics in its geometry. Unlike the Thin Line (Variant 15) which deforms a 1D line, this variant deforms a 2D glyph, allowing for richer visual encoding (forward/back, up/down, curvature, rotation, and twist are all simultaneously visible). The symbol has the quality of a Chinese/Japanese character or abstract logo that "means" something -- users develop an intuitive reading of the symbol's posture meaning. The disassembly/reassembly animation on fire gives the symbol a life of its own, like a living ideogram.

---

## Quick Reference Table

| # | Name | Category | Primary Visual | Tech Stack |
|---|------|----------|---------------|------------|
| 1 | Precision Gauge | Score-Centric | Speedometer with needle | Canvas, AngularGradient, custom Shape |
| 2 | Triadic Rings | Score-Centric | 3 concentric Apple Watch rings | Circle.trim, AngularGradient, sensoryFeedback |
| 3 | Battery Drain | Score-Centric | Phone battery icon | Custom Shape, Canvas (undulating fill), symbolEffect |
| 4 | Arc Meter | Score-Centric | Single sweeping arc + dot | Circle.trim, offset trig, blur glow |
| 5 | Numeric Countdown | Score-Centric | Giant number counting down | contentTransition.numericText, dynamic font |
| 6 | Traffic Light | Score-Centric | 3 stacked circles | matchedGeometryEffect, RadialGradient |
| 7 | Five-Bar Equalizer | Dashboard | 5 vertical bars | Canvas (particles), LinearGradient, saturation |
| 8 | Donut Breakdown | Dashboard | Variable-width donut chart | Custom Shape (multi-radius arcs), Canvas |
| 9 | Horizontal Rails | Dashboard | 5 horizontal progress bars | GeometryReader, shimmer animation, clipShape |
| 10 | Radial Dial Array | Dashboard | 5 mini gauges in pentagon | Trig positioning, rotationEffect, Path |
| 11 | Digital Cockpit | Dashboard | Aircraft HUD instruments | Canvas (attitude indicator), monospaced HUD type |
| 12 | Split Flap Display | Dashboard | Airport departure board | rotation3DEffect, perspective, Timer cascade |
| 13 | Single Word | Minimal | Massive state word | contentTransition.interpolate, dynamic tracking |
| 14 | Breathing Dot | Minimal | Pulsing circle | RadialGradient, offset wobble, TimelineView |
| 15 | Thin Line | Minimal | Deformable horizontal line | Canvas bezier, additive deformations |
| 16 | Gradient Wash | Minimal | Full-screen color gradient | MeshGradient, hue interpolation |
| 17 | Clock Face | Minimal | Large digital clock | Live date formatting, sweep arc, ambient color |
| 18 | Emoji Mood | Minimal | Large emoji face | phaseAnimator, scaleEffect flip, id transition |
| 19 | Concentric Ripples | Minimal | Expanding ring pattern | Canvas ring array, parametric distortion |
| 20 | Kanji / Symbol | Minimal | Morphing abstract glyph | Canvas path deformation, Perlin noise, spring |
