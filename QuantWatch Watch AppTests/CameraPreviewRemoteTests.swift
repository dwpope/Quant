import Foundation
import Testing
import WatchConnectivity
@testable import QuantWatch_Watch_App

/// Showing the camera's view on the phone from the wrist (2026-10-20), to check you're in frame
/// without reaching for the phone. The phone holds whether it's shown, so the Watch asks, and the
/// phone answers with what it now shows. The dictionaries are the golden copies the phone's
/// `CameraPreviewRemoteAppTests` assert.
struct CameraPreviewRemoteTests {

    @Test func asksThePhoneToShowTheView() {
        #expect(CameraPreviewRemote.request(show: true) as NSDictionary
                == ["type": "showCameraPreview", "show": true] as NSDictionary)
    }

    @Test func asksThePhoneToHideIt() {
        #expect(CameraPreviewRemote.request(show: false) as NSDictionary
                == ["type": "showCameraPreview", "show": false] as NSDictionary)
    }

    @Test func readsWhatThePhoneSaysItShows() {
        #expect(CameraPreviewRemote.shown(from: ["type": "cameraPreview", "shown": true]) == true)
        #expect(CameraPreviewRemote.shown(from: ["type": "cameraPreview", "shown": false]) == false)
    }

    @Test func ignoresAMalformedAnswer() {
        #expect(CameraPreviewRemote.shown(from: ["type": "cameraPreview"]) == nil)
        #expect(CameraPreviewRemote.shown(from: ["type": "nudgeSilence", "shown": true]) == nil)
    }

    /// The button says what a tap will do.
    @Test func theButtonOffersTheOpposite() {
        #expect(CameraPreviewRemote.buttonTitle(phoneShows: false) == "Show camera")
        #expect(CameraPreviewRemote.buttonTitle(phoneShows: true) == "Hide camera")
    }

    /// The phone's answer reaches the button.
    @MainActor @Test func thePhonesAnswer_reachesTheButton() async {
        let delegate = WatchSessionDelegate(activatesSession: false)
        delegate.session(WCSession.default, didReceiveMessage: ["type": "cameraPreview", "shown": true])
        // The delegate hands the answer to the main queue; wait for it to come round.
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
        #expect(delegate.phoneShowsCamera)
    }
}
