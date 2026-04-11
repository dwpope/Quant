import CoreGraphics
import Foundation

/// Detects drinking gestures from raw pose observations using a three-signal
/// scoring state machine.
///
/// ## How It Works
///
/// The detector runs a state machine on every `PoseObservation`:
///
/// ```
///  ┌──────┐  proximity  ┌───────────┐  score ≥ threshold  ┌───────────┐
///  │ IDLE │ ──────────> │ CANDIDATE │ ──────────────────> │ CONFIRMED │
///  │      │ <────────── │           │                      └─────┬─────┘
///  └──────┘  wrist far  └───────────┘                            │ SipEvent
///      ^    or timeout                                            ▼
///      └────────────────────────────── cooldown expires ── COOLDOWN
/// ```
///
/// **Three Signals:**
/// 1. **Proximity** — wrist-to-nose distance normalised against shoulder width.
///    Scale-invariant regardless of camera distance.
/// 2. **Velocity** — sips have a distinct accelerate-up, pause-near-face,
///    accelerate-down profile. Chin-resting has near-zero velocity.
/// 3. **Duration band** — 1–8 seconds of face proximity. Too short = stray
///    movement; too long = resting hand.
///
/// **Both wrists** are monitored simultaneously. Whichever crosses the
/// proximity threshold first enters candidate state. No dominant-hand config.
///
/// ## Usage
///
/// ```swift
/// let detector = SipDetector()
/// detector.onSipConfirmed = { event in
///     print("Sip detected at \(event.timestamp), duration \(event.duration)s")
/// }
/// // Feed observations from poseObservationPublisher:
/// pipeline.poseObservationPublisher
///     .sink { observation in detector.process(observation) }
/// ```
public final class SipDetector {

    // MARK: - Public Interface

    /// Called on the thread that calls `process(_:)` when a sip is confirmed.
    public var onSipConfirmed: ((SipEvent) -> Void)?

    /// Configurable thresholds. Can be replaced with personalised values from
    /// `SipCalibrationCapture.derivedThresholds` after running calibration.
    public var thresholds: SipThresholds

    /// Exposes the detector's internal state for the debug overlay.
    public var debugState: [String: Any] {
        [
            "state": stateDescription,
            "activeWrist": activeWrist.map { "\($0)" } as Any,
            "proximityScore": String(format: "%.3f", lastProximityScore),
            "velocityScore": String(format: "%.3f", lastVelocityScore),
            "durationScore": String(format: "%.1f", lastDurationScore),
            "candidateEnteredAt": candidateEnteredAt as Any,
        ]
    }

    /// Typed read-only snapshot of the detector's latest three signal
    /// scores and active wrist. Used by the training-mode label/export
    /// workflow to attach exact score values to a `SipEvent` without
    /// having to parse the formatted strings in `debugState`.
    ///
    /// Purely additive: reads existing private tracking fields, does not
    /// affect state machine behavior and is not referenced by the detector
    /// itself.
    public struct Scores: Equatable {
        public let proximity: Float
        public let velocity: Float
        public let duration: Float
        /// `"leftWrist"` / `"rightWrist"` while a candidate is active,
        /// otherwise `nil` (idle / cooldown).
        public let activeWrist: String?

        public init(
            proximity: Float,
            velocity: Float,
            duration: Float,
            activeWrist: String?
        ) {
            self.proximity = proximity
            self.velocity = velocity
            self.duration = duration
            self.activeWrist = activeWrist
        }
    }

    public var scoresSnapshot: Scores {
        Scores(
            proximity: lastProximityScore,
            velocity: lastVelocityScore,
            duration: lastDurationScore,
            activeWrist: activeWrist.map { $0.rawValue }
        )
    }

    // MARK: - State Machine

    private enum State {
        case idle
        case candidate
        case cooldown(until: TimeInterval)
    }

    private var state: State = .idle

    private var stateDescription: String {
        switch state {
        case .idle: return "idle"
        case .candidate: return "candidate"
        case .cooldown(let until): return "cooldown(until: \(String(format: "%.1f", until)))"
        }
    }

    // MARK: - Candidate State

    /// Which wrist triggered the candidate entry (nil when idle/cooldown).
    private var activeWrist: Joint?

    /// Timestamp when the wrist first entered the proximity zone.
    private var candidateEnteredAt: TimeInterval?

    // MARK: - Velocity Tracking

    /// Previous frame's wrist position (normalised by shoulder width) for
    /// computing per-frame velocity.
    private var previousLeftWristPos: CGPoint?
    private var previousRightWristPos: CGPoint?
    private var previousTimestamp: TimeInterval?

    // MARK: - Score Tracking (for debug overlay)

    private var lastProximityScore: Float = 0
    private var lastVelocityScore: Float = 0
    private var lastDurationScore: Float = 0

    // MARK: - Initialization

    public init(thresholds: SipThresholds = SipThresholds()) {
        self.thresholds = thresholds
    }

    // MARK: - Public Methods

    /// The main entry point — call this for every `PoseObservation`.
    ///
    /// Thread safety: call from a single consistent thread (e.g., the main
    /// actor task that publishes observations, or a dedicated serial queue).
    public func process(_ observation: PoseObservation) {
        let t = observation.timestamp

        // Extract relevant keypoints
        guard
            let nose = observation.keypoint(.nose),
            let leftShoulder = observation.keypoint(.leftShoulder),
            let rightShoulder = observation.keypoint(.rightShoulder)
        else { return }

        let shoulderWidth = abs(leftShoulder.position.x - rightShoulder.position.x)
        guard shoulderWidth > 0 else { return }

        let leftWrist = observation.keypoint(.leftWrist)
        let rightWrist = observation.keypoint(.rightWrist)

        // Compute per-wrist signals
        let leftSignals = leftWrist.map {
            computeSignals(
                wrist: $0,
                nose: nose,
                shoulderWidth: shoulderWidth,
                previousPos: previousLeftWristPos,
                timestamp: t
            )
        }

        let rightSignals = rightWrist.map {
            computeSignals(
                wrist: $0,
                nose: nose,
                shoulderWidth: shoulderWidth,
                previousPos: previousRightWristPos,
                timestamp: t
            )
        }

        // Update previous positions for next frame's velocity calculation
        previousLeftWristPos = leftWrist.map { $0.position }
        previousRightWristPos = rightWrist.map { $0.position }
        previousTimestamp = t

        switch state {

        case .idle:
            // Enter candidate if either wrist is close to the face
            if let left = leftSignals, left.proximity {
                enterCandidate(wrist: .leftWrist, at: t)
                lastProximityScore = left.normalizedProximity
                lastVelocityScore = left.normalizedVelocity
            } else if let right = rightSignals, right.proximity {
                enterCandidate(wrist: .rightWrist, at: t)
                lastProximityScore = right.normalizedProximity
                lastVelocityScore = right.normalizedVelocity
            }

        case .candidate:
            guard let entered = candidateEnteredAt, let wrist = activeWrist else {
                state = .idle
                return
            }

            let elapsed = t - entered
            let signals: WristSignals?

            switch wrist {
            case .leftWrist:  signals = leftSignals
            case .rightWrist: signals = rightSignals
            default:          signals = nil
            }

            // If the active wrist leaves proximity, abandon candidate
            guard let s = signals, s.proximity else {
                state = .idle
                activeWrist = nil
                candidateEnteredAt = nil
                return
            }

            // Abandon if duration exceeds maximum (hand resting on chin)
            if elapsed > thresholds.maxDuration {
                state = .idle
                activeWrist = nil
                candidateEnteredAt = nil
                return
            }

            // Update debug scores
            lastProximityScore = s.normalizedProximity
            lastVelocityScore = s.normalizedVelocity
            lastDurationScore = Float(elapsed)

            // Count scored signals: proximity always counts (we're still close)
            var score: Float = 1.0  // proximity

            if s.velocity {
                score += 1.0
            }

            // Duration signal: credit once we're past minDuration
            if elapsed >= thresholds.minDuration {
                score += 1.0
            }

            if score >= thresholds.candidateScoreRequired {
                confirmSip(startedAt: entered, duration: elapsed, at: t)
            }

        case .cooldown(let until):
            if t >= until {
                state = .idle
            }
        }
    }

    /// Resets the detector to idle, clearing all in-progress state.
    public func reset() {
        state = .idle
        activeWrist = nil
        candidateEnteredAt = nil
        previousLeftWristPos = nil
        previousRightWristPos = nil
        previousTimestamp = nil
        lastProximityScore = 0
        lastVelocityScore = 0
        lastDurationScore = 0
    }

    // MARK: - Private Helpers

    private struct WristSignals {
        /// True when the wrist is within the proximity threshold.
        let proximity: Bool
        /// True when the wrist velocity exceeds the velocity threshold.
        let velocity: Bool
        /// Normalised distance value (0 = at nose, 1 = at shoulder width).
        let normalizedProximity: Float
        /// Normalised per-frame speed.
        let normalizedVelocity: Float
    }

    private func computeSignals(
        wrist: Keypoint,
        nose: Keypoint,
        shoulderWidth: CGFloat,
        previousPos: CGPoint?,
        timestamp: TimeInterval
    ) -> WristSignals {
        // Signal 1: Proximity — wrist-to-nose distance / shoulder width
        let dx = wrist.position.x - nose.position.x
        let dy = wrist.position.y - nose.position.y
        let distance = sqrt(dx * dx + dy * dy)
        let normalizedDist = Float(distance / shoulderWidth)
        let proximityHit = normalizedDist < thresholds.proximityThreshold

        // Signal 2: Velocity — normalised displacement per frame
        var normalizedVelocity: Float = 0
        if let prev = previousPos, let prevT = previousTimestamp {
            let dt = timestamp - prevT
            if dt > 0 {
                let vx = wrist.position.x - prev.x
                let vy = wrist.position.y - prev.y
                let speed = sqrt(vx * vx + vy * vy)
                normalizedVelocity = Float(speed / shoulderWidth / dt)
            }
        }
        let velocityHit = normalizedVelocity >= thresholds.velocityThreshold

        return WristSignals(
            proximity: proximityHit,
            velocity: velocityHit,
            normalizedProximity: normalizedDist,
            normalizedVelocity: normalizedVelocity
        )
    }

    private func enterCandidate(wrist: Joint, at timestamp: TimeInterval) {
        state = .candidate
        activeWrist = wrist
        candidateEnteredAt = timestamp
    }

    private func confirmSip(startedAt: TimeInterval, duration: TimeInterval, at timestamp: TimeInterval) {
        let event = SipEvent(
            timestamp: startedAt,
            duration: duration,
            confidence: nil
        )
        state = .cooldown(until: timestamp + thresholds.cooldownDuration)
        activeWrist = nil
        candidateEnteredAt = nil
        onSipConfirmed?(event)
    }
}

// MARK: - PoseObservation convenience

private extension PoseObservation {
    func keypoint(_ joint: Joint) -> Keypoint? {
        keypoints.first { $0.joint == joint }
    }
}
