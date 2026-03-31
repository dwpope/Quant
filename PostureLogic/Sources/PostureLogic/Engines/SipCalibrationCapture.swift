import CoreGraphics
import Foundation

/// Records raw sip gesture data and derives personalised `SipThresholds`.
///
/// ## Usage
///
/// 1. Present the "Record Sip" UI.
/// 2. When the user taps "Record Sip", call `beginCapture()`.
/// 3. Feed observations via `process(_:)` for the next 10 seconds.
/// 4. Call `endCapture()` — the engine stores the sample internally.
/// 5. Repeat until `isReady` is `true` (5 sips captured).
/// 6. Read `derivedThresholds` and assign to `SipDetector.thresholds`.
///
/// After 5 sips, `derivedThresholds` returns thresholds derived from
/// the min/max of observed values with a 20% margin for robustness.
public final class SipCalibrationCapture {

    // MARK: - Public State

    /// Number of completed sip recordings. At least 5 required before thresholds
    /// can be derived, but more recordings improve accuracy.
    public private(set) var recordedSipCount: Int = 0

    /// True when 5 or more sips have been recorded and thresholds can be derived.
    public var isReady: Bool { recordedSipCount >= requiredSipCount }

    /// Personalised thresholds derived from the recorded sips.
    /// Returns `nil` until `isReady` is `true`.
    public var derivedThresholds: SipThresholds? {
        guard isReady else { return nil }
        return computeThresholds()
    }

    // MARK: - Configuration

    private let requiredSipCount = 5
    private let captureDuration: TimeInterval = 10.0

    // MARK: - Capture State

    private var isCapturing = false
    private var captureStartTime: TimeInterval?
    private var currentSipSamples: [RawCaptureSampleInternal] = []

    // MARK: - Recorded Data

    private struct SipSample {
        let minProximity: Float      // minimum distance/shoulderWidth during sip
        let maxVelocity: Float       // peak normalised velocity during sip
        let duration: TimeInterval   // total duration wrist was in proximity zone
    }

    private var recordedSamples: [SipSample] = []

    // MARK: - Per-Frame Tracking

    private var previousWristPos: CGPoint?
    private var previousTimestamp: TimeInterval?
    private var proximityEnteredAt: TimeInterval?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Start a 10-second capture window. Call when the user taps "Record Sip".
    public func beginCapture(at timestamp: TimeInterval = Date().timeIntervalSince1970) {
        isCapturing = true
        captureStartTime = timestamp
        currentSipSamples = []
        previousWristPos = nil
        previousTimestamp = nil
        proximityEnteredAt = nil
    }

    /// Process one observation during an active capture window.
    /// Safe to call when not capturing — returns immediately.
    public func process(_ observation: PoseObservation) {
        guard isCapturing, let startTime = captureStartTime else { return }
        let t = observation.timestamp

        // Auto-end after 10 seconds
        if t - startTime >= captureDuration {
            endCapture(at: t)
            return
        }

        guard
            let nose = observation.keypoints.first(where: { $0.joint == .nose }),
            let leftShoulder = observation.keypoints.first(where: { $0.joint == .leftShoulder }),
            let rightShoulder = observation.keypoints.first(where: { $0.joint == .rightShoulder })
        else { return }

        let shoulderWidth = abs(leftShoulder.position.x - rightShoulder.position.x)
        guard shoulderWidth > 0 else { return }

        // Use whichever wrist has higher confidence
        let leftWrist = observation.keypoints.first(where: { $0.joint == .leftWrist })
        let rightWrist = observation.keypoints.first(where: { $0.joint == .rightWrist })

        let wrist: Keypoint?
        if let l = leftWrist, let r = rightWrist {
            wrist = l.confidence >= r.confidence ? l : r
        } else {
            wrist = leftWrist ?? rightWrist
        }

        guard let w = wrist else { return }

        // Proximity
        let dx = w.position.x - nose.position.x
        let dy = w.position.y - nose.position.y
        let distance = sqrt(dx * dx + dy * dy)
        let normalizedDist = Float(distance / shoulderWidth)

        // Velocity
        var normalizedVelocity: Float = 0
        if let prev = previousWristPos, let prevT = previousTimestamp {
            let dt = t - prevT
            if dt > 0 {
                let vx = w.position.x - prev.x
                let vy = w.position.y - prev.y
                let speed = sqrt(vx * vx + vy * vy)
                normalizedVelocity = Float(speed / shoulderWidth / dt)
            }
        }

        previousWristPos = w.position
        previousTimestamp = t

        // Track proximity entry/exit for duration measurement
        let closeEnough = normalizedDist < 0.5  // permissive zone during capture
        if closeEnough, proximityEnteredAt == nil {
            proximityEnteredAt = t
        }

        let sample = RawCaptureSample(
            proximity: normalizedDist,
            velocity: normalizedVelocity,
            timestamp: t
        )
        currentSipSamples.append(RawCaptureSampleInternal(raw: sample, proximityEnteredAt: proximityEnteredAt))

        if !closeEnough {
            proximityEnteredAt = nil
        }
    }

    /// End the current capture window and store the sample.
    /// Also called automatically when 10 seconds elapse.
    public func endCapture(at timestamp: TimeInterval = Date().timeIntervalSince1970) {
        guard isCapturing else { return }
        isCapturing = false

        // Summarise this sip: minimum proximity, peak velocity, total proximity duration
        guard !currentSipSamples.isEmpty else { return }

        let minProximity = currentSipSamples.map(\.raw.proximity).min() ?? 1.0
        let maxVelocity = currentSipSamples.map(\.raw.velocity).max() ?? 0.0

        // Duration = how long the wrist stayed close during this capture
        let duration: TimeInterval
        if let entered = proximityEnteredAt {
            duration = timestamp - entered
        } else {
            // Use the span of close frames as a proxy
            let closeFrames = currentSipSamples.filter { $0.raw.proximity < 0.5 }
            if closeFrames.count >= 2 {
                duration = (closeFrames.last?.raw.timestamp ?? timestamp) - (closeFrames.first?.raw.timestamp ?? timestamp)
            } else {
                duration = 1.0
            }
        }

        recordedSamples.append(SipSample(
            minProximity: minProximity,
            maxVelocity: maxVelocity,
            duration: max(duration, 0.5)
        ))
        recordedSipCount = recordedSamples.count
        currentSipSamples = []
        captureStartTime = nil
    }

    /// Reset all recorded data. Used if the user wants to redo calibration.
    public func reset() {
        recordedSipCount = 0
        recordedSamples = []
        currentSipSamples = []
        isCapturing = false
        captureStartTime = nil
        previousWristPos = nil
        previousTimestamp = nil
        proximityEnteredAt = nil
    }

    // MARK: - Threshold Derivation

    private func computeThresholds() -> SipThresholds {
        var t = SipThresholds()

        // Proximity threshold: minimum observed proximity + 20% margin
        // (lower proximity value = closer to face; we add margin to be permissive)
        let minObservedProximity = recordedSamples.map(\.minProximity).min() ?? 0.35
        t.proximityThreshold = minObservedProximity * 1.2

        // Velocity threshold: min observed peak velocity * 0.8 (slightly below min)
        let minObservedVelocity = recordedSamples.map(\.maxVelocity).min() ?? 0.008
        t.velocityThreshold = max(minObservedVelocity * 0.8, 0.002)  // floor at 0.002

        // Duration: use observed min with 20% reduction as the required minimum
        let minObservedDuration = recordedSamples.map(\.duration).min() ?? 1.0
        t.minDuration = max(minObservedDuration * 0.8, 0.5)

        return t
    }
}

// MARK: - Internal types

private struct RawCaptureSample {
    let proximity: Float
    let velocity: Float
    let timestamp: TimeInterval
}

private struct RawCaptureSampleInternal {
    let raw: RawCaptureSample
    let proximityEnteredAt: TimeInterval?
}
