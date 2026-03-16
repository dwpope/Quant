# Variant Catalog 2: Variants 21-40

## Abstract Geometric, 3D/Body, and Flight/Engineering Instruments

**Date:** 2026-03-16
**Context:** Second section of the 60-variant posture metrics UI catalog for the Quant app.
**Platform:** SwiftUI, iOS 17+, iPhone (portrait + landscape)
**Data Model:** `PostureDisplayData` providing five metric ratios (0-1+), `PostureState`, `NudgeDecision`

---

## Shared Data Contract

All variants receive the same `PostureDisplayData` object:

```swift
struct PostureDisplayData {
    // Five metric ratios: 0.0 = perfect, 1.0 = at threshold, >1.0 = beyond threshold
    let forwardCreep: CGFloat
    let headDrop: CGFloat
    let shoulderRounding: CGFloat
    let lateralLean: CGFloat
    let twist: CGFloat

    let postureState: PostureState        // .good, .drifting(since:), .bad(since:)
    let nudgeDecision: NudgeDecision      // .none, .pending(reason:, timeRemaining:), .fire(reason:)
    let worstOffender: MetricType         // which metric is furthest from ideal
    let overallScore: CGFloat             // 0.0 (worst) to 1.0 (perfect)
}
```

Each variant implements two modes:
- **Real-time mode** (PostureState is `.good`): all 5 metrics displayed simultaneously
- **Alert mode** (PostureState is `.drifting` or `.bad`): animated transition highlighting worst offender + nudge countdown

All variants include a settings gear icon as the single entry point to controls.

---

## Abstract Geometric Variants (21-28)

---

### Variant 21: Stacked Totem

**Category:** Abstract Geometric

**Concept:** A vertical assembly of three geometric primitives representing the body in extreme abstraction: a circle (head), a horizontal line with two endpoint dots (shoulders), and a tall ellipse (torso). When posture is perfect, these three elements are vertically aligned, evenly spaced, and symmetrically drawn along a faint central spine axis. As metrics degrade, each primitive deforms, shifts, or collapses independently, causing the totem to lose its stately, balanced composure and appear to topple or compress.

**Real-time mode:** All three primitives are visible against a clean background. The central spine axis is drawn as a faint dashed vertical line. Each metric maps to a specific deformation:

| Metric | Visual Effect |
|---|---|
| Forward Creep | The entire totem scales larger (as if approaching the viewer). The torso ellipse grows wider horizontally, simulating perspective expansion. |
| Head Drop | The head circle descends, closing the gap between it and the shoulder line. At 1.0, the circle overlaps the line. |
| Shoulder Rounding | The straight shoulder line bends into a downward arc (convex becomes concave). The two endpoint dots pull inward. |
| Lateral Lean | The head circle and shoulder line shift horizontally off the central spine axis by `lateralLean * maxOffset`. The torso ellipse stays grounded, creating a diagonal lean. |
| Twist | The shoulder line rotates around its center (one end rises, the other drops). The head circle's internal crosshair rotates by the same angle. |

Five small labels or SF Symbol icons sit beside each primitive, fading from `Color.secondary` (perfect) to `Color.red` (threshold). The overall totem tints from `.primary` to a warm amber as `overallScore` drops.

**Alert mode:** The totem performs a spring-dampened collapse animation over 0.6 seconds. The head circle drops sharply, the shoulder line sags into a deep frown arc, and the torso balloons outward. All elements except the worst offender's primitive desaturate to 20% opacity. The worst offender's primitive pulses with a subtle scale oscillation (1.0 to 1.05, 2-second period) and is labeled with the metric name in bold system font. A circular countdown timer ring appears around the head circle (or around the worst offender's primitive if it is not the head), filling counterclockwise from the `timeRemaining` value. The settings gear sits in the top-trailing corner at all times.

**Key SwiftUI techniques:**
- `Canvas` for drawing the three primitives and dashed spine axis
- Custom `Shape` conforming to `Animatable` with a 5-value `AnimatablePair` chain for the metric-driven deformations
- `.animation(.spring(response: 0.6, dampingFraction: 0.7))` on each metric value
- `trim(from:to:)` on a `Circle` path for the countdown ring
- `withAnimation(.easeInOut(duration: 0.6))` for the real-time-to-alert transition

**Landscape adaptation:** The totem rotates 90 degrees conceptually: the three primitives arrange horizontally (torso ellipse left, shoulder line center, head circle right) along a horizontal spine axis. This preserves the spatial metaphor while using the wider aspect ratio. Labels relocate below each primitive.

**Distinguishing feature:** The simplicity of just three geometric primitives -- circle, line, ellipse -- makes this the most minimal human-body abstraction possible. It reduces the body to its essential topology (top, middle, base) and uses deformation of those shapes rather than additional visual elements to encode all five metrics. It is the easiest variant to read at arm's length.

---

### Variant 22: Radar Glyph

**Category:** Abstract Geometric

**Concept:** A pentagonal radar chart (spider chart) where each of the five axes represents one posture metric. When posture is perfect, all five axes register at their minimum value, forming a tiny regular pentagon (or a single point) at the center of the chart. As posture degrades, each axis extends outward proportionally, distorting the pentagon into an irregular, lopsided polygon. The visual language borrows from sports performance analytics and air traffic control radar displays.

**Real-time mode:** Five thin axis lines radiate from the chart center at 72-degree intervals, each labeled with an SF Symbol icon at its outer tip: `figure.walk` (forward creep), `arrow.down.to.line` (head drop), `arrow.left.and.right.circle` (shoulder rounding), `arrow.left.arrow.right` (lateral lean), `arrow.triangle.2.circlepath` (twist). The axes have three concentric pentagonal grid lines at 33%, 66%, and 100% thresholds, drawn in `Color.secondary.opacity(0.2)`.

The data polygon connects the five metric points with a filled, semi-transparent shape. Color interpolates from `Color.teal.opacity(0.3)` (all metrics near zero, small polygon) through `Color.orange.opacity(0.3)` to `Color.red.opacity(0.4)` (large polygon, one or more metrics at threshold). The polygon's stroke is a solid 2pt line in the same hue family but fully opaque. Each vertex dot is a 6pt circle.

The polygon's total area serves as a visual proxy for `overallScore` -- the smaller and more regular, the better.

**Alert mode:** The polygon freezes and all axis lines except the worst offender's desaturate to 10% opacity. The worst offender's axis line thickens to 3pt, pulses in red, and a numeric readout of its ratio (e.g., "1.2x") appears beside its vertex. The filled polygon shrinks to show only the worst offender's axis as a single triangular wedge (center to the two adjacent axes), colored in a pulsing red gradient. A countdown arc wraps around the outer boundary of the chart (a circular track overlaid on the pentagonal frame), filling as `timeRemaining` decreases.

**Key SwiftUI techniques:**
- `Canvas` with `context.fill()` for the data polygon and `context.stroke()` for axis lines and grid
- Polar-to-Cartesian coordinate conversion: `x = center.x + radius * cos(angle)`, `y = center.y + radius * sin(angle)`
- `Path` with `move(to:)` and `addLine(to:)` connecting five computed vertices
- `.animation(.interpolatingSpring(stiffness: 200, damping: 15))` on each metric for responsive vertex motion
- `matchedGeometryEffect` to smoothly morph the full pentagon into the single-wedge alert shape

**Landscape adaptation:** The radar chart maintains its aspect ratio (always circular) and centers in the available space. In landscape, two sidebars appear flanking the chart: the left sidebar lists all five metric names with their current ratio values, and the right sidebar shows the countdown timer (if in alert mode) and settings gear. This uses the extra horizontal space for textual detail without distorting the chart.

**Distinguishing feature:** The pentagonal spider chart is the only variant that gives equal visual weight to all five metrics simultaneously in a single geometric shape. The polygon's area, symmetry, and color collectively encode overall posture quality without requiring the user to read any individual value. It is instantly recognizable to anyone familiar with sports analytics or RPG character stat screens.

---

### Variant 23: Concentric Target

**Category:** Abstract Geometric

**Concept:** A bullseye target with concentric colored rings radiating from green (center) through yellow to red (outer edge). Five dots -- one per metric -- are plotted on the target. When posture is perfect, all five dots cluster at the bullseye center. As individual metrics degrade, their dots drift outward along their assigned angular axis toward the red zone. The visual metaphor is marksmanship: perfect posture is a perfect grouping at center; bad posture is a scattered, off-target spread.

**Real-time mode:** The target consists of five concentric rings:
1. Innermost (bullseye): `Color.green.opacity(0.4)`, radius = 15% of view width
2. Ring 2: `Color.green.opacity(0.25)`, extending to 30%
3. Ring 3: `Color.yellow.opacity(0.2)`, extending to 50%
4. Ring 4: `Color.orange.opacity(0.2)`, extending to 70%
5. Outermost: `Color.red.opacity(0.15)`, extending to 90%

Each dot has a fixed angular position (72-degree separation) and its radial distance from center = `metricRatio * maxRadius`. Dot shapes are distinct: a circle (forwardCreep), a downward triangle (headDrop), a rounded square (shoulderRounding), a diamond (lateralLean), and a hexagon (twist). Each dot is 12pt, filled with `.primary`, and trails a faint 30-sample motion trail (a `Path` of its recent positions) to show trajectory.

A subtle crosshair (+) is drawn through the bullseye center in `Color.secondary.opacity(0.3)`. Tiny labels appear when any dot enters the yellow zone or beyond.

**Alert mode:** The target dims to 40% opacity. The worst offender's dot enlarges to 20pt and gains a pulsing red ring around it. A straight red line connects the worst offender's dot to the bullseye center, with its metric name displayed at the midpoint of this line in `.callout` font. The other four dots fade to 15% opacity and freeze. A countdown ring replaces the outermost target ring, animating as a `trim` arc that shrinks as `timeRemaining` decreases.

**Key SwiftUI techniques:**
- `Canvas` for drawing concentric circles, crosshair, motion trails, and connecting line
- `Circle`, `Path`, and custom `Shape` for the five distinct dot shapes
- Ring buffer (circular array of 30 `CGPoint` values per dot) for the motion trail, rendered as a `Path` with progressively decreasing opacity
- `.animation(.spring(response: 0.4, dampingFraction: 0.65))` on dot positions
- `trim(from:to:)` on the outer ring for countdown animation

**Landscape adaptation:** The target occupies the left half of the landscape layout (maintaining its circular aspect ratio). The right half displays a vertical list of all five metrics as horizontal bar gauges with their current ratio values and SF Symbol icons, providing a secondary data-dense readout alongside the spatial target visualization.

**Distinguishing feature:** The motion trails behind each dot provide a temporal dimension that no other variant has: you can see not just where each metric is now, but where it has been over the last few seconds. This makes oscillating metrics (like fidgeting lateral lean) visually distinct from sustained deviations (like a gradual forward creep), adding diagnostic value to the glanceable display.

---

### Variant 24: Pendulum Array

**Category:** Abstract Geometric

**Concept:** Five pendulums hang from a horizontal support bar, evenly spaced. Each pendulum represents one posture metric. When posture is perfect, all five pendulums hang straight down, aligned with gravity -- a serene, still arrangement. When a metric degrades, its pendulum deflects to one side and remains deflected; the further it swings, the worse the metric. The pendulums use physics-based spring animations to feel tangible and weighty.

**Real-time mode:** The horizontal support bar spans the top 15% of the view, drawn as a thick (4pt) line in `.primary`. Five pendulums descend from evenly spaced attachment points. Each pendulum consists of:
- A thin string (1.5pt line) from the attachment point to the bob
- A weighted bob at the bottom, drawn as a distinct shape to identify the metric:
  - Forward Creep: filled circle (16pt)
  - Head Drop: downward-pointing triangle (16pt)
  - Shoulder Rounding: rounded rectangle (14x14pt)
  - Lateral Lean: diamond / rotated square (16pt)
  - Twist: hexagon (16pt)

The string length is fixed at approximately 60% of view height. The pendulum's deflection angle = `metricRatio * 45 degrees` (maximum 45 degrees from vertical). Direction of deflection is always to the right for all metrics except lateralLean, which deflects left or right based on sign. The bob colors shift from `.secondary` (at rest) through `.orange` to `.red` as the angle increases.

A faint vertical reference line (dashed, 0.5pt, `Color.secondary.opacity(0.2)`) drops from each attachment point to show where "plumb" (zero deflection) is, so deviation is immediately visible.

**Alert mode:** The non-offending pendulums smoothly retract upward (strings shorten to 30% of view height over 0.4 seconds) and desaturate to 15% opacity, clearing visual space. The worst offender's pendulum drops lower (string lengthens to 80% of view height) and its bob enlarges to 24pt with a pulsing red outline. The metric name appears below the bob in `.headline` font. A countdown timer appears as a small circular badge on the support bar above the worst offender's attachment point, showing `timeRemaining` as both a numeric value and a diminishing ring.

**Key SwiftUI techniques:**
- `Canvas` for drawing strings, bobs, and reference lines
- `TimelineView(.animation)` wrapping the Canvas to drive physics-based spring behavior: each pendulum's angle uses a custom damped harmonic oscillator (`angle(t) = targetAngle + overshoot * e^(-damping*t) * cos(frequency*t)`) computed per frame for organic overshoot when metric values change suddenly
- Custom `Shape` definitions for each bob type (triangle, diamond, hexagon)
- `.rotationEffect(Angle(degrees: deflection), anchor: attachmentPoint)` as an alternative per-pendulum approach if using stacked SwiftUI views instead of Canvas

**Landscape adaptation:** The support bar runs along the top in landscape as well, but the pendulums are shorter (40% of view height) and wider-spaced to fill the horizontal dimension. A summary bar with metric names and ratio values runs along the bottom edge of the screen, serving as a legend.

**Distinguishing feature:** Physics-based damped harmonic oscillation on the pendulums gives this variant a tactile, almost physical quality. When a metric suddenly changes, the pendulum doesn't snap to its new angle -- it swings past, oscillates, and settles. This makes the visualization feel like a real instrument responding to real forces, which is engaging to watch and creates a natural "fidget detection" visual: small oscillations in a metric produce visible pendulum wobble.

---

### Variant 25: Tensegrity

**Category:** Abstract Geometric

**Concept:** A tensegrity structure -- rigid struts floating in space, held together only by tension cables. This mirrors the actual biomechanical model of the human body where bones (rigid struts) are suspended by muscles and fascia (tension cables). The visualization shows four rigid bars arranged in a roughly humanoid configuration (vertical spine strut, horizontal shoulder strut, and two shorter struts for head and pelvis) connected by a network of tension cables. When posture is good, all cables are evenly taut and the structure floats in balanced equilibrium. When posture degrades, specific cables go slack (thin, faded, drooping) while others overtighten (thick, red, straight), and the struts shift out of alignment.

**Real-time mode:** The four struts are drawn as thick rounded rectangles (6pt width, `Color.primary`):
- **Spine strut**: vertical, centered, ~50% of view height
- **Shoulder strut**: horizontal, crossing the spine at its upper quarter
- **Head strut**: short horizontal, above the spine's top end
- **Pelvis strut**: short horizontal, at the spine's bottom end

Twelve tension cables connect the strut endpoints in a web:

| Metric | Affected Cables | Visual Change |
|---|---|---|
| Forward Creep | Front cables (connecting shoulder strut to pelvis strut on the "front" side) tighten; rear cables slacken | Front cables: thicker (3pt), shift toward red. Rear cables: thinner (0.5pt), fade to 20% opacity, draw as a catenary droop curve instead of straight line |
| Head Drop | Top cables (head strut to shoulder strut) lengthen and slacken; head strut descends | Head-shoulder cables droop, thin out. Head strut position moves downward. |
| Shoulder Rounding | Lateral cables (shoulder strut endpoints to spine) shorten and tighten on the "inside" | Shoulder strut endpoints pull inward, shortening the visible shoulder width. Inner cables thicken. |
| Lateral Lean | Left-side cables tighten, right-side cables slacken (or vice versa) | Asymmetric cable tension causes the entire structure to visually lean. |
| Twist | Diagonal cables become asymmetric: one pair tightens, the opposing pair loosens | Shoulder strut rotates around the spine axis (shown as perspective foreshortening on one end). |

Cable colors range from `Color.teal` (balanced tension) through `Color.orange` (over-tight) to `Color.red` (critical). Slack cables shift to `Color.secondary.opacity(0.2)`. Strut colors remain `.primary` but shift slightly warm when the structure is stressed.

**Alert mode:** All cables except those connected to the worst offender's region snap to a muted gray at 15% opacity. The affected cables for the worst offender flash between their tension color and white (0.5-second period). The corresponding strut highlights with a glow effect (`.shadow(color: .red, radius: 8)`). The metric name and ratio appear centered below the structure. A countdown bar (horizontal, not circular) fills from left to right beneath the metric name, representing `timeRemaining`.

**Key SwiftUI techniques:**
- `Canvas` for drawing struts (thick rounded-end lines) and cables (variable-thickness Bezier curves for catenary droop or straight lines for taut cables)
- Catenary curve approximation: `y = a * cosh((x - center) / a)` for slack cable sag, where `a` decreases as tension decreases
- `context.stroke(path, with: .color(cableColor), style: StrokeStyle(lineWidth: cableThickness))` with per-cable computed thickness and color
- `.animation(.interpolatingSpring(stiffness: 120, damping: 12))` for strut position changes (slow, heavy feel)
- `.animation(.easeOut(duration: 0.3))` for cable color and thickness transitions

**Landscape adaptation:** The tensegrity structure reorients to fill the wider frame: the spine strut becomes more horizontal (angled at 20 degrees from horizontal rather than vertical), with all other struts and cables adjusting accordingly. This creates a "reclining" or "lying down" version of the structure that better fills the landscape aspect ratio while preserving all cable/strut relationships.

**Distinguishing feature:** This is the only variant grounded in actual biomechanical science. Tensegrity is how the musculoskeletal system actually works -- bones floating in a web of muscle tension. The slack/taut cable visualization directly represents what is happening in the user's body: when you slouch forward, your posterior chain muscles go slack while anterior muscles tighten. This makes the visualization not just a metaphor but a simplified model of reality.

---

### Variant 26: Origami Crane

**Category:** Abstract Geometric

**Concept:** A stylized origami crane (tsuru) composed entirely of triangular facets -- approximately 8-10 triangles forming the familiar folded bird shape with spread wings, a long neck, and a pointed tail. When posture is perfect, the crane is fully "open" -- wings spread wide, neck extended upward, body compact and proud. As posture degrades, the crane progressively folds in on itself: wings droop, neck tucks, body compresses. The metaphor is openness and flight (good posture) versus contraction and collapse (poor posture).

**Real-time mode:** The crane is centered in the view, drawn as a collection of triangular facets with thin stroke outlines (1pt, `Color.primary`) and semi-transparent fills. The crane is built from these parametric triangles:

| Metric | Affected Facets | Visual Effect |
|---|---|---|
| Forward Creep | Body triangles (central 2-3 facets) | Compress horizontally -- the body thickens as triangles overlap more, simulating a "closer" appearance |
| Head Drop | Neck/head triangle (topmost facet + beak point) | The beak point angles downward. The neck triangle's apex drops toward the body. |
| Shoulder Rounding | Wing triangles (2-3 facets per side) | Wings rotate inward toward the body center. The angle between each wing's base and its tip decreases. |
| Lateral Lean | All facets | The entire crane tilts laterally -- one wing dips below horizontal, the other rises. |
| Twist | Left wing vs. right wing facets | Wings rotate asymmetrically in opposite directions. The left wing may fold forward (facets foreshorten) while the right wing opens backward. |

Each facet's fill color subtly encodes its stress: relaxed facets are a soft paper-white/cream color (`Color(white: 0.95)` in light mode, `Color(white: 0.15)` in dark mode), while stressed facets (adjacent to high-ratio metrics) blush toward amber/copper. A faint fold line (crease mark) down the center of the crane darkens as `overallScore` drops.

**Alert mode:** The crane performs a dramatic fold animation over 0.8 seconds: all facets except those corresponding to the worst offender collapse flat (triangles compress to near-zero area along fold lines). The worst offender's facets remain open and pulse with a red tint. The crane's "body" becomes a compressed diamond shape with only the offending region visible as an extended, struggling wing or drooping neck. The metric name appears below the crane, and a countdown ring encircles the entire folded form.

**Key SwiftUI techniques:**
- `Canvas` with 8-10 `Path` triangles, each defined by three parametric vertex positions computed from metric values
- `AnimatableData` as a `VectorArithmetic`-conforming struct containing all vertex positions (approximately 24 CGFloat values for 8 triangles with shared vertices) for smooth morphing
- `context.fill()` with per-facet color computed from metric proximity
- `.animation(.spring(response: 0.8, dampingFraction: 0.6))` for fold/unfold transitions
- Fold lines drawn as `Path` dashed lines with `StrokeStyle(dash: [4, 3])`

**Landscape adaptation:** The crane flies horizontally -- it rotates 90 degrees so the beak points right and the tail points left, with wings extending up and down. This uses the full width for the wingspan spread, placing the crane's body at center-left and the beak/head at center-right. Metric labels arrange vertically along the trailing edge.

**Distinguishing feature:** The origami aesthetic is unlike anything else in health app design. The triangular facet construction creates a distinctly geometric, paper-craft feel that is both beautiful when fully open (a proud crane in flight) and emotionally compelling when folded (a bird that cannot fly). The fold/unfold animation doubles as both data visualization and an art piece, making this variant the most likely to be screenshot-shared or shown to friends.

---

### Variant 27: Bauhaus Figure

**Category:** Abstract Geometric

**Concept:** Inspired by Oskar Schlemmer's figure studies at the Bauhaus (1920s), which reduced the human form to pure geometric shapes organized along axes of symmetry. The visualization is a frontal figure composed of: a circle (head), a downward-pointing triangle (torso, wide at shoulders narrowing to waist), a horizontal line at the triangle's top edge (shoulder axis), a vertical line down the center (axis of symmetry / spine), and two small circles at the shoulder-line endpoints (shoulder joints). All rendered in thin monoline stroke on a contrasting background, like a Bauhaus teaching diagram.

**Real-time mode:** The figure is drawn in a single consistent stroke weight (2pt) in `Color.primary` on the system background. No fills -- pure outline. A subtle reference grid of thin horizontal and vertical lines sits behind the figure at 20% opacity, reinforcing the constructivist aesthetic. Metric mapping:

| Metric | Visual Effect |
|---|---|
| Forward Creep | The torso triangle progressively fills from outline to solid. At ratio 0.0, it is a pure stroke outline. At 1.0, it is fully filled with `Color.primary.opacity(0.8)`. The increasing mass communicates "presence" / "weight" / "closeness." |
| Head Drop | The head circle descends on the vertical axis, overlapping the triangle's top edge at high ratios. The circle also subtly shrinks (from 1.0x to 0.85x scale) as it drops. |
| Shoulder Rounding | The triangle's top edge narrows. The two shoulder-joint circles move inward along the shoulder line. The triangle becomes taller and thinner, transforming from a wide equilateral shape to a narrow isosceles one. |
| Lateral Lean | The vertical axis line tilts. The entire figure shifts laterally relative to the fixed reference grid, making the asymmetry obvious against the grid's regularity. |
| Twist | The two shoulder-joint circles become asymmetric in size: one grows (closer shoulder, in perspective) while the other shrinks (farther shoulder). The shoulder line itself remains straight but appears to recede on one side. |

Small Bauhaus-style labels (Futura or system sans-serif, all caps, widely letter-spaced) identify each metric along the edges of the figure: "CREEP" beside the torso, "DROP" beside the head, "ROUND" beside the shoulders, "LEAN" beside the spine, "TWIST" beside the shoulder joints.

**Alert mode:** The reference grid fades to 0% opacity. All figure elements except the worst offender's associated geometry desaturate to `Color.secondary.opacity(0.15)`. The worst offender's geometry is redrawn in a contrasting accent color (`.red` in light mode, `.orange` in dark mode) at 3pt stroke weight. The Bauhaus-style label for that metric enlarges to `.title2` and gains a rectangular underline. A minimal countdown appears as a numeric value below the figure in monospaced digits, counting down in tenths of a second.

**Key SwiftUI techniques:**
- `Canvas` for all geometry (circle, triangle path, lines, shoulder-joint circles) and grid lines
- Triangle fill transition: two overlaid triangles in Canvas -- one stroked, one filled with opacity animated from 0.0 to `forwardCreep` ratio
- `.font(.system(.caption2, design: .default).smallCaps().tracking(3))` for the Bauhaus-style metric labels
- `context.rotate(by: Angle(degrees: lateralLean * maxTilt))` applied to a saved graphics state for the tilt effect
- `.animation(.easeInOut(duration: 0.5))` for the alert mode transition (Bauhaus values measured, deliberate motion)

**Landscape adaptation:** The figure remains vertically oriented but shifts to the left third of the screen. The right two-thirds display the five metric labels as a vertical stack with horizontal bar indicators beside each, drawn in the same monoline Bauhaus style (thin rectangles filling proportionally). The reference grid extends across the full width, unifying both halves.

**Distinguishing feature:** The strict monoline, no-fill, grid-referenced aesthetic is immediately recognizable as Bauhaus / constructivist. It is the only variant that uses a design-historical movement as its visual language. The progressive fill of the torso triangle (from outline to solid) is a particularly elegant encoding of forward creep -- the figure literally gains visual weight as the user leans forward. In dark mode (white strokes on black), this variant has a dramatic, poster-quality appearance.

---

### Variant 28: Sacred Geometry

**Category:** Abstract Geometric

**Concept:** A mandala built from the "Flower of Life" sacred geometry pattern -- overlapping circles arranged in a hexagonal grid forming a symmetric, meditative pattern. When posture is perfect, the mandala is perfectly symmetric, all circles are evenly spaced, and the pattern exhibits its characteristic six-fold rotational symmetry. As posture degrades, the pattern distorts: circles shift, overlap irregularly, symmetry axes break, and the once-harmonious form becomes visually discordant.

**Real-time mode:** The core mandala consists of 19 circles arranged in the classic Flower of Life configuration (1 center + 6 inner ring + 12 outer ring). All circles have the same radius and are drawn with a 1pt stroke in `Color.primary.opacity(0.6)`. The intersections of the circles create the characteristic petal/vesica piscis shapes, which are filled with a very subtle gradient (`Color.teal.opacity(0.05)` in good state).

Each of the five metrics distorts a different aspect of the pattern:

| Metric | Distortion |
|---|---|
| Forward Creep | All circles scale non-uniformly: their horizontal radius grows while vertical shrinks, turning circles into horizontal ellipses. The pattern appears to "flatten" / expand toward the viewer. |
| Head Drop | The top cluster of circles (top 5-6 in the arrangement) slides downward, compressing the upper portion of the mandala and stretching the lower portion. |
| Shoulder Rounding | The left and right lateral circles (the 4-6 circles at 3 o'clock and 9 o'clock positions) pull inward toward the center, narrowing the overall width of the mandala. |
| Lateral Lean | The entire mandala shears horizontally: the top half shifts left or right relative to the bottom half, breaking the vertical symmetry axis. |
| Twist | The mandala gains a rotational offset: the inner ring rotates clockwise while the outer ring rotates counterclockwise (or vice versa), creating a "twisted" pattern where petal shapes become irregular. |

A faint golden ratio spiral can be drawn from the center outward as a subtle reference line, visible only when posture is near-perfect (fades as `overallScore` drops below 0.7).

**Alert mode:** The mandala contracts to approximately 60% of its size over 0.5 seconds. The circles not related to the worst offender metric fade to 5% opacity. The circles affected by the worst offender remain visible and pulse with a warm amber glow (`.shadow(color: .orange, radius: 6)`). The metric name appears in the center of the mandala in a thin serif or system font. The countdown timer manifests as the golden ratio spiral unwinding -- the spiral's `trim(from:to:)` decreases as time runs out, so the spiral progressively disappears.

**Key SwiftUI techniques:**
- `Canvas` for drawing 19+ circles with individual transforms (position, x-scale, y-scale, rotation)
- Per-circle transform computed from a lookup table mapping each circle's grid position to which metrics affect it and by how much
- `context.drawLayer { layerContext in }` to apply group transforms (shear for lateral lean) to subsets of circles
- Vesica piscis fill: computed as the intersection `Path` of two overlapping circles, filled with gradient
- `TimelineView(.animation)` for the subtle idle breathing animation (all circles gently pulse in scale by +/- 1% on a 4-second sinusoidal cycle when posture is good)
- Golden ratio spiral: a custom `Path` defined as a series of quarter-circle arcs with progressively increasing radius

**Landscape adaptation:** The mandala stays circular and centers vertically. It shifts to the center-left of the landscape layout. The right side shows a minimal readout: five horizontal lines (one per metric), each with a small circle at the current ratio position. This creates a pleasing duality: the organic mandala on the left, the linear readout on the right.

**Distinguishing feature:** The sacred geometry / Flower of Life pattern appeals to users with an interest in meditation, yoga, or spiritual practice -- a natural overlap with posture-conscious users. The mandala's six-fold symmetry makes any distortion immediately apparent: humans are exceptionally good at detecting broken symmetry in radially symmetric patterns. The idle breathing animation (gentle scale pulse) makes the mandala feel alive and meditative when posture is good, reinforcing a calm, mindful state.

---

## 3D / Body Visualization Variants (29-34)

---

### Variant 29: SceneKit Mannequin

**Category:** 3D / Body Visualization

**Concept:** A programmatic 3D stick-figure mannequin built entirely from SceneKit primitives -- `SCNSphere` nodes for joints and `SCNCylinder` nodes for bones -- floating in a minimal 3D scene with soft ambient lighting. No imported model files are needed; the entire figure is constructed in code. The mannequin faces the viewer and deforms its pose in real time based on posture metrics, creating a clear "this is what your body is doing" feedback loop.

**Real-time mode:** The mannequin consists of approximately 15 nodes arranged in a skeletal hierarchy:

```
root (hip center sphere)
  spine (cylinder up to chest)
    chest (sphere)
      neck (cylinder up to head)
        head (larger sphere)
      leftShoulder (cylinder out-left)
        leftElbow (sphere, arm hanging)
      rightShoulder (cylinder out-right)
        rightElbow (sphere, arm hanging)
  leftHip (cylinder down-left)
    leftKnee (sphere)
  rightHip (cylinder down-right)
    rightKnee (sphere)
```

Joints are `SCNSphere(radius: 0.04)` in a matte white material. Bones are `SCNCylinder(radius: 0.015)` in a matte system-blue material. The scene background is `UIColor.clear` (composited over the SwiftUI background). A single soft ambient light + one directional light provide gentle shadowing.

Metric mapping via euler angle rotations:

| Metric | Mannequin Response |
|---|---|
| Forward Creep | Spine node rotates forward around X-axis: `spine.eulerAngles.x = forwardCreep * 0.4` radians |
| Head Drop | Head node tilts down: `head.eulerAngles.x = headDrop * 0.5` radians |
| Shoulder Rounding | Both shoulder cylinders rotate forward (X-axis): `shoulder.eulerAngles.x = shoulderRounding * 0.3` radians. Shoulder endpoint spheres move inward slightly. |
| Lateral Lean | Root node tilts sideways: `root.eulerAngles.z = lateralLean * 0.35` radians |
| Twist | Spine node rotates around Y-axis: `spine.eulerAngles.y = twist * 0.4` radians |

Joint sphere colors shift from white to orange to red as the metric affecting that joint increases. A subtle "ghost" mannequin in the ideal pose (all rotations zero) is rendered at 8% opacity behind the active mannequin, providing a visual reference for "where you should be."

Five small 2D SwiftUI labels overlay the bottom of the SceneKit view showing metric names and ratios.

**Alert mode:** The mannequin freezes in its current pose. The ghost mannequin fades out. All joints except those in the worst offender's chain desaturate to a dark gray (material diffuse color change via `SCNTransaction`). The worst offender's joints pulse between their stress color and bright red. The camera slowly dollies in (field of view narrows from 60 to 45 degrees) to focus on the affected region over 1 second. The metric name appears as a 2D overlay centered above the mannequin. Countdown timer is a SwiftUI ring overlaid on the SceneKit view in the bottom-right corner.

**Key SwiftUI techniques:**
- `UIViewRepresentable` wrapping `SCNView` with `updateUIView` driven by `PostureDisplayData` binding
- `SCNTransaction.begin()` / `.commit()` with `animationDuration = 0.3` for smooth pose transitions
- `SCNNode` hierarchy with `.eulerAngles` driven by metric values
- Overlay `ZStack` layering SwiftUI text/shapes on top of the SceneKit view
- `scnView.backgroundColor = .clear` and `scnView.autoenablesDefaultLighting = true`

**Landscape adaptation:** The mannequin rotates to a 30-degree three-quarter view (camera orbits slightly to the side), using the wider frame to show depth that is lost in a direct frontal view. The 2D metric labels relocate to the right edge of the screen as a vertical stack.

**Distinguishing feature:** This is the only variant that renders in true 3D space with real perspective, lighting, and shadow. The "ghost mannequin" overlay showing ideal pose alongside actual pose is a powerful coaching tool -- the user can see exactly how their body differs from the target. The camera dolly-in during alert mode creates a cinematic focus effect that draws attention to the problem area.

---

### Variant 30: Wire Skeleton

**Category:** 3D / Body Visualization

**Concept:** A wireframe body outline rendered in 3D space using SceneKit line geometry -- no solid surfaces, only thin bright lines tracing the edges of a simplified human form. The aesthetic references TRON-style digital environments, medical imaging wireframes, and 1980s computer graphics. The wireframe is built from connected line segments forming a body silhouette with visible vertices at joint locations. Deformations warp the wireframe in 3D, creating visible stretching and compression of the wire mesh.

**Real-time mode:** The skeleton is defined as a set of approximately 40 line segments connecting ~20 vertices, forming:
- An ovoid wireframe head (8 line segments forming an octagonal approximation)
- A trapezoidal wireframe torso (front face, back face, and 4 connecting edges -- 12 segments)
- Line-segment arms (4 segments: shoulder-elbow, elbow-wrist, each side)
- Line-segment legs (4 segments: hip-knee, knee-ankle, each side)
- Cross-bracing lines along the spine (4 segments connecting front-to-back at chest and waist heights)

All lines are rendered in a bright cyan/teal color (`UIColor.systemTeal`) with a 1.5pt width. The SceneKit scene uses a black background. Line endpoints have small bright dots (2pt spheres) at joint positions. The camera is positioned for a slight three-quarter view (15 degrees off frontal) to give depth cues.

| Metric | Wireframe Deformation |
|---|---|
| Forward Creep | The front face of the torso wireframe expands toward the camera (front vertices move forward on Z-axis) while the back face stays fixed, creating visible depth distortion. |
| Head Drop | Head ovoid vertices translate downward. Cross-bracing lines connecting head to torso compress. |
| Shoulder Rounding | Top edge of torso trapezoid narrows. Shoulder vertices pull inward and forward. |
| Lateral Lean | All vertices shear: upper vertices shift left/right while lower vertices remain fixed, creating a visible lean in the wireframe. |
| Twist | Left and right vertices of the torso rotate in opposite directions around the vertical axis, creating a visible twist distortion in the cross-bracing lines. |

A subtle grid floor (10x10 line grid at the figure's feet) provides spatial grounding and makes the lean/twist deformations more obvious against a reference plane.

**Alert mode:** All wireframe lines except those in the worst offender's region shift to a dim blue (`UIColor.systemBlue.withAlphaComponent(0.15)`). The worst offender's lines pulse between cyan and white at 1-second intervals, using `SCNAction.repeatForever(SCNAction.sequence([fadeIn, fadeOut]))`. The grid floor lines pointing toward the affected region illuminate brighter. A scan-line effect (a horizontal bright line sweeping vertically through the wireframe at 2-second intervals, implemented as a moving emissive plane) adds drama. Metric name and countdown appear as 2D SwiftUI overlays.

**Key SwiftUI techniques:**
- `UIViewRepresentable` wrapping `SCNView`
- Custom `SCNGeometry` with `SCNGeometryPrimitiveType.line` for wireframe rendering
- `SCNGeometrySource` for vertex positions, updated per frame from metric values
- `SCNAction` for pulsing animations in alert mode
- Black background with `.pointOfView` camera at slight offset for three-quarter view

**Landscape adaptation:** The camera orbits to a more pronounced three-quarter view (30 degrees off frontal and 10 degrees above eye level), taking advantage of the wider frame to show the wireframe's depth dimension. The grid floor becomes more prominent and extends wider.

**Distinguishing feature:** The wireframe aesthetic is maximally "digital" -- it looks like a body being rendered by a computer, which is exactly what the posture detection pipeline is doing. The visible distortion of the mesh (stretching, twisting, compressing) creates an immediately visceral sense of what is happening to the user's body topology. The scan-line effect in alert mode adds an urgency that feels like a diagnostic system detecting a problem.

---

### Variant 31: Body Silhouette

**Category:** 3D / Body Visualization

**Concept:** A 2D filled silhouette of a human figure in a standing, front-facing pose -- like a bathroom pictogram or an Apple Human Interface Guidelines figure, but with smooth Bezier curves instead of hard geometric shapes. The silhouette is a single continuous `Path` that deforms smoothly as posture metrics change. When posture is perfect, the silhouette stands upright, centered, and symmetric. As metrics degrade, the silhouette leans, twists, drops its head, and hunches -- visually mirroring what the user's body is actually doing.

**Real-time mode:** The silhouette is drawn as a single filled `Path` defined by approximately 30 Bezier control points outlining a simplified human form (head, neck, shoulders, torso, arms at sides, waist). The figure fills approximately 70% of the view height and is centered horizontally.

The silhouette's color is a solid fill that shifts based on `overallScore`:
- Score 1.0 (perfect): `Color.primary` (black in light mode, white in dark mode)
- Score 0.5: `Color.orange`
- Score 0.0: `Color.red`

A faint outline of the ideal posture silhouette (always upright, always centered) persists at 10% opacity behind the active silhouette, serving as a reference "shadow."

| Metric | Silhouette Deformation |
|---|---|
| Forward Creep | The silhouette's torso control points shift forward (rightward in 2D, since the figure is shown slightly turned to give a sense of depth). The shoulders thicken (wider silhouette at shoulder height). |
| Head Drop | The head ovoid's control points shift downward. The neck curve compresses. |
| Shoulder Rounding | The shoulder control points pull inward and the upper back curve becomes more convex (a visible hunch). |
| Lateral Lean | All upper-body control points shift horizontally relative to the lower body. The silhouette develops a visible S-curve lean. |
| Twist | The shoulder width becomes asymmetric: one shoulder extends further than the other (as if one shoulder is coming toward the viewer and the other is receding). |

**Alert mode:** The ideal-pose reference silhouette fades to 0%. The active silhouette dims to 30% opacity everywhere except the body region corresponding to the worst offender, which remains at full opacity and gains a red tint. Specifically:
- Forward Creep: torso region highlighted
- Head Drop: head + neck region highlighted
- Shoulder Rounding: shoulder + upper back region highlighted
- Lateral Lean: waist/core region highlighted
- Twist: shoulder girdle region highlighted

The highlighted region is extracted as a clipped sub-path of the silhouette (using `Path.intersection()` with a rectangular clip region). The metric name appears beside the highlighted region with a connecting line. Countdown ring appears at the figure's chest level.

**Key SwiftUI techniques:**
- Custom `Shape` conforming to `Animatable` with `AnimatableData` containing all ~30 control point coordinates as a flattened `AnimatablePair` chain or `VectorArithmetic`-conforming struct
- `path(in rect: CGRect)` computes all Bezier control points from the five metric values and the available `rect`
- `.fill()` with computed color based on `overallScore`
- Background reference silhouette: same `Shape` with fixed zero-metric parameters, `.opacity(0.1)`
- `.animation(.spring(response: 0.5, dampingFraction: 0.75))` for organic deformation

**Landscape adaptation:** The silhouette shifts to the left 40% of the screen. The right 60% shows a "posture breakdown" panel: five rows, each with the metric name, an icon of the body region, and a horizontal bar showing the current ratio. This panel provides the analytical detail that complements the gestural silhouette.

**Distinguishing feature:** The single continuous filled silhouette is the most human-recognizable variant -- everyone immediately sees "a person" and can read the body language. The deformation of the Bezier curves creates naturalistic body postures (a hunched figure, a leaning figure) rather than abstract geometric changes. This variant has the strongest emotional resonance because humans are hardwired to read body posture as emotional state -- a slouched silhouette triggers an almost empathetic response.

---

### Variant 32: Muscle Heatmap

**Category:** 3D / Body Visualization

**Concept:** A body outline (similar to Variant 31's silhouette) with a transparent fill, overlaid with colored hotspots that indicate which muscle groups or body regions are under strain based on the posture metrics. The outline itself does not deform -- it remains in the ideal upright pose. Instead, colored blobs appear and intensify on specific body regions to show where problems are occurring, like a thermal imaging or medical diagnostic overlay.

**Real-time mode:** The body outline is drawn as a 2pt stroke path in `Color.secondary` -- always upright, always the same shape. This fixed outline serves as a body "map."

Five heatmap zones are defined as elliptical regions positioned at specific body areas:

| Metric | Heatmap Zone Location | Color Behavior |
|---|---|---|
| Forward Creep | Upper chest / sternum area | Radial gradient from center, radius = `forwardCreep * maxRadius`, color from `Color.clear` (center) to `Color.blue.opacity(0.4)` (edge) at low values, shifting to `Color.red.opacity(0.6)` at threshold |
| Head Drop | Neck / base of skull | Same gradient pattern positioned at the neck area |
| Shoulder Rounding | Both deltoid / upper trap regions (two symmetrical zones) | Dual gradient blobs on left and right shoulders |
| Lateral Lean | One-sided oblique / waist area (left or right depending on lean direction) | Single gradient blob on the side of compression |
| Twist | Diagonal across the torso (from one shoulder to the opposite hip) | An elongated elliptical gradient rotated 45 degrees |

Each zone is rendered as a `RadialGradient` clipped to an elliptical mask, with the gradient's outer radius scaling from 0 (no metric deviation) to full zone size (at threshold). Colors progress through a thermal palette: transparent -> blue (cool, mild strain) -> green -> yellow -> orange -> red (hot, severe strain).

When all metrics are zero, the body outline is clean and clear with no hotspots. As metrics increase, colored blobs bloom onto the body like a thermal camera detecting heat.

**Alert mode:** All heatmap zones except the worst offender's fade to 10% opacity over 0.4 seconds. The worst offender's zone intensifies: its gradient radius pulses between 80% and 100% of maximum on a 1-second cycle, and its color pins to `Color.red`. A callout label appears connected to the zone by a thin line, showing the metric name and ratio. The countdown timer appears as a temperature-gauge-style vertical bar on the side of the screen (filling downward, red to empty).

**Key SwiftUI techniques:**
- `Canvas` for the body outline path (fixed, non-animated)
- `Canvas` overlay layer for the heatmap zones: each zone rendered as `context.fill(ellipsePath, with: .radialGradient(...))`
- `.blendMode(.screen)` or `.blendMode(.plusLighter)` on the heatmap layer for luminous color blending where zones overlap
- `RadialGradient(colors: thermalPalette(for: metricRatio), center: .center, startRadius: 0, endRadius: zoneRadius)` per zone
- `.animation(.easeInOut(duration: 0.5))` on gradient radii and colors

**Landscape adaptation:** The body outline shifts to the center-left and the five metric zones reposition accordingly. A sidebar on the right shows a "thermal legend" (color strip from blue to red with ratio labels) and the five metric names with their current values as numeric readouts. This mirrors the layout of professional thermal imaging software.

**Distinguishing feature:** The heatmap approach is the only variant where the body representation itself does not deform. The outline stays in perfect posture, and the strain is shown as an overlay. This has a clinical, diagnostic quality -- like a doctor's body map highlighting problem areas. Users who appreciate data-driven, clinical feedback (rather than artistic metaphor) will prefer this variant. The thermal color palette and bloom effect create a visually striking "scanning" aesthetic.

---

### Variant 33: Spine Column

**Category:** 3D / Body Visualization

**Concept:** An isolated visualization of the spinal column -- no arms, legs, or body outline. Just the spine, rendered as a vertical chain of 7 vertebra-like shapes (simplified as rounded rectangles or capsule shapes stacked vertically with small gaps between them) representing the cervical (top 2), thoracic (middle 3), and lumbar (bottom 2) regions. A circle sits on top for the head. The spine curves and twists in real time based on posture metrics, providing a focused, anatomically suggestive view of the central axis of the body.

**Real-time mode:** The spine is drawn as a chain of 7 rounded rectangles (each approximately 30pt wide x 12pt tall with 4pt corner radius), stacked vertically with 4pt gaps, connected by a thin 1pt vertical line running through their centers (the spinal cord). The head is a 24pt circle sitting above the top vertebra.

The chain is rendered using a `Canvas` with each vertebra's position and rotation computed from the metrics:

| Metric | Spine Deformation |
|---|---|
| Forward Creep | The thoracic vertebrae (middle 3) shift forward (rightward in 2D). The spine develops a visible forward curve. Each successive vertebra from bottom to top shifts progressively more, creating a smooth C-curve. |
| Head Drop | The head circle and top cervical vertebra descend. The gap between cervical and thoracic regions compresses. |
| Shoulder Rounding | The thoracic vertebrae widen slightly and develop a kyphotic (convex backward) curvature exaggeration. Shown as increased forward displacement of the middle vertebrae. |
| Lateral Lean | All vertebrae shift laterally from bottom to top, creating a visible lateral curve (scoliosis-like pattern). Bottom vertebrae stay centered; top vertebrae displace most. |
| Twist | Each vertebra rotates slightly more than the one below it, creating a progressive twist. Shown in 2D as a progressive horizontal displacement alternating left-right (helical projection). The vertebra outlines also warp slightly (one end thicker than the other) to suggest perspective rotation. |

Vertebra colors encode local stress: green (no deviation at this level) through yellow to red (high deviation). The spinal cord line color follows the worst local stress. Each spinal region (cervical, thoracic, lumbar) has a subtle bracket label on the left side.

**Alert mode:** The spine straightens to its current deformed state and freezes. The vertebrae not in the worst offender's region fade to 20% opacity. The affected vertebrae (the specific region where the metric manifests) enlarge slightly and pulse red. For example, head drop highlights the cervical vertebrae; forward creep highlights the thoracic vertebrae. A callout arrow points from the affected region to a text label showing the metric name and ratio. The countdown timer appears as the spinal cord line itself changing color from its current state to a progressively darkening red, filling downward from the head.

**Key SwiftUI techniques:**
- `Canvas` with a computed array of 7 `(position: CGPoint, rotation: Angle, width: CGFloat, color: Color)` tuples, one per vertebra
- Each vertebra position computed as `basePosition + offset(forwardCreep, lateralLean, twist, index)` where `index` determines how much that vertebra is affected (progressive chain)
- `RoundedRectangle` shapes drawn via `context.fill()` with per-vertebra rotation via `context.rotate(by:)`
- Head circle drawn last (on top) with `context.fill(Circle().path(in:))`
- `.animation(.interpolatingSpring(stiffness: 150, damping: 14))` for vertebra position changes

**Landscape adaptation:** The spine rotates to horizontal orientation, read left-to-right: lumbar (left) through thoracic (center) to cervical and head (right). This fills the landscape width naturally. Vertebra labels relocate above each segment. The horizontal orientation also evokes a "timeline" reading of the body's central axis.

**Distinguishing feature:** By stripping away everything except the spine, this variant focuses attention on the literal core of posture. It is the most anatomically specific visualization, showing not just "your posture is off" but "this specific region of your spine is curved/twisted/compressed." The progressive chain computation (each vertebra affected incrementally more than the one below it) creates realistic spinal curves that users with any anatomy knowledge will immediately recognize as kyphosis (forward hunch), lordosis (excessive arch), or scoliosis (lateral curve).

---

### Variant 34: Mirror Avatar

**Category:** 3D / Body Visualization

**Concept:** A stylized cartoon character -- a friendly, gender-neutral humanoid figure with a round head, simple limbs, and an expressive but minimal face (two dot eyes, no mouth) -- that mirrors the user's detected posture in real time. When posture is good, the avatar stands tall and the eyes appear content (neutral semicircle shape). As posture degrades, the avatar slouches, leans, and twists to match, and the eyes shift to express concern (slightly wider, angled eyebrows drawn above them). The character design is reminiscent of a Wii Mii or Nintendo-style avatar, scaled down to essential posture-relevant geometry.

**Real-time mode:** The avatar is rendered in a SwiftUI `Canvas` as a composition of simple shapes:
- **Head:** A filled circle (40pt) with two dot eyes (6pt filled circles) positioned in the upper third. Eyebrow lines (small arcs) above each eye express emotion.
- **Neck:** A short thick line (4pt) connecting head to torso.
- **Torso:** A rounded rectangle (50pt wide x 80pt tall, 12pt corner radius).
- **Arms:** Two line segments per arm (upper arm + forearm), hanging naturally at the sides with small circle joints at shoulders and elbows.
- **Legs:** Two line segments per leg (thigh + shin), planted on a ground line.

The avatar uses a friendly two-tone color scheme: body in a soft teal/blue, head in a warm off-white/cream. The ground line is `Color.secondary.opacity(0.2)`.

| Metric | Avatar Response |
|---|---|
| Forward Creep | Torso tilts forward (rotation around the waist point). Head shifts forward of the body center. The whole figure appears to lean toward the screen. |
| Head Drop | Head circle drops lower, neck line compresses. The figure's head hangs. Eye dots shift downward within the head circle (looking at the ground). |
| Shoulder Rounding | The shoulder points of the arm line segments pull inward and slightly forward. The torso rectangle's top edge narrows. Arms rotate inward at the shoulders. |
| Lateral Lean | The entire upper body (waist up) shifts left or right while the legs stay planted, creating a visible lean. The ground shadow (a flattened ellipse below the figure) shifts correspondingly. |
| Twist | The left and right shoulder points move in opposite depth directions (one arm comes forward/shortens, the other goes back/lengthens). The torso rectangle warps slightly trapezoidal. |

**Expression system:** The avatar's eyebrows and eye shape change based on `overallScore`:
- Score > 0.7: neutral eyebrows (flat), normal round eyes -- calm expression
- Score 0.4 - 0.7: slightly angled eyebrows (inner ends raise), eyes widen slightly -- mild concern
- Score < 0.4: steeply angled eyebrows, wide eyes -- worried expression

A subtle ground shadow (dark ellipse, 10% opacity) beneath the avatar's feet responds to the lean and tilt, grounding the figure in space.

**Alert mode:** The avatar performs an exaggerated version of the worst offender's deformation (1.5x the actual ratio, clamped). The avatar's expression shifts to maximum concern. The body region associated with the worst offender gains a pulsing red highlight (a semi-transparent colored ellipse overlaid on that body region). The metric name appears in a speech-bubble-style callout emerging from the avatar (a rounded rectangle with a triangular tail pointing to the avatar). The countdown timer fills the speech bubble's background as a progress bar. Non-offending metrics still display but the avatar's posture emphasizes the worst.

**Key SwiftUI techniques:**
- `Canvas` for the entire avatar composition
- A custom `AvatarPose` struct containing all joint positions computed from the five metric values, with `VectorArithmetic` conformance for smooth interpolation
- `context.fill()` for body shapes, `context.stroke()` for joint connections and limbs
- `context.drawLayer { }` for the shadow (with `opacity` and `scaleEffect` transforms)
- Expression system: eye and eyebrow positions computed from `overallScore` and drawn as small arcs/circles
- `.animation(.spring(response: 0.5, dampingFraction: 0.7))` for all pose changes
- Speech bubble: SwiftUI `RoundedRectangle` + `Triangle` overlay with `Text`

**Landscape adaptation:** The avatar occupies the center of the landscape view with more surrounding space. A horizontal strip below the avatar shows five small replicas of the avatar in fixed poses: ideal posture, forward creep, head drop, lean, and twist -- serving as a visual legend. The current state is highlighted among these reference poses.

**Distinguishing feature:** This is the only variant with a "character" -- a figure with personality, expression, and emotional response. The eyebrow/eye expression system creates an empathetic feedback loop: when the user slouches, the avatar looks worried, which triggers an almost paternal/caretaker response ("I should fix this, the little guy looks concerned"). The speech-bubble callout in alert mode gives the avatar a voice, making the feedback feel like advice from a companion rather than a clinical warning. This variant has the highest emotional engagement potential.

---

## Flight / Engineering Instrument Variants (35-40)

---

### Variant 35: Attitude Indicator

**Category:** Flight / Engineering Instruments

**Concept:** A faithful recreation of an aviation attitude indicator (artificial horizon) -- the primary flight instrument that shows aircraft orientation relative to the horizon. A circular instrument face is divided into an upper half (sky blue) and a lower half (earth brown/amber). A fixed miniature aircraft symbol (a simplified wing shape) sits at center. The horizon line tilts for roll, shifts vertically for pitch, and the compass ring rotates for yaw. For posture: the "aircraft" becomes a simplified torso/shoulder icon, and the horizon represents "ideal alignment." Any deviation from centered-and-level reads as "wrong" -- leveraging a visual language that billions of people intuitively understand from flight simulators and movies.

**Real-time mode:** The instrument face is a circle filling approximately 75% of the view's smaller dimension. Rendering layers from back to front:

1. **Sky/Ground sphere:** The upper half is a gradient from `Color.blue` (top) to `Color.cyan` (horizon). The lower half is a gradient from `Color.brown` (bottom) to `Color(red: 0.6, green: 0.4, blue: 0.2)` (horizon). The dividing line (horizon) is a thin white 2pt line.

2. **Pitch lines:** Thin white horizontal lines above and below the horizon at 5-degree intervals, labeled with degree values. These move vertically with pitch.

3. **Bank angle indicator:** A curved scale at the top of the circle with tick marks at 10, 20, 30, 45, 60, 90 degrees. A small triangle marker indicates current bank angle.

4. **Center aircraft symbol:** A fixed (non-rotating) yellow/orange miniature wing shape: a horizontal line with downward angled tips and a small dot at center.

5. **Compass ring:** A thin ring around the outer edge with N/E/S/W markings and degree ticks, rotating to show heading/twist.

| Metric | Instrument Response |
|---|---|
| Forward Creep | The horizon line drops below center (the "ground" rises, as if the aircraft is pitching nose-down / leaning forward). The pitch degree markings shift accordingly. Amount: `forwardCreep * 25 degrees`. |
| Head Drop | A small dot (pilot head marker) above the center aircraft symbol descends, representing the head dropping relative to the body frame. |
| Shoulder Rounding | The center aircraft symbol's wings curve downward -- the straight wing line bends into a frown shape. The more rounding, the deeper the frown. |
| Lateral Lean | The entire sky/ground/horizon assembly rotates around the center: `lateralLean * 30 degrees` of roll. The bank angle triangle indicator moves correspondingly. |
| Twist | The outer compass ring rotates: `twist * 20 degrees` off north, indicating yaw/heading change. |

The instrument bezel is a dark gray circle with subtle metallic gradient (`.linearGradient` from gray to dark gray) and four mounting screws (tiny circles) at 12, 3, 6, 9 o'clock positions.

**Alert mode:** The horizon tilts dramatically to reflect the worst offender's metric at exaggerated scale (1.5x). All other metric effects continue but the instrument gains a red warning border -- the bezel tints from gray to red. A "warning flag" (a small red rectangle with "WARN" in white text) drops into view from the top of the instrument face (mimicking the real attitude indicator's failure flag). The worst offender's name appears on the warning flag. The compass ring's outer edge becomes the countdown timer: a red arc segment that shrinks as `timeRemaining` decreases.

**Key SwiftUI techniques:**
- `Canvas` for the entire instrument (layered drawing: gradient halves, pitch lines, bank scale, aircraft symbol, compass ring, bezel)
- Sky/ground: two semicircular fills using `Path` with `addArc()`, with the entire assembly rotated by `lateralLean * rollScale`
- Horizon shift: `context.translateBy(x: 0, y: forwardCreep * pitchScale)` applied before drawing the sky/ground layer
- Wing frown: the aircraft symbol's wing path uses a quadratic Bezier where the control point's Y position = `shoulderRounding * maxDroop`
- Compass ring: `ForEach(0..<36)` drawing tick marks at 10-degree intervals, with the entire set rotated by `twist * yawScale`
- `.animation(.easeInOut(duration: 0.4))` for smooth instrument response

**Landscape adaptation:** The instrument circle maintains its aspect ratio and centers vertically. In landscape, a secondary "instrument panel" strip appears to the right, containing three supplementary mini-instruments:
1. A vertical speed indicator (bar showing rate of posture change)
2. A heading indicator (showing twist as a compass card)
3. An altimeter-style display showing `overallScore` as "altitude"

This creates a full cockpit instrument cluster aesthetic.

**Distinguishing feature:** The attitude indicator is one of the most information-dense single instruments ever designed. It encodes three rotational axes in a single circular display. Aviation enthusiasts will love the fidelity; everyone else benefits from the deeply intuitive visual language of "horizon should be centered and level." The metallic bezel and mounting screws add a physical, analog-instrument charm that makes the app feel like a precision tool rather than a toy.

---

### Variant 36: Spirit Level

**Category:** Flight / Engineering Instruments

**Concept:** Three digital spirit levels (bubble levels) stacked vertically, positioned at the head, shoulder, and hip heights of a simplified body outline. Each level is a rounded rectangular tube containing a floating bubble that should rest at the center mark when that body region is properly aligned. Additionally, a vertical plumb line connects the three levels, indicating the overall spinal alignment. The visual language borrows from construction tools -- universally understood as "is this level and plumb?"

**Real-time mode:** A faint body outline (head circle, shoulder line, torso rectangle, hip line) is drawn at 15% opacity as context. Overlaid on this outline are three spirit level tubes:

1. **Head level** (positioned at the head): A horizontal rounded rectangle (120pt x 24pt) with a clear fill and 1.5pt stroke. Inside, a filled circle "bubble" (18pt) sits at center when head position is correct. Tick marks at center, +/- 25%, and +/- 50% positions.

2. **Shoulder level** (positioned at the shoulders): Same dimensions. The bubble responds to shoulder-related metrics.

3. **Hip level** (positioned at the hips): Same dimensions. The bubble responds to lower-body alignment.

A vertical plumb line (thin line with a weighted bob at the bottom -- a filled circle) connects the three levels along the left side.

| Metric | Spirit Level Response |
|---|---|
| Forward Creep | The plumb line develops a forward curve (the bob swings toward the viewer, shown as the bob growing larger via scale effect + gaining a drop shadow). All three bubbles shift slightly right (forward shown as rightward displacement). |
| Head Drop | The head-level tube slides downward, closing the gap between it and the shoulder level. The head level's bubble also shifts downward within the tube. |
| Shoulder Rounding | The shoulder-level tube's outline curves (from straight-edged to slightly concave on top, convex on bottom), and the bubble inside becomes slightly ovoid (compressed vertically). |
| Lateral Lean | All three bubbles shift in the same lateral direction (left or right) by an amount proportional to `lateralLean * maxDisplacement`. The plumb line tilts off-vertical. |
| Twist | The three levels rotate slightly in alternating directions: head level rotates clockwise, hip level rotates counterclockwise, shoulder level stays fixed. This creates a visible twist pattern across the three levels. |

Bubble colors: green (centered), yellow (near edge), red (at or beyond edge of the tube). The tube backgrounds have a subtle gradient fill (pale green-gray) mimicking the liquid in a real spirit level.

**Alert mode:** The two spirit levels not associated with the worst offender fade to 15% opacity. The offending level enlarges (scales to 1.3x) and shifts to the center of the view. Its bubble turns solid red and pulsates. The metric name appears above the enlarged level in `.headline` font. The plumb line straightens to show the ideal reference while the offending level's deviation is exaggerated. Countdown appears as the "liquid" in the tube draining: the tube's background fill level drops from full to empty as `timeRemaining` approaches zero.

**Key SwiftUI techniques:**
- `Canvas` for drawing the body outline, spirit level tubes, bubbles, tick marks, and plumb line
- Bubble position: `centerX + lateralLean * maxBubbleTravel` (clamped to tube bounds)
- Tube curvature: `Path` with Bezier curves where control point Y-offsets = `shoulderRounding * maxCurve`
- Plumb line bob: `Circle` with `.scaleEffect(1.0 + forwardCreep * 0.3)` and `.shadow(radius: forwardCreep * 4)`
- `.animation(.spring(response: 0.3, dampingFraction: 0.5))` on bubble positions for a fluid, "liquid" feel (bubbles should settle with slight overshoot, like a real spirit level)

**Landscape adaptation:** The three spirit levels arrange horizontally side-by-side (left: hip, center: shoulder, right: head), each now oriented vertically (tall rectangles with bubbles that float up/down). The plumb line becomes a horizontal reference line connecting all three. This landscape layout resembles a professional leveling instrument panel.

**Distinguishing feature:** The bubble physics is the star feature. Real spirit level bubbles have a characteristic movement: they're slightly underdamped, so they overshoot the center mark and settle back with a few oscillations. Implementing this with a custom spring animation (low damping fraction ~0.4) makes the bubbles feel like they are floating in actual liquid. This tactile, physical-tool quality makes the variant feel like a real instrument the user is holding, rather than a software visualization.

---

### Variant 37: Gyroscope Rings

**Category:** Flight / Engineering Instruments

**Concept:** Three concentric gyroscope rings (gimbal rings) rendered in perspective, representing three rotational axes of body alignment. When posture is perfect, the three rings are concentric, coplanar, and appear as a clean set of nested circles viewed from the front. As posture degrades, each ring tilts on its respective axis, creating an increasingly chaotic, off-kilter arrangement. At extreme deviation, the rings approach "gimbal lock" -- a visually tangled state that immediately communicates "something is very wrong."

**Real-time mode:** Three rings are drawn in perspective using `rotation3DEffect`:

1. **Outer ring (Roll / Lateral Lean):** Largest ring (80% of view width diameter), 3pt stroke, `Color.blue`. Represents the frontal plane. Tilts left/right based on `lateralLean`.

2. **Middle ring (Pitch / Forward Creep + Head Drop):** Medium ring (60% diameter), 2.5pt stroke, `Color.green`. Represents the sagittal plane. Tilts forward/backward based on the average of `forwardCreep` and `headDrop`.

3. **Inner ring (Yaw / Twist):** Smallest ring (40% diameter), 2pt stroke, `Color.orange`. Represents the transverse plane. Rotates around the vertical axis based on `twist`.

`shoulderRounding` modifies the middle ring's shape: at zero, it is a perfect circle; as rounding increases, the top of the ring pinches inward, deforming from circle toward teardrop, by adjusting the ellipse's vertical eccentricity at the top.

Each ring is rendered as an `Ellipse()` in SwiftUI with `.rotation3DEffect()` applied:
```swift
Ellipse()
    .stroke(Color.blue, lineWidth: 3)
    .frame(width: outerDiameter, height: outerDiameter)
    .rotation3DEffect(.degrees(lateralLean * 30), axis: (x: 0, y: 0, z: 1))
```

A small sphere dot sits at the top of the inner ring (the "pilot" or "head marker"), whose position descends clockwise as metrics degrade.

When all three rings are aligned (good posture), the composition looks like a clean, harmonious target. As they diverge, the 3D perspective creates overlapping, intersecting rings that look increasingly unstable.

**Alert mode:** The two rings not primarily associated with the worst offender freeze and fade to 20% opacity. The worst offender's ring enlarges to 90% of view width, tilts to its current extreme, and pulses in its accent color. The head marker dot on the inner ring turns red. The metric name appears at the center of the gimbal assembly. The countdown timer manifests as the worst offender's ring slowly rotating back toward center: `trim(from: 0, to: timeRemaining/totalTime)` on its stroke, so the ring progressively disappears as time runs out.

**Key SwiftUI techniques:**
- Three `Ellipse()` views in a `ZStack`, each with `.rotation3DEffect()` around different axes
- `.rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)` for pitch tilt (forward/backward lean of the middle ring)
- `.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)` for yaw rotation (twist of the inner ring)
- `.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 0, z: 1))` for roll (lateral lean of the outer ring)
- Z-ordering challenge: SwiftUI's `rotation3DEffect` does not handle true 3D occlusion (rings passing through each other). Mitigation: draw each ring as two half-ellipses and manually order the front halves above and back halves below, or accept the flat layering as an acceptable stylistic choice.
- `.animation(.easeInOut(duration: 0.6))` for smooth ring tilts

**Landscape adaptation:** The gimbal assembly maintains its circular aspect ratio and centers in the landscape view. The extra horizontal space is used for three small supplementary displays to the right: one per ring, showing its current tilt angle numerically with a small diagram. These supplementary displays use the same color coding (blue, green, orange) as their respective rings.

**Distinguishing feature:** The 3D perspective rotation of nested rings creates a visually striking kinetic sculpture effect. When posture is good, it looks like a calm, spinning gyroscope. When posture is bad, the diverging ring angles create an unsettling "gimbal lock" appearance that is immediately readable as instability. This variant is the most visually dynamic of the instrument category -- the 3D perspective transforms make it feel like a physical object floating in space.

---

### Variant 38: Compass Rose

**Category:** Flight / Engineering Instruments

**Concept:** A nautical/orienteering compass with an ornate compass rose at center. The compass needle should point "North" (straight up) when posture is perfect -- north represents ideal alignment. As posture degrades, the needle deflects away from north, the compass face rotates, and auxiliary indicators show specific metric deviations. The compass dial has concentric severity zones: green center zone, yellow intermediate zone, red outer zone. The further the needle strays from north, the deeper into the red zone it falls.

**Real-time mode:** The compass fills approximately 80% of the view's smaller dimension. Layers from back to front:

1. **Severity zones:** Three concentric filled rings: innermost (0-15 degree radius) in `Color.green.opacity(0.2)`, middle (15-30 degrees) in `Color.yellow.opacity(0.15)`, outermost (30-45+ degrees) in `Color.red.opacity(0.1)`.

2. **Compass rose:** An ornate 8-point star design at the center in `Color.secondary.opacity(0.3)`, providing visual texture. The four cardinal points (N, E, S, W) are labeled in a classic serif-style font (system `.body` with `.serif` design).

3. **Degree ring:** A circle of tick marks at every 5 degrees, with numeric labels every 30 degrees. This ring rotates based on `twist`.

4. **Compass needle:** A classic diamond/kite-shaped needle. The north (top) half is red; the south (bottom) half is white/silver. The needle's tip points in the direction computed from the combined lateral lean and forward creep:
   - `needleAngle = atan2(lateralLean, forwardCreep)` (deviation direction)
   - `needleDistance = hypot(lateralLean, forwardCreep)` (deviation magnitude, controls how far from center the needle tip reaches into the severity zones)

5. **Secondary indicators:**
   - Head drop: A small bead on the needle descends from the center toward the south pole as head drop increases.
   - Shoulder rounding: The needle's shaft thickness increases (from 3pt to 6pt), visually representing the "weight" or "burden" on the shoulders. The needle also bows outward slightly (becomes an arc instead of a straight line).

| Metric | Compass Response |
|---|---|
| Forward Creep | Needle deflects toward the 6 o'clock position (south = "falling forward"). Combined with lateral lean for final angle. |
| Head Drop | A bead marker on the needle slides toward the south end. |
| Shoulder Rounding | Needle shaft thickens and bows. |
| Lateral Lean | Needle deflects east or west. Combined with forward creep for final angle. |
| Twist | The degree ring rotates, creating visual misalignment between the ring markings and the cardinal labels (which stay fixed). |

**Alert mode:** The severity zones flash (the zone the needle tip occupies pulses in its color at 1-second intervals). The compass needle locks to the worst offender's direction and the needle tip gains a glowing halo effect. The compass rose design at center is replaced by the metric name in large text. The degree ring stops rotating and freezes. The countdown timer replaces the outermost severity zone as a diminishing arc in red, shrinking clockwise from 360 degrees to 0 as `timeRemaining` approaches zero.

**Key SwiftUI techniques:**
- `Canvas` for the entire compass: severity zone fills (`addArc`), tick marks (`ForEach` over angles), compass rose star (custom `Path`), needle (custom `Path` with variable width)
- Needle angle: `Angle(radians: atan2(lateralLean, forwardCreep))` for the combined deviation direction
- Needle bowing: a quadratic Bezier curve for the needle shaft where the control point's perpendicular offset = `shoulderRounding * maxBow`
- Degree ring rotation: `context.rotate(by: Angle(degrees: twist * yawScale))` applied to a saved context state before drawing the tick marks
- `context.drawLayer { }` for applying rotation to the degree ring without affecting other elements

**Landscape adaptation:** The compass maintains its circular aspect ratio and shifts to center-left. A "navigation data" panel appears on the right, styled like a ship's instrument panel: five rows showing each metric as a "bearing" reading (e.g., "FWD CREEP: 034 degrees" styled in monospaced, green-on-dark text). This creates a full navigation console aesthetic.

**Distinguishing feature:** The compass rose combines two metrics (forward creep and lateral lean) into a single needle direction using `atan2`, creating a true 2D directional encoding that most other variants lack. The user doesn't just see "forward creep is high" -- they see "you're drifting toward 4 o'clock" (forward and to the right). This combined directional reading adds genuine diagnostic value: it reveals the direction of postural drift, not just its magnitude. The ornate compass rose design also gives this variant an antique, nautical charm.

---

### Variant 39: Oscilloscope

**Category:** Flight / Engineering Instruments

**Concept:** Five real-time waveform traces displayed on a simulated oscilloscope screen -- the classic green phosphor display with a dark background, scan lines, and a glowing afterimage. Each trace represents one posture metric as a scrolling waveform, with the baseline (zero deviation) at center and amplitude proportional to the metric's current ratio. The aesthetic is 1970s-80s electronic test equipment: a warm green glow on a near-black background, subtle CRT scan lines, and slight bloom on bright signals.

**Real-time mode:** The display occupies the full view with a dark background (`Color(red: 0.02, green: 0.05, blue: 0.02)` -- near-black with a hint of green). A subtle horizontal scan line pattern overlays everything at 3% opacity.

Five waveform traces are stacked vertically, each in its own horizontal "channel" with a thin divider line between them:

| Channel | Metric | Waveform Behavior |
|---|---|---|
| CH1 (top) | Forward Creep | Amplitude = `forwardCreep * channelHeight/2`. Signal scrolls left at a fixed rate. |
| CH2 | Head Drop | Same behavior, dedicated channel. |
| CH3 | Shoulder Rounding | Same behavior, dedicated channel. |
| CH4 | Lateral Lean | This metric can be positive or negative, so the waveform oscillates above and below the baseline. |
| CH5 (bottom) | Twist | Same as lateral lean -- bidirectional. |

Each trace is drawn as a `Path` connecting a ring buffer of the last 120 sample points (approximately 2 seconds at 60fps). The path uses cubic Bezier interpolation between points for smooth curves. The most recent point (right edge) is brightest; older points fade (phosphor decay simulation) -- achieved by drawing the path with a gradient from `Color.green.opacity(1.0)` (right) to `Color.green.opacity(0.1)` (left).

Channel labels sit on the left edge: "CH1: FWD", "CH2: HEAD", etc., in a monospaced font, glowing green (`Color.green.opacity(0.8)`).

A vertical "trigger line" (a bright vertical line at the right edge) marks the current sample position.

Each channel's baseline (zero line) is drawn as a faint dashed horizontal line in `Color.green.opacity(0.15)`.

When a metric is at zero, its trace is a flat line at the baseline. When a metric rises, the trace deflects upward (or bidirectionally for lean/twist). Sustained high values show as a consistently elevated waveform; oscillating values (fidgeting) show as visible wave patterns.

A CRT-style bloom/glow effect is applied to the entire canvas via `.shadow(color: Color.green.opacity(0.3), radius: 4)`.

**Alert mode:** The four non-offending channels compress to half-height and dim to 30% brightness. The worst offender's channel expands to fill 60% of the vertical space. Its trace color shifts from green to amber to red (maintaining the phosphor glow aesthetic). The channel label enlarges and flashes. A rectangular "ALERT" indicator (a box outline with "ALERT" text) appears in the top-right corner, pulsing. The countdown timer appears as a horizontal progress bar at the bottom of the offending channel, filling from right to left in a red phosphor glow.

**Key SwiftUI techniques:**
- `Canvas` wrapping a `TimelineView(.animation)` for continuous frame-rate rendering
- Ring buffer: `[CGFloat]` array of 120 elements per channel, with a write-head index that wraps. Each frame, the current metric value is written at the head and the Path is recomputed from the buffer contents.
- Cubic Bezier interpolation between buffer points: `path.addCurve(to: next, control1: cp1, control2: cp2)` where control points are computed using Catmull-Rom to Bezier conversion
- Phosphor decay: draw the path with `context.stroke(path, with: .linearGradient(Gradient(colors: [.green.opacity(0.1), .green.opacity(1.0)]), startPoint: leftEdge, endPoint: rightEdge))`
- CRT scan lines: a repeating horizontal stripe pattern drawn as a `Rectangle()` with a very small height, repeated vertically using `stride(from:to:by:)` in the canvas
- Bloom effect: `.shadow(color: .green.opacity(0.3), radius: 4)` on the Canvas view

**Landscape adaptation:** The five channels spread wider horizontally, showing approximately 4 seconds of history (240 samples) instead of 2 seconds. The channels become taller and more readable. Channel labels move to the left edge as a vertical sidebar. This landscape layout closely matches a real oscilloscope's aspect ratio and feels most natural.

**Distinguishing feature:** The oscilloscope is the only variant that shows the temporal history of every metric simultaneously. Other variants show current state; this one shows the last 2-4 seconds of trajectory. This is extremely valuable for identifying patterns: periodic fidgeting (visible as regular oscillation), gradual drift (visible as a slowly rising baseline), and sudden posture breaks (visible as sharp spikes). The CRT phosphor aesthetic -- green glow on black, scan lines, bloom -- is visually striking and distinct from every other health app on the market.

---

### Variant 40: Load Diagram

**Category:** Flight / Engineering Instruments

**Concept:** A structural engineering stress diagram applied to a simplified beam model of the human spine. The visualization shows a vertical beam (representing the spine) supported at the base (pelvis), with loads and forces applied at various points. Stress is visualized using color-coded regions along the beam (green = no stress, through yellow/orange to red = high stress) and force arrows showing the direction and magnitude of each postural deviation. The aesthetic references structural analysis software used by civil and mechanical engineers.

**Real-time mode:** The spine beam is a tall, narrow rectangle (20pt wide x 300pt tall) centered in the view, oriented vertically with the base at the bottom (pelvis) and the top at the head. The beam has three annotated cross-section markers at the cervical (top), thoracic (middle), and lumbar (bottom) regions, drawn as short horizontal lines through the beam.

**Stress coloring:** The beam is divided into a vertical gradient of stress colors. Each section's color is computed from the metrics that affect it:
- **Cervical (top third):** Primarily affected by head drop and forward creep. Color = interpolated from green (zero) to red (threshold) based on `max(headDrop, forwardCreep) * 0.7 + shoulderRounding * 0.3`.
- **Thoracic (middle third):** Primarily affected by shoulder rounding and forward creep. Color = interpolated based on `max(shoulderRounding, forwardCreep) * 0.7 + twist * 0.3`.
- **Lumbar (bottom third):** Affected by all metrics (as the base bears all loads). Color = interpolated based on `overallScore` inverted.

**Force arrows:** Five arrows emanate from specific points on the beam, each representing one metric:

| Metric | Arrow Placement | Direction |
|---|---|---|
| Forward Creep | Middle of the beam, pointing horizontally rightward (forward) | Length = `forwardCreep * maxArrowLength`. A right-pointing horizontal arrow emerging from the thoracic region. |
| Head Drop | Top of the beam, pointing downward | A downward vertical arrow from the beam's top end. Length = `headDrop * maxArrowLength`. |
| Shoulder Rounding | Top third of the beam, pointing inward (two arrows, one from each side pointing toward center) | Two short horizontal arrows pointing inward at the shoulder level. Length = `shoulderRounding * maxArrowLength`. |
| Lateral Lean | Middle of the beam, pointing left or right | A horizontal arrow from the beam center in the lean direction. Length = `lateralLean * maxArrowLength`. |
| Twist | Two arrows at the top and bottom of the beam, pointing in opposite horizontal directions | A torque/couple indicator: top arrow points right, bottom arrow points left (or vice versa). Length = `twist * maxArrowLength`. |

Arrow design: Each arrow is a thin line (2pt) with a triangular arrowhead, drawn in the same color as the stress zone it originates from. Arrow labels show the metric name and force magnitude in engineering notation (e.g., "FWD: 0.73").

**Support symbol:** At the base of the beam, a standard engineering support symbol (a triangle with horizontal ground line) indicates that the pelvis/base is the fixed support point. A reaction force arrow points upward from this support, whose length = sum of all downward/compressive forces.

A faint dashed vertical line (the "neutral axis") runs through the beam's center, and the beam bends away from this line proportionally to the metrics -- a subtle Bezier curve where the control point offsets represent the bending moment diagram.

**Alert mode:** All force arrows except the worst offender's shrink to 30% opacity and minimum length. The worst offender's arrow enlarges (thicker line, larger arrowhead, 1.5x length) and pulses between its stress color and white. The section of the beam affected by this force flashes with a cross-hatched overlay pattern (diagonal lines at 45 degrees) -- the engineering convention for indicating a critical stress zone. The metric name appears in a rectangular label with a border (engineering drawing style callout) connected to the arrow by a leader line. The countdown timer appears as a "load factor" gauge: a small horizontal bar labeled "LOAD" that fills from left to right, becoming fully red when time expires.

**Key SwiftUI techniques:**
- `Canvas` for the beam, force arrows, support symbol, and stress gradient
- Beam stress gradient: `context.fill(beamPath, with: .linearGradient(Gradient(stops: stressStops), startPoint: .bottom, endPoint: .top))` where `stressStops` are computed from the three-section stress values
- Force arrows: custom `Path` for each arrow (line + triangle arrowhead), scaled and positioned per metric
- Beam bending: the beam's side edges are Bezier curves rather than straight lines. Control point offsets = `lateralLean * maxDeflection` (lateral bending) and `forwardCreep * maxDeflection` (forward bending, shown as beam width variation)
- Cross-hatch overlay: `Path` with `stride(from:to:by:)` generating diagonal lines, clipped to the critical beam section
- Engineering callout: a `Path` drawing a rectangular border with a leader line (horizontal line + angled line to arrow)
- `.animation(.easeInOut(duration: 0.5))` for arrow growth/shrink transitions

**Landscape adaptation:** The beam rotates to horizontal orientation (a horizontal beam supported at the left end, loads applied downward). This is the standard engineering beam diagram orientation. Force arrows point downward/sideways. The horizontal layout fills the landscape width naturally and looks identical to a structural engineering textbook illustration. Engineering callout labels appear above and below the beam.

**Distinguishing feature:** This is the only variant that treats the human body as a literal engineering structure under load. The force arrows, bending moment visualization, stress coloring, and support symbols are drawn directly from structural analysis conventions. For users with engineering backgrounds, this variant communicates with precision and authority: they can immediately read the "structural analysis" of their own body. The bending beam visualization (where the beam itself curves under load) directly represents what is happening to the spine, making this both a metaphor and a simplified physical model.

---

## Design Principles Across Variants 21-40

### Visual Hierarchy in Both Modes

All twenty variants follow the same two-mode information architecture:

1. **Real-time mode** prioritizes simultaneous display of all five metrics with roughly equal visual weight. The user can scan all five at a glance. Overall posture quality is encoded in aggregate visual properties (total area, symmetry, color temperature, deformation magnitude).

2. **Alert mode** aggressively focuses on the single worst offender. The transition from real-time to alert mode always involves: (a) dimming/shrinking the four non-offending metrics, (b) enlarging/highlighting the worst offender, (c) displaying the metric name in text, and (d) showing the countdown timer. The specific animation vocabulary varies per variant but the information flow is identical.

### Color Strategy

All variants use the same semantic color progression:
- **Good / at rest:** Cool, calm hues (teal, blue, green, or neutral gray)
- **Degrading:** Warm shift (amber, orange)
- **At threshold / bad:** Alert hues (red, but not alarming red -- a warm coral)
- **System adaptive:** All color references use SwiftUI semantic colors (`.primary`, `.secondary`) or custom colors defined for both light and dark `ColorScheme`

### Settings Gear Placement

Every variant includes a settings gear icon (SF Symbol `gearshape.fill`) as the single entry point to controls. Default placement: top-trailing corner, 20pt from safe area edges, in `Color.secondary` to avoid competing with the visualization. In alert mode, the gear persists but does not animate or change.

### Animation Timing

- Metric value changes: `.spring(response: 0.4-0.6, dampingFraction: 0.6-0.75)` -- responsive but not twitchy
- Mode transitions (real-time to alert): `.easeInOut(duration: 0.5-0.8)` -- deliberate, noticeable
- Countdown timer: `.linear` -- constant rate, predictable
- Idle/ambient animations: sinusoidal at 3-5 second periods -- calming, unobtrusive

### Accessibility Considerations

- All metric values are exposed as accessibility labels on their visual representations
- Color is never the sole differentiator -- shape, position, size, and labels always provide redundant encoding
- VoiceOver announces the worst offender name and countdown time in alert mode
- Dynamic Type affects the metric labels and countdown text (but not the visualization geometry)
