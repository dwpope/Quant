# Rough Idea: Posture Metrics UI Variants

Create 60 unique and novel UI variations for displaying posture metrics in the Quant app. The goal is to explore diverse visual approaches for presenting posture data so the user can choose which design direction to pursue.

## Context

The Quant app is a SwiftUI-based posture monitoring app that uses the device camera + Vision framework to track body pose in real-time. Currently, the main monitoring screen is a bare placeholder — all metric display lives in a developer debug overlay (`DebugOverlayView`).

## Available Posture Data

- **5 core metrics** (each with raw values and calibrated deltas vs. baseline):
  - Forward Creep (leaning toward camera)
  - Head Drop (head dropping downward)
  - Shoulder Rounding (forward torso lean)
  - Lateral Lean (side-to-side lean)
  - Twist (shoulder rotation)
- **Posture state machine**: absent → calibrating → good ⇌ drifting(since:) → bad(since:)
- **Nudge decisions**: none / pending(reason, timeRemaining) / fire(reason) / suppressed(reason)
- **Movement**: movementLevel (0–1), headMovementPattern (.still/.smallOscillations/.largeMovements/.erratic)
- **Tracking quality**: camera mode, depth mode, confidence, FPS
- **Calibration baseline**: reference "good posture" snapshot

## Requirements

- 60 distinct UI variants, each with a unique visual concept
- Designed for the SwiftUI monitoring screen
- Should effectively communicate posture quality to the user
- Each variant should be novel/differentiated from the others
