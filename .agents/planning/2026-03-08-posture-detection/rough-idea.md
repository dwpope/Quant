# Rough Idea

Desk-mounted posture detection using rear camera + LiDAR when available, with graceful 2D fallback, and feedback via audio + Apple Watch.

The app monitors the user's posture from an iPhone propped on a desk. It uses Vision framework for 2D body pose detection and optionally LiDAR for 3D depth fusion. When sustained bad posture is detected (slouching, forward lean, head drop, twist), it nudges the user via audio cue and Apple Watch haptic tap.

Key aspects:
- **Precision over recall**: False alarms are more annoying than missed slouches
- **5-minute slouch threshold**: Brief posture shifts are normal; only sustained bad posture warrants nudging
- **Protocol-based architecture**: Enables mocking for tests and potential ML swap later
- **Swift Package for logic**: Keeps business logic testable and separate from UIKit/ARKit dependencies
- **Front camera support**: Enables posture tracking while user faces screen
- **No pretty UI initially**: Developer-facing debug overlay is sufficient for MVP
