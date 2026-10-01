import XCTest
import ARKit
import Combine
@testable import Quant

/// What the person holding the phone sees when the rear camera can't run.
///
/// Before 2026-10-01: `ARSessionService` published a failed state that nothing subscribed to,
/// and its frame-timeout timer logged "No frames received yet" every 2 seconds, forever, while
/// the screen showed nothing. The front camera had a recovery screen; the rear one didn't.
@MainActor
final class RearCameraStatusTests: XCTestCase {

    private func arError(_ code: ARError.Code) -> NSError {
        NSError(domain: ARError.errorDomain, code: code.rawValue)
    }

    // MARK: - What an ARKit error means

    func test_cameraUnauthorized_needsSettings() {
        XCTAssertEqual(RearCameraStatus.after(error: arError(.cameraUnauthorized)), .unauthorized)
    }

    /// The service already restarts the session for these. Only if frames still don't come is
    /// it the person's problem, which the frame timeout below covers.
    func test_recoverableErrors_showNothingYet() {
        XCTAssertNil(RearCameraStatus.after(error: arError(.sensorFailed)))
        XCTAssertNil(RearCameraStatus.after(error: arError(.worldTrackingFailed)))
    }

    func test_anyOtherError_isUnavailable() {
        guard case .unavailable = RearCameraStatus.after(error: arError(.unsupportedConfiguration)) else {
            return XCTFail("an unrecoverable ARKit error should be shown")
        }
        guard case .unavailable = RearCameraStatus.after(error: NSError(domain: "x", code: 1)) else {
            return XCTFail("a non-ARKit error should be shown")
        }
    }

    // MARK: - No frames

    func test_noFrameEver_isUnavailable_afterTheGracePeriod() {
        let grace = RearCameraStatus.noFramesGracePeriod
        XCTAssertNil(RearCameraStatus.afterFrameCheck(secondsSinceStart: grace - 0.1, receivedAnyFrame: false))
        guard case .unavailable = RearCameraStatus.afterFrameCheck(
            secondsSinceStart: grace, receivedAnyFrame: false) else {
            return XCTFail("no frame after the grace period should be shown")
        }
    }

    /// A stall after frames have flowed is the service's resource recovery's job, not a screen.
    func test_aStallAfterFramesFlowed_showsNothing() {
        XCTAssertNil(RearCameraStatus.afterFrameCheck(secondsSinceStart: 60, receivedAnyFrame: true))
    }

    // MARK: - The service

    func test_theServicePublishesAnUnauthorizedFailure() {
        let service = ARSessionService()
        XCTAssertEqual(service.status, .ok)

        service.session(service.session, didFailWithError: arError(.cameraUnauthorized))

        XCTAssertEqual(service.status, .unauthorized)
    }

    func test_aRecoverableFailure_leavesTheStatusAlone() {
        let service = ARSessionService()

        service.session(service.session, didFailWithError: arError(.sensorFailed))

        XCTAssertEqual(service.status, .ok)
    }

    // MARK: - The app

    /// The screen reads `AppModel.rearCameraStatus`, which follows the service.
    func test_theAppModelFollowsTheService() async {
        let model = AppModel()
        let seen = expectation(description: "unauthorized reaches the model")
        let sub = model.$rearCameraStatus.dropFirst().sink { status in
            if status == .unauthorized { seen.fulfill() }
        }

        model.arService.session(model.arService.session, didFailWithError: arError(.cameraUnauthorized))

        await fulfillment(of: [seen], timeout: 2)
        sub.cancel()
    }
}
