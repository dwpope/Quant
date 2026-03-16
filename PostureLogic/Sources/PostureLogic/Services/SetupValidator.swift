import simd
import Foundation

/// Result of validating the user's physical setup before/during calibration.
public enum SetupValidationResult: Equatable {
    case valid
    case tooClose(String)
    case tooFar(String)
    case badAngle(String)
    case bodyNotFullyVisible(String)
}

/// Validates that the user is positioned correctly for posture tracking.
/// Checks distance, angle, and body visibility before calibration begins.
public struct SetupValidator: DebugDumpable {

    public init() {}

    /// Validate the user's setup from a single pose sample.
    /// Checks are performed in priority order; the first failure is returned.
    public func validate(sample: PoseSample, baseline: Baseline?) -> SetupValidationResult {
        // 1. Body visibility — head and both shoulders must be detected
        if sample.trackingQuality == .lost {
            return .bodyNotFullyVisible("Tracking lost. Make sure your head and shoulders are visible.")
        }
        let origin = SIMD3<Float>(0, 0, 0)
        if sample.leftShoulder == origin && sample.rightShoulder == origin {
            return .bodyNotFullyVisible("Shoulders not detected. Make sure your upper body is fully visible.")
        }

        // 2. Distance check
        switch sample.depthMode {
        case .depthFusion:
            let z = sample.shoulderMidpoint.z
            if z < 0.5 {
                return .tooClose(String(format: "Distance: %.2fm. Move back to at least 0.5m.", z))
            }
            if z > 1.5 {
                return .tooFar(String(format: "Distance: %.2fm. Move closer to within 1.5m.", z))
            }
        case .twoDOnly:
            let w = sample.shoulderWidthRaw
            if w > 0.5 {
                return .tooClose(String(format: "Shoulder width ratio: %.2f. Move further away.", w))
            }
            if w < 0.15 {
                return .tooFar(String(format: "Shoulder width ratio: %.2f. Move closer.", w))
            }
        }

        // 3. Angle check
        if abs(sample.torsoAngle) > 30 {
            return .badAngle(String(format: "Torso angle: %.0f°. Face the camera more directly.", sample.torsoAngle))
        }

        return .valid
    }

    // MARK: - DebugDumpable

    public var debugState: [String: Any] {
        ["type": "SetupValidator"]
    }
}
