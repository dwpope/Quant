import ARKit
import Foundation

/// Whether the rear camera is usable, in terms the person holding the phone can act on.
///
/// Until 2026-10-01 a rear camera that couldn't run was invisible: `ARSessionService` published
/// a failed state nobody subscribed to, and its frame timer logged "No frames received yet"
/// every 2 seconds, forever, over a blank screen. The front camera already had a recovery
/// screen (`CameraPermissionView`). This is the rear camera's equivalent. The decisions are
/// pure functions so they can be tested without a camera.
enum RearCameraStatus: Equatable {
    case ok
    /// Camera permission is off. Only Settings can fix it.
    case unauthorized
    /// ARKit can't run, or no image has arrived. Retrying, or switching camera, may help.
    case unavailable(reason: String)

    /// How long a fresh session may go without a single frame before it's shown as a problem.
    /// ARKit usually delivers the first frame well within a second.
    static let noFramesGracePeriod: TimeInterval = 6

    /// What an ARKit failure means for the person. Nil when the service restarts the session
    /// itself (sensor or tracking failures): if that doesn't work, no frames arrive, and
    /// ``afterFrameCheck(secondsSinceStart:receivedAnyFrame:)`` reports it instead.
    static func after(error: Error) -> RearCameraStatus? {
        let error = error as NSError
        if error.domain == ARError.errorDomain, let code = ARError.Code(rawValue: error.code) {
            switch code {
            case .cameraUnauthorized:
                return .unauthorized
            case .sensorFailed, .worldTrackingFailed:
                return nil
            default:
                return .unavailable(reason: error.localizedDescription)
            }
        }
        return .unavailable(reason: error.localizedDescription)
    }

    /// What it means that the session has run for `secondsSinceStart` seconds. Only a session
    /// that has never delivered a frame is a problem here: a stall after frames have flowed is
    /// the service's resource recovery's job.
    static func afterFrameCheck(secondsSinceStart: TimeInterval, receivedAnyFrame: Bool) -> RearCameraStatus? {
        guard !receivedAnyFrame, secondsSinceStart >= noFramesGracePeriod else { return nil }
        return .unavailable(reason: "The rear camera isn't sending any images.")
    }
}
