import Foundation
import PostureLogic

/// A training-mode sidecar record that captures exactly what the sip
/// detector "saw" at the moment it confirmed an event.
///
/// Joined back to a `SipEvent` by `id`. Persisted in its own daily JSON
/// file (`sip-training-YYYY-MM-DD.json`) by `SipTrainingStore`, so the
/// main `sips-YYYY-MM-DD.json` stays lean and the training sidecar can
/// be wiped independently.
///
/// The on-disk shape is deliberately compact (short field names inside
/// `Point`, flat arrays) because a 3-second buffer at ~30fps × 9 joints
/// is around 800 keypoints per record.
struct SipTrainingRecord: Codable, Identifiable {

    // MARK: - Join key

    /// Same UUID as the corresponding `SipEvent`. This is how exports
    /// stitch labels to feature vectors.
    let id: UUID

    // MARK: - Capture metadata

    /// Wall-clock time (seconds since 1970) when the training record was
    /// captured — i.e. when `SipDetector.onSipConfirmed` fired.
    let capturedAt: TimeInterval

    // MARK: - Detector signals at confirmation time

    let proximityScore: Float
    let velocityScore: Float
    let durationScore: Float
    /// `"leftWrist"` / `"rightWrist"` while a candidate was active,
    /// otherwise `nil`.
    let activeWrist: String?

    /// Exact thresholds the detector was using at the moment of the
    /// event. Allows offline replay with the original configuration.
    let thresholdsUsed: SipThresholds

    // MARK: - Rolling pose buffer

    /// The ~3s rolling buffer as of the moment the event was confirmed.
    /// Oldest frame first.
    let poseFrames: [PoseFrame]

    // MARK: - Nested types

    struct PoseFrame: Codable, Equatable {
        /// Absolute observation timestamp (seconds, same clock the
        /// detector saw). Keeping it absolute rather than relative to
        /// `capturedAt` avoids precision loss on round-trip and makes
        /// downstream analysis easier.
        let t: TimeInterval
        let keypoints: [Point]
    }

    struct Point: Codable, Equatable {
        /// `Joint.rawValue`, e.g. "leftWrist".
        let j: String
        let x: Double
        let y: Double
        /// Per-keypoint confidence from the Vision model.
        let c: Float
    }

    // MARK: - Construction helpers

    /// Builds a record from the outputs `AppModel` already has on hand
    /// when `SipDetector.onSipConfirmed` fires.
    init(
        id: UUID,
        capturedAt: TimeInterval,
        scores: SipDetector.Scores,
        thresholds: SipThresholds,
        bufferFrames: [SipTrainingBuffer.Frame]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.proximityScore = scores.proximity
        self.velocityScore = scores.velocity
        self.durationScore = scores.duration
        self.activeWrist = scores.activeWrist
        self.thresholdsUsed = thresholds
        self.poseFrames = bufferFrames.map { frame in
            PoseFrame(
                t: frame.timestamp,
                keypoints: frame.keypoints.map { kp in
                    Point(
                        j: kp.joint.rawValue,
                        x: Double(kp.position.x),
                        y: Double(kp.position.y),
                        c: kp.confidence
                    )
                }
            )
        }
    }
}
