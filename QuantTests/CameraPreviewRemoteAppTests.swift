import XCTest
import Combine
@testable import Quant

/// Showing the camera's view on the phone from the Watch (2026-10-20), so Dave can check he's in
/// frame without reaching for a phone propped out of reach.
///
/// The phone holds whether the view is shown: the Watch asks, and the phone answers with what it
/// now shows. The dictionaries are the golden copies the Watch's `CameraPreviewRemoteTests` assert.
@MainActor
final class CameraPreviewRemoteAppTests: XCTestCase {

    /// What the phone told the Watch, in order.
    private final class Told {
        var shown: [Bool] = []
    }

    private func model(recording told: Told) -> AppModel {
        let model = AppModel()
        model.sendsCameraPreview = { _, shown in told.shown.append(shown) }
        return model
    }

    // MARK: - The messages

    func test_readsTheWatchsRequest() {
        XCTAssertEqual(WatchConnectivityService.cameraPreviewRequest(
            from: ["type": "showCameraPreview", "show": true]), true)
        XCTAssertEqual(WatchConnectivityService.cameraPreviewRequest(
            from: ["type": "showCameraPreview", "show": false]), false)
    }

    func test_ignoresAMalformedRequest() {
        XCTAssertNil(WatchConnectivityService.cameraPreviewRequest(from: ["type": "showCameraPreview"]))
        XCTAssertNil(WatchConnectivityService.cameraPreviewRequest(from: ["type": "calibrate", "show": true]))
    }

    func test_tellsTheWatchWhetherItsShown() {
        XCTAssertEqual(WatchConnectivityService.cameraPreviewMessage(shown: true) as NSDictionary,
                       ["type": "cameraPreview", "shown": true] as NSDictionary)
        XCTAssertEqual(WatchConnectivityService.cameraPreviewMessage(shown: false) as NSDictionary,
                       ["type": "cameraPreview", "shown": false] as NSDictionary)
    }

    // MARK: - On the phone

    func test_theWatchsRequest_showsThenHidesTheView() {
        let model = AppModel()
        model.watchService.handleReceivedMessage(["type": "showCameraPreview", "show": true])
        XCTAssertTrue(model.showCameraPreview)
        model.watchService.handleReceivedMessage(["type": "showCameraPreview", "show": false])
        XCTAssertFalse(model.showCameraPreview)
    }

    /// The eye on the phone and the button on the Watch stay in step.
    func test_tappingTheEyeOnThePhone_tellsTheWatch() {
        let told = Told()
        let model = model(recording: told)
        model.showCameraPreview.toggle()
        model.showCameraPreview.toggle()
        XCTAssertEqual(told.shown, [true, false])
    }

    /// The Watch's button can be out of date (the phone app relaunched with the view hidden).
    /// Asking for what's already showing still gets an answer, which puts the button right.
    func test_askingForWhatsAlreadyShowing_isStillAnswered() {
        let told = Told()
        let model = model(recording: told)
        model.watchService.handleReceivedMessage(["type": "showCameraPreview", "show": false])
        XCTAssertEqual(told.shown, [false])
    }

    func test_whenTheWatchAppOpens_itsToldWhatsShowing() {
        let told = Told()
        let model = model(recording: told)
        model.showCameraPreview = true
        told.shown = []
        model.watchService.reachabilityChanged.send(true)
        XCTAssertEqual(told.shown, [true])
    }
}
