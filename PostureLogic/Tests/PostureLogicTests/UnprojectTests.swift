import XCTest
import simd
@testable import PostureLogic

final class UnprojectTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a typical camera intrinsics matrix.
    ///
    /// simd_float3x3 is column-major:
    ///   column 0 = (fx,  0,  0)
    ///   column 1 = ( 0, fy,  0)
    ///   column 2 = (cx, cy,  1)
    private func makeIntrinsics(fx: Float, fy: Float, cx: Float, cy: Float) -> simd_float3x3 {
        simd_float3x3(
            SIMD3<Float>(fx, 0, 0),
            SIMD3<Float>(0, fy, 0),
            SIMD3<Float>(cx, cy, 1)
        )
    }

    // MARK: - Known Values

    func test_unproject_withKnownValues_producesCorrectPosition() {
        // Camera: fx=500, fy=500, cx=320, cy=240 (typical 640x480 camera)
        let intrinsics = makeIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        let point = SIMD2<Float>(420, 340)  // 100px right and 100px below principal point
        let depth: Float = 2.0  // 2 meters

        let result = unproject(point: point, depth: depth, intrinsics: intrinsics)

        // x = (420 - 320) * 2.0 / 500 = 100 * 2.0 / 500 = 0.4
        XCTAssertEqual(result.x, 0.4, accuracy: 1e-5)
        // y = (340 - 240) * 2.0 / 500 = 100 * 2.0 / 500 = 0.4
        XCTAssertEqual(result.y, 0.4, accuracy: 1e-5)
        // z = depth = 2.0
        XCTAssertEqual(result.z, 2.0, accuracy: 1e-5)
    }

    func test_unproject_atPrincipalPoint_returnsZeroXY() {
        let intrinsics = makeIntrinsics(fx: 600, fy: 600, cx: 320, cy: 240)
        let point = SIMD2<Float>(320, 240)  // exactly at principal point
        let depth: Float = 1.5

        let result = unproject(point: point, depth: depth, intrinsics: intrinsics)

        XCTAssertEqual(result.x, 0.0, accuracy: 1e-5)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-5)
        XCTAssertEqual(result.z, 1.5, accuracy: 1e-5)
    }

    func test_unproject_negativeOffset_producesNegativeCoords() {
        let intrinsics = makeIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        let point = SIMD2<Float>(220, 140)  // 100px left and 100px above principal point
        let depth: Float = 3.0

        let result = unproject(point: point, depth: depth, intrinsics: intrinsics)

        // x = (220 - 320) * 3.0 / 500 = -100 * 3.0 / 500 = -0.6
        XCTAssertEqual(result.x, -0.6, accuracy: 1e-5)
        // y = (140 - 240) * 3.0 / 500 = -100 * 3.0 / 500 = -0.6
        XCTAssertEqual(result.y, -0.6, accuracy: 1e-5)
        XCTAssertEqual(result.z, 3.0, accuracy: 1e-5)
    }

    func test_unproject_asymmetricFocalLength() {
        // Different fx and fy (non-square pixels)
        let intrinsics = makeIntrinsics(fx: 500, fy: 400, cx: 320, cy: 240)
        let point = SIMD2<Float>(420, 340)
        let depth: Float = 2.0

        let result = unproject(point: point, depth: depth, intrinsics: intrinsics)

        // x = (420 - 320) * 2.0 / 500 = 0.4
        XCTAssertEqual(result.x, 0.4, accuracy: 1e-5)
        // y = (340 - 240) * 2.0 / 400 = 0.5
        XCTAssertEqual(result.y, 0.5, accuracy: 1e-5)
        XCTAssertEqual(result.z, 2.0, accuracy: 1e-5)
    }

    func test_unproject_zeroDepth_returnsOrigin() {
        let intrinsics = makeIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        let point = SIMD2<Float>(420, 340)
        let depth: Float = 0.0

        let result = unproject(point: point, depth: depth, intrinsics: intrinsics)

        XCTAssertEqual(result.x, 0.0, accuracy: 1e-5)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-5)
        XCTAssertEqual(result.z, 0.0, accuracy: 1e-5)
    }

    func test_unproject_depthScalesLinearly() {
        let intrinsics = makeIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
        let point = SIMD2<Float>(370, 290)  // 50px offset from principal point

        let result1 = unproject(point: point, depth: 1.0, intrinsics: intrinsics)
        let result2 = unproject(point: point, depth: 2.0, intrinsics: intrinsics)

        // At 2x depth, x and y should also be 2x
        XCTAssertEqual(result2.x, result1.x * 2.0, accuracy: 1e-5)
        XCTAssertEqual(result2.y, result1.y * 2.0, accuracy: 1e-5)
    }
}
