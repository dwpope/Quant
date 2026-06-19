import XCTest
@testable import PostureLogic

/// Unit tests for the pure Vision-face-angle → degrees converter. The *scale*
/// (rad→deg) and the per-axis nil passthrough are the parts that can be proven
/// off-device; the physical sign is confirmed on device via the binding gains, so
/// these assert that Vision's native sign is preserved (not inverted) and scaled.
final class FaceAngleConversionTests: XCTestCase {

    private let degPerRad = Float(180.0 / Double.pi)

    func test_scalesRadiansToDegrees() {
        let out = FaceAngleConversion.degrees(yawRadians: 0.5, pitchRadians: -0.25, rollRadians: 1.0)
        XCTAssertEqual(out.yaw!, 0.5 * degPerRad, accuracy: 1e-4)   // ≈ 28.6479°
        XCTAssertEqual(out.pitch!, -0.25 * degPerRad, accuracy: 1e-4) // ≈ -14.3239°
        XCTAssertEqual(out.roll!, 1.0 * degPerRad, accuracy: 1e-4)   // ≈ 57.2958°
    }

    func test_preservesSign() {
        let pos = FaceAngleConversion.degrees(yawRadians: 0.3, pitchRadians: 0.3, rollRadians: 0.3)
        XCTAssertGreaterThan(pos.yaw!, 0)
        XCTAssertGreaterThan(pos.pitch!, 0)
        XCTAssertGreaterThan(pos.roll!, 0)

        let neg = FaceAngleConversion.degrees(yawRadians: -0.3, pitchRadians: -0.3, rollRadians: -0.3)
        XCTAssertLessThan(neg.yaw!, 0)
        XCTAssertLessThan(neg.pitch!, 0)
        XCTAssertLessThan(neg.roll!, 0)
    }

    func test_zeroMapsToZero() {
        let out = FaceAngleConversion.degrees(yawRadians: 0, pitchRadians: 0, rollRadians: 0)
        XCTAssertEqual(out.yaw!, 0, accuracy: 1e-6)
        XCTAssertEqual(out.pitch!, 0, accuracy: 1e-6)
        XCTAssertEqual(out.roll!, 0, accuracy: 1e-6)
    }

    /// A nil input axis must yield a nil output axis (so `computeHeadAngles` falls
    /// back to the legacy 2D formula for that axis only — per-axis mixing).
    func test_nilAxisStaysNil_perAxis() {
        let out = FaceAngleConversion.degrees(yawRadians: 0.4, pitchRadians: nil, rollRadians: nil)
        XCTAssertNotNil(out.yaw)
        XCTAssertNil(out.pitch)
        XCTAssertNil(out.roll)
    }

    func test_allNilStaysAllNil() {
        let out = FaceAngleConversion.degrees(yawRadians: nil, pitchRadians: nil, rollRadians: nil)
        XCTAssertNil(out.yaw)
        XCTAssertNil(out.pitch)
        XCTAssertNil(out.roll)
    }
}
