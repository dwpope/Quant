import XCTest
import ARKit
import AVFoundation
import PostureLogic
@testable import Quant

/// The camera services' recovery rules (2026-10-11 code review).
@MainActor
final class CameraLifecycleTests: XCTestCase {

    // MARK: - Interruptions

    /// A phone call or Siri stops the frames. That isn't a resource problem: the rear camera's
    /// timeout "recovered" through it and, on its third try, switched depth off for good.
    func test_noFramesDuringAnInterruption_isNotATimeout() {
        XCTAssertFalse(ARSessionService.isFrameTimeout(secondsSinceFrame: 10, interrupted: true))
        XCTAssertTrue(ARSessionService.isFrameTimeout(secondsSinceFrame: 10, interrupted: false))
        XCTAssertFalse(ARSessionService.isFrameTimeout(secondsSinceFrame: 1, interrupted: false))
    }

    // MARK: - A refused camera

    /// Face tracking retried a refused camera every half second, for as long as the app ran.
    func test_aRefusedCamera_isNotRetried() {
        let refused = NSError(domain: ARError.errorDomain, code: ARError.Code.cameraUnauthorized.rawValue)
        let sensor = NSError(domain: ARError.errorDomain, code: ARError.Code.sensorFailed.rawValue)
        XCTAssertFalse(ARFaceTrackingService.isRetryable(refused))
        XCTAssertTrue(ARFaceTrackingService.isRetryable(sensor))
    }

    func test_deniedAndRestricted_areRefused() {
        XCTAssertTrue(CameraAccess.isRefused(.denied))
        XCTAssertTrue(CameraAccess.isRefused(.restricted))
        XCTAssertFalse(CameraAccess.isRefused(.authorized))
        XCTAssertFalse(CameraAccess.isRefused(.notDetermined), "ARKit asks then")
    }

    // MARK: - Heat

    /// "Paused to cool down" now stops the camera, the main source of the heat.
    func test_critical_stopsTheCamera_andCoolingStartsItAgain() {
        XCTAssertEqual(HeatPause.action(for: .critical, cameraStoppedForHeat: false), .stopCamera)
        XCTAssertEqual(HeatPause.action(for: .critical, cameraStoppedForHeat: true), .none)
        XCTAssertEqual(HeatPause.action(for: .serious, cameraStoppedForHeat: true), .startCamera)
        XCTAssertEqual(HeatPause.action(for: .serious, cameraStoppedForHeat: false), .none)
    }
}
