//
//  CameraPreviewRemote.swift
//  QuantWatch Watch App
//
//  Showing the camera's view on the phone from the wrist.
//

import Foundation

/// Showing the camera's view on the phone, to check you're in frame without reaching for a phone
/// propped out of reach (2026-10-20). The phone holds whether it's shown, so the Watch asks, and
/// the phone answers with what it now shows. The phone's `WatchConnectivityService` reads and
/// writes the other side of these messages.
enum CameraPreviewRemote {

    /// Asks the phone to show the camera's view, or to hide it.
    static func request(show: Bool) -> [String: Any] {
        ["type": "showCameraPreview", "show": show]
    }

    /// Whether the phone says the view is showing, or nil when the message isn't its answer.
    static func shown(from message: [String: Any]) -> Bool? {
        guard message["type"] as? String == "cameraPreview" else { return nil }
        return message["shown"] as? Bool
    }

    /// The button says what a tap will do.
    static func buttonTitle(phoneShows: Bool) -> String {
        phoneShows ? "Hide camera" : "Show camera"
    }
}
