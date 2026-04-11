import Foundation

/// A rolling buffer of the most recent ~3 seconds of `PoseObservation`
/// frames, filtered to the joints relevant to sip detection.
///
/// This is a sibling of `SipDetector` used only by the training-mode
/// labeling workflow. It subscribes to the same `poseObservationPublisher`
/// that `SipDetector` does (see `AppModel`), and when the detector
/// confirms a sip the AppModel calls `snapshot()` to grab a frozen copy
/// of the rolling window to attach to the training record.
///
/// ## Design notes
///
/// - **Independent of `SipDetector`.** The buffer is additive and can be
///   removed without touching the detector. Trivial to rip out once the
///   training-mode feature is retired.
/// - **Joint filter.** Only the 9 joints involved in sip-detection
///   reasoning are retained (nose, shoulders, wrists, elbows, eyes).
///   This keeps per-frame records small and the total buffer cheap to
///   clone in `snapshot()`.
/// - **Thread safety.** Not internally synchronised. Call `process(_:)`
///   and `snapshot()` / `reset()` from the same thread — typically the
///   pipeline publisher sink on `AppModel`, which is serialised. If you
///   need cross-thread access later, wrap accesses in an actor.
/// - **Window policy.** After each `process`, frames older than
///   `frames.last!.timestamp - windowSeconds` are dropped from the
///   front. Count-based caps are avoided so the window is purely
///   time-based regardless of the publisher's frame rate.
public final class SipTrainingBuffer {

    // MARK: - Types

    /// A single pose observation retained in the buffer, filtered down
    /// to sip-relevant joints.
    public struct Frame: Equatable {
        public let timestamp: TimeInterval
        public let keypoints: [Keypoint]

        public init(timestamp: TimeInterval, keypoints: [Keypoint]) {
            self.timestamp = timestamp
            self.keypoints = keypoints
        }
    }

    // MARK: - Public Interface

    /// How many seconds of history to retain. Default 3.0s matches the
    /// plan for the training-mode confirmation popup.
    public var windowSeconds: TimeInterval

    /// Current frames in the buffer, oldest first. Exposed read-only
    /// primarily for tests and the debug overlay. Use `snapshot()` when
    /// you want a detached copy for attaching to a training record.
    public private(set) var frames: [Frame] = []

    // MARK: - Filter

    /// Joints that matter for sip detection. Everything else is dropped
    /// on ingest.
    public static let relevantJoints: Set<Joint> = [
        .nose,
        .leftEye, .rightEye,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
    ]

    // MARK: - Initialization

    public init(windowSeconds: TimeInterval = 3.0) {
        self.windowSeconds = windowSeconds
    }

    // MARK: - Public Methods

    /// Ingest a frame. Filters keypoints, appends, and trims anything
    /// older than `windowSeconds` from the newest frame.
    public func process(_ observation: PoseObservation) {
        let filtered = observation.keypoints.filter {
            Self.relevantJoints.contains($0.joint)
        }
        let frame = Frame(
            timestamp: observation.timestamp,
            keypoints: filtered
        )
        frames.append(frame)

        // Trim: drop any frames older than (latest - windowSeconds).
        // Uses the *newest* frame's timestamp as the reference so the
        // window is anchored to the detector's frame of reference, not
        // wall-clock time. This keeps the buffer consistent even if
        // observation timestamps come from a synthetic / replayed clock.
        let cutoff = frame.timestamp - windowSeconds
        if frames.first?.timestamp ?? .infinity < cutoff {
            frames.removeAll { $0.timestamp < cutoff }
        }
    }

    /// Returns a detached (value-copied) snapshot of the current rolling
    /// window. Safe to hand off to a training record without worrying
    /// about subsequent `process` calls mutating the returned frames.
    public func snapshot() -> [Frame] {
        frames
    }

    /// Clears the buffer. Call when the detector resets or when training
    /// mode is turned off.
    public func reset() {
        frames.removeAll(keepingCapacity: true)
    }
}
