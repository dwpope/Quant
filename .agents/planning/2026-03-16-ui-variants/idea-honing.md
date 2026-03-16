# Idea Honing: Posture Metrics UI Variants

Requirements clarification Q&A for the posture metrics UI variants project.

---

## Q1: What is the primary use context?

When the user is on the monitoring screen, what are they typically doing? For example:
- **Glanceable background** — the phone is propped up nearby and they glance at it occasionally while working
- **Active monitoring** — they're actively watching the screen to correct posture in real-time
- **Post-session review** — they check posture quality after a work session

This matters because it determines information density, text size, animation prominence, etc.

**A1:** Two primary modes: **glanceable background** (phone propped up while working) and **post-session review** (checking posture quality after a work session). This suggests the UI needs to work at two levels — a bold, at-a-glance summary visible from a distance, and a detailed drill-down for reviewing session data.

---

## Q2: What level of metric detail should be visible at a glance?

When you glance at the phone from across your desk, what's the most important thing to see?

- **Overall posture quality only** — a single score, color, or icon (e.g., green = good, red = bad)
- **Overall + worst offender** — overall quality plus which specific metric is off (e.g., "forward lean")
- **All 5 metrics at once** — each metric individually visible, even from a distance
- **State + time** — how long you've been in good/drifting/bad posture

**A2:** **Overall + worst offender + nudge countdown.** At a glance: overall posture quality, which specific metric is the worst offender, and a visible countdown when poor posture has been triggered (i.e., drifting/bad state with pending nudge timer). This gives three layers of glanceable info.

---

## Q3: What format should the 10 variants be delivered in?

How would you like to evaluate and compare the variants?

- **ASCII/text wireframes** — quick layout sketches described in markdown
- **Annotated SwiftUI code** — actual SwiftUI view code you can drop in and run
- **Detailed written descriptions with mockup diagrams** — prose + mermaid/ASCII visuals
- **A mix** — written concept + SwiftUI prototype code for each

**A3:** **Annotated SwiftUI code** — actual runnable views for each variant. Each variant should have two visual modes:
1. **Real-time mode** (good posture) — shows all 5 metrics live
2. **Alert mode** (drifting/bad posture triggered) — transitions to show the worst offender prominently + nudge countdown timer

The transition between modes should be animated and part of each variant's design language.

---

## Q4: Should the camera preview be part of the variant designs?

The app currently has a toggleable camera preview (rear ARView or front camera feed) behind the UI. Should the variants:

- **Assume camera preview is visible** — design as an overlay on top of the live camera feed
- **Assume camera preview is hidden** — design as a standalone full-screen UI (solid background)
- **Support both** — design works whether camera is on or off behind it

**A4:** Camera toggle should exist but can be tucked behind a settings interaction to keep the UI clean. Variants should design primarily for a **solid background** (camera hidden by default), but the design should still work as an overlay when camera is toggled on. The camera toggle, along with other controls (recalibrate, settings, etc.), can live behind a secondary interaction (long press, swipe, menu) rather than cluttering the main view.

---

## Q5: What visual style / aesthetic are you drawn to?

This will help differentiate the 10 variants. Are any of these appealing, or should I cover a broad range?

- **Minimal / typographic** — clean text, lots of whitespace, like Apple Health
- **Data-rich / dashboard** — gauges, charts, rings, like a car instrument cluster
- **Organic / ambient** — gradients, particles, breathing animations, mood-based
- **Gamified** — scores, streaks, achievements, progress bars
- **Something else** — describe your taste or reference apps you like

**A5:** **Broad range.** The 10 variants should span diverse aesthetic styles — minimal, data-rich, organic, gamified, and beyond — so the user can compare fundamentally different approaches and pick the direction that resonates.

---

## Q6: What about the post-session review mode?

You mentioned post-session review as a second use context. Should each variant include a review/history view, or is the focus purely on the live monitoring screen for now?

- **Live monitoring only** — each variant is just the real-time view; review comes later as a separate effort
- **Both** — each variant includes a concept for how session history/summary would look in the same design language
- **Light touch** — the live view includes a small summary stat (e.g., "82% good posture today") but no full review screen

**A6:** **Live monitoring only.** Each variant focuses on the real-time monitoring view. Post-session review will be a separate effort later.

---

## Q7: Should the variants include the existing toolbar controls (haptic picker, test nudge, recalibrate, settings)?

The current monitoring screen has a bottom toolbar with several controls. For the variants:

- **Include them** — integrate these controls into each variant's design language
- **Exclude them** — focus purely on the metrics display; controls will be handled separately
- **Minimal** — include only recalibrate and settings; drop debug controls like test nudge and haptic picker

**A7:** **Place them into settings.** All controls (haptic picker, test nudge, recalibrate, camera toggle) should live behind a settings interaction, keeping the monitoring view clean and focused entirely on posture metrics display. Each variant just needs a single entry point to settings (e.g., gear icon, long press, swipe gesture).

---

## Q8: Screen orientation and device target?

Should the variants be designed for:

- **Portrait iPhone only** — standard phone held/propped upright
- **Landscape iPhone** — phone on its side (e.g., propped on a desk with a stand)
- **Both orientations**
- **iPad support too**

**A8:** **Both orientations** (portrait and landscape iPhone). Variants should adapt their layout to work well in either orientation — portrait when held, landscape when propped on a desk stand.

---

## Q9: Color and dark/light mode?

- **Dark mode only** — optimized for a single dark appearance
- **Light mode only** — optimized for a single light appearance
- **System adaptive** — supports both, follows system setting
- **Always-on display style** — very dim/minimal to save battery when propped up

**A9:** **System adaptive.** Variants should support both dark and light mode, following the system setting. Use semantic SwiftUI colors and materials to ensure both appearances work well.

---

## Q10: Should the variants use only built-in SwiftUI capabilities, or are third-party libraries acceptable?

- **SwiftUI only** — no external dependencies; SF Symbols, built-in shapes, Canvas, etc.
- **Allow Charts framework** — SwiftUI + Apple's Swift Charts for any graph/chart elements
- **Third-party OK** — open to libraries like Lottie for animations, custom charting libs, etc.

**A10:** **Allow Swift Charts + third-party libraries OK, preference for Apple-native.** SwiftUI + Apple's Swift Charts framework preferred. Third-party libraries are allowed where they add significant value (e.g., Lottie for animations, custom 3D libs), but Apple-native frameworks (SceneKit, RealityKit, SpriteKit, Core Animation, Metal) should be the first choice. The user is particularly interested in visual/3D representations that give a direct visual indication of their posture — e.g., a 3D avatar/skeleton that mirrors their pose, an abstract body silhouette that distorts with bad posture, SceneKit/RealityKit 3D models, etc. Some variants should explore this direction.

---

## Q11: How should the 10 variants be structured in the codebase?

- **Separate files** — one SwiftUI file per variant (e.g., `Variant1View.swift`, `Variant2View.swift`) with a picker/tab to switch between them
- **Single showcase file** — all 10 in one file with a navigation list
- **Preview-only** — each as a standalone `#Preview` block so you can flip through them in Xcode previews

**A11:** **Single showcase file.** All 10 variants in one file with a navigation list to browse and switch between them. This makes it easy to compare side-by-side in the running app.

---

## Q12: Should the variants use mock/sample data, or wire into the live pipeline?

- **Mock data** — hardcoded sample values with simulated state transitions so they work standalone
- **Live data** — wire directly into `AppModel` / `Pipeline` published properties
- **Both** — live data when running the app, mock data for Xcode previews

**A12:** **Both, with a toggle.** The showcase view should include a toggle to switch between:
1. **Mock data** — hardcoded sample values with simulated state transitions for standalone evaluation without camera/pipeline
2. **Live data** — wired into `AppModel` / `Pipeline` published properties for real-time posture feedback

This lets the user evaluate variants visually with mock data first, then test with real posture tracking.

---

I think we've covered the key requirements. Here's a summary of what's been established:

**Summary:**
- 60 unique UI variants spanning diverse visual styles (minimal, data-rich, organic, gamified, 3D, etc.)
- **Two visual modes per variant**: real-time (all 5 metrics live) → alert mode (worst offender + nudge countdown) with animated transition
- Glanceable from a distance when propped up
- All controls tucked behind a settings entry point — clean monitoring view
- Both portrait and landscape iPhone orientations
- System adaptive dark/light mode
- SwiftUI + Swift Charts allowed; 3D/visual body representations encouraged for some variants
- Single showcase file with navigation list to browse all 10
- Mock data for standalone evaluation
- Live monitoring view only (no session review for now)
