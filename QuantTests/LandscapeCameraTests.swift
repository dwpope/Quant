import XCTest
import CoreVideo
import Combine
import PostureLogic
@testable import Quant

/// The phone on its side (2026-11-11, Dave: "The camera in portrait mode is too narrow on my
/// desk. What happened to the landscape mode?"). A baseline is good only for the way round the
/// camera's frames were when it was taken: turning the phone moves the camera and swaps the
/// frame's sides, so turning it asks for a new calibration.
@MainActor
final class LandscapeCameraTests: XCTestCase {
    private let baselineKey = "com.quant.savedBaseline"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: baselineKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: baselineKey)
    }

    private func baseline(_ orientation: FrameOrientation = .portrait) -> Baseline {
        Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0),
                 headPosition: SIMD3<Float>(0, -0.9, 0), torsoAngle: 45, shoulderWidth: 0.42,
                 depthAvailable: false, neckHeight: -0.34, orientation: orientation)
    }

    /// A model that launched with `saved` as its baseline.
    private func model(saved: Baseline) throws -> AppModel {
        UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: baselineKey)
        let model = AppModel()
        XCTAssertFalse(model.needsCalibration, "launched calibrated")
        return model
    }

    func test_turningThePhoneOnItsSide_asksForANewCalibration() throws {
        let model = try model(saved: baseline(.portrait))

        model.cameraTurned(to: .landscape)

        XCTAssertTrue(model.needsCalibration)
        XCTAssertNil(model.baseline)
        XCTAssertNil(UserDefaults.standard.data(forKey: baselineKey), "not loaded again on relaunch")
        XCTAssertEqual(model.calibrationStatus, .waiting)
    }

    func test_framesTheWayTheBaselineWasTaken_keepIt() throws {
        let model = try model(saved: baseline(.portrait))

        model.cameraTurned(to: .portrait)

        XCTAssertFalse(model.needsCalibration)
        XCTAssertNotNil(model.baseline)
    }

    func test_aLandscapeBaseline_holdsInLandscape() throws {
        let model = try model(saved: baseline(.landscape))

        model.cameraTurned(to: .landscape)

        XCTAssertFalse(model.needsCalibration)
        XCTAssertEqual(model.baseline?.orientation, .landscape)
    }

    /// Calibrated on its side yesterday, upright today.
    func test_aLandscapeBaseline_isDroppedWhenTheFramesComeUpright() throws {
        let model = try model(saved: baseline(.landscape))

        model.cameraTurned(to: .portrait)

        XCTAssertTrue(model.needsCalibration)
        XCTAssertNil(model.baseline)
    }

    func test_aNewBaseline_isForTheWayTheCameraIsTurned() throws {
        let model = AppModel()
        model.cameraTurned(to: .landscape)

        model.adoptBaseline(baseline(.portrait))

        XCTAssertFalse(model.needsCalibration)
        XCTAssertEqual(model.baseline?.orientation, .landscape)
        XCTAssertEqual(AppModel().baseline?.orientation, .landscape, "saved so")
    }

    /// Before any frame has said, the camera is taken to be upright, as it always was.
    func test_aNewBaseline_beforeAnyFrame_isUpright() {
        let model = AppModel()
        model.adoptBaseline(baseline(.landscape))
        XCTAssertEqual(model.baseline?.orientation, .portrait)
    }

    /// A turn while counting down or sampling starts the calibration again, so no baseline mixes
    /// frames from both ways round.
    func test_aTurnWhileCalibrating_startsItAgain() {
        let model = AppModel()
        model.calibrationStatus = .countdown(2)

        model.cameraTurned(to: .landscape)

        XCTAssertEqual(model.calibrationStatus, .waiting)
        XCTAssertTrue(model.needsCalibration)
    }

    /// The camera's frames reach the model through the pipeline: turned for long enough, the
    /// baseline goes.
    func test_framesComingTheOtherWayRound_askForANewCalibration() async throws {
        let model = try model(saved: baseline(.portrait))
        let camera = MockPoseProvider()
        try await camera.start()
        model.switchableProvider.attach(source: camera)
        let recalibrating = XCTestExpectation(description: "asked for a new calibration")
        let watch = model.$needsCalibration.dropFirst().sink { if $0 { recalibrating.fulfill() } }

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 128, 72, kCVPixelFormatType_32BGRA, nil, &buffer)
        for t in stride(from: 1_790_000_000.0, to: 1_790_000_003, by: 0.5) {
            camera.emit(frame: InputFrame(timestamp: t, pixelBuffer: try XCTUnwrap(buffer), depthMap: nil,
                                          cameraIntrinsics: nil, orientation: .landscape))
        }

        await fulfillment(of: [recalibrating], timeout: 5)
        watch.cancel()
        XCTAssertNil(model.baseline)
    }

    func test_aTurn_isALogLine() {
        let now = Date(timeIntervalSince1970: 1_794_400_000)
        let event = PostureLogRecorder.cameraEvent(.landscape, now: now)
        XCTAssertEqual(event.kind, "camera")
        XCTAssertEqual(event.value, "landscape")
        XCTAssertEqual(event.t, 1_794_400_000)
        XCTAssertEqual(PostureLogRecorder.cameraEvent(.portrait, now: now).value, "portrait")
    }
}
