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

    // MARK: - A camera's own restarts (2026-10-19 review)

    /// The cameras restart their own sessions half a second or a second after a frame timeout or
    /// a failure. One queued just before `stop()` ran after it, so a heat pause's stop could be
    /// undone: the camera, the main source of the heat, came back on while the phone was hot.
    func test_aRestartQueuedBeforeAStop_doesNotRun() {
        var runs = CameraRuns()
        runs.started()
        let restart = runs.current
        runs.stopped()
        XCTAssertFalse(runs.isStill(restart))
    }

    func test_aRestartWhileRunning_runs() {
        var runs = CameraRuns()
        runs.started()
        XCTAssertTrue(runs.isStill(runs.current))
    }

    /// Nor does one from before a stop and a start again: the new run has its own.
    func test_aRestartFromAnEarlierRun_doesNotRun() {
        var runs = CameraRuns()
        runs.started()
        let restart = runs.current
        runs.stopped()
        runs.started()
        XCTAssertFalse(runs.isStill(restart))
        XCTAssertTrue(runs.isStill(runs.current))
    }

    /// Never started: nothing to restart.
    func test_beforeAStart_nothingRuns() {
        let runs = CameraRuns()
        XCTAssertFalse(runs.isStill(runs.current))
    }

    // MARK: - Heat, with the app (2026-10-16 audit)

    private let cameraModeKey = "com.quant.cameraMode"
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: cameraModeKey)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: cameraModeKey)
        super.tearDown()
    }

    /// The cameras the app started, in order.
    private final class Starts {
        var cameras: [any PoseProvider] = []
    }

    /// A model whose camera starts are recorded, once it has taken in the phone's own thermal
    /// level: that arrives a run of the main loop after the model starts, and a cool one would
    /// start the camera in the middle of a test.
    private func model(recording starts: Starts) async throws -> AppModel {
        let model = AppModel()
        model.startsCamera = { starts.cameras.append($0) }
        try await Task.sleep(for: .milliseconds(100))
        return model
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// Switching camera while the phone is too hot leaves the new one off until it cools. The
    /// switch started it straight away, heat or not.
    func test_switchingCameraWhileTooHot_waitsForItToCool() async throws {
        let starts = Starts()
        let model = try await model(recording: starts)
        XCTAssertNotEqual(model.cameraMode, .front2D, "a switch to the camera already chosen does nothing")
        model.applyHeatPause(.critical)

        await model.switchCameraMode(to: .front2D)
        XCTAssertTrue(starts.cameras.isEmpty, "too hot: the new camera waits")

        model.applyHeatPause(.nominal)
        try await waitFor { !starts.cameras.isEmpty }
        XCTAssertEqual(starts.cameras.count, 1)
        XCTAssertTrue(starts.cameras.first is FrontCameraSessionService, "the camera chosen while it was hot")
    }

    /// Nothing else starts the camera while the phone is too hot either: the launch, or "Try
    /// again" on a camera problem, rear or front.
    func test_startingOrRetryingWhileTooHot_waitsForItToCool() async throws {
        let starts = Starts()
        let rear = try await model(recording: starts)
        XCTAssertEqual(rear.cameraMode, .rearDepth)
        rear.applyHeatPause(.critical)
        await rear.startMonitoring()
        await rear.retryRearCamera()

        UserDefaults.standard.set(CameraMode.front2D.rawValue, forKey: cameraModeKey)
        let front = try await model(recording: starts)
        XCTAssertEqual(front.cameraMode, .front2D)
        front.applyHeatPause(.critical)
        await front.retryFrontCamera()

        XCTAssertTrue(starts.cameras.isEmpty)
    }

    private func replaying(_ model: AppModel) throws -> URL {
        model.startRecording()
        let url = try XCTUnwrap(model.stopRecording())
        try model.loadSession(url)
        model.startReplay()
        return url
    }

    /// The phone cooling during a replay starts the camera again. It was ignored, and the level
    /// isn't sent again unless it changes, so the camera stayed off after the replay.
    func test_coolingDuringAReplay_startsTheCameraAgain() async throws {
        let starts = Starts()
        let model = try await model(recording: starts)
        model.applyHeatPause(.critical)
        let url = try replaying(model)
        defer { try? FileManager.default.removeItem(at: url) }

        model.applyHeatPause(.nominal)
        model.stopReplay()
        try await waitFor { !starts.cameras.isEmpty }
        XCTAssertFalse(model.cameraStoppedForHeat)
        XCTAssertEqual(starts.cameras.count, 1)
    }

    /// The phone getting too hot during a replay stops the camera, which runs through a replay.
    func test_tooHotDuringAReplay_stopsTheCamera() async throws {
        let model = try await model(recording: Starts())
        let url = try replaying(model)
        defer { try? FileManager.default.removeItem(at: url) }

        model.applyHeatPause(.critical)
        model.stopReplay()
        XCTAssertTrue(model.cameraStoppedForHeat)
    }
}
