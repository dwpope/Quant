import AVFoundation

/// Whether the camera can be used at all.
enum CameraAccess {
    /// Refused: denied in Settings, or restricted. Retrying can't help; the person has to go to
    /// Settings, so the app shows a screen saying so.
    static func isRefused(_ status: AVAuthorizationStatus) -> Bool {
        status == .denied || status == .restricted
    }
}
