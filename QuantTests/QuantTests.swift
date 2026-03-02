//
//  QuantTests.swift
//  QuantTests
//
//  Created by Learning on 27/12/2025.
//

import XCTest
import PostureLogic
import simd
@testable import Quant

@MainActor
final class AppModelTests: XCTestCase {
    private let baselineKey = "com.quant.savedBaseline"
    private let cameraModeKey = "com.quant.cameraMode"

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        UserDefaults.standard.removeObject(forKey: cameraModeKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        UserDefaults.standard.removeObject(forKey: cameraModeKey)
    }

    func test_init_requiresCalibrationWhenNoSavedBaseline() {
        let model = AppModel()

        XCTAssertTrue(model.needsCalibration)
        XCTAssertNil(model.baseline)
    }

    func test_init_loadsFreshBaselineFromUserDefaults() throws {
        let expected = makeBaseline(timestamp: Date())
        let data = try JSONEncoder().encode(expected)
        UserDefaults.standard.set(data, forKey: baselineKey)

        let model = AppModel()
        guard let loaded = model.baseline else {
            XCTFail("Expected baseline to be loaded from UserDefaults")
            return
        }

        XCTAssertFalse(model.needsCalibration)
        XCTAssertEqual(loaded.depthAvailable, expected.depthAvailable)
        XCTAssertEqual(loaded.shoulderWidth, expected.shoulderWidth, accuracy: 0.0001)
        XCTAssertEqual(loaded.torsoAngle, expected.torsoAngle, accuracy: 0.0001)
    }

    func test_init_discardsStaleBaselineFromUserDefaults() throws {
        let stale = makeBaseline(timestamp: Date().addingTimeInterval(-7_200))
        let data = try JSONEncoder().encode(stale)
        UserDefaults.standard.set(data, forKey: baselineKey)

        let model = AppModel()

        XCTAssertTrue(model.needsCalibration)
        XCTAssertNil(model.baseline)
        XCTAssertNil(UserDefaults.standard.data(forKey: baselineKey))
    }

    func test_recalibrate_clearsLoadedBaselineAndResetsCalibrationState() throws {
        let expected = makeBaseline(timestamp: Date())
        let data = try JSONEncoder().encode(expected)
        UserDefaults.standard.set(data, forKey: baselineKey)

        let model = AppModel()
        XCTAssertFalse(model.needsCalibration)
        XCTAssertNotNil(model.baseline)

        model.recalibrate()

        XCTAssertTrue(model.needsCalibration)
        XCTAssertNil(model.baseline)
        XCTAssertEqual(model.calibrationStatus, .waiting)
        XCTAssertEqual(model.calibrationProgress, 0, accuracy: 0.0001)
    }

    // MARK: - Camera Mode Tests

    func test_defaultCameraMode_isRearDepth() {
        let model = AppModel()
        XCTAssertEqual(model.cameraMode, .rearDepth)
    }

    func test_cameraModePersistedInUserDefaults() {
        UserDefaults.standard.set("front2D", forKey: cameraModeKey)
        let model1 = AppModel()
        XCTAssertEqual(model1.cameraMode, .front2D)

        UserDefaults.standard.set("rearDepth", forKey: cameraModeKey)
        let model2 = AppModel()
        XCTAssertEqual(model2.cameraMode, .rearDepth)
    }

    func test_switchingModeUpdatesActiveProvider() async {
        let model = AppModel()
        XCTAssertEqual(model.cameraMode, .rearDepth)

        await model.switchCameraMode(to: .front2D)

        XCTAssertEqual(model.cameraMode, .front2D)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: cameraModeKey),
            "front2D"
        )
        XCTAssertTrue(model.needsCalibration)
    }

    // MARK: - Helpers

    private func makeBaseline(timestamp: Date) -> Baseline {
        Baseline(
            timestamp: timestamp,
            shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            headPosition: SIMD3<Float>(0, 1, 0),
            torsoAngle: 4.0,
            shoulderWidth: 0.42,
            depthAvailable: true
        )
    }

}
