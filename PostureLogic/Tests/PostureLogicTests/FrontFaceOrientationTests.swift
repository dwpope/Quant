import XCTest
import CoreVideo
import ImageIO
@testable import PostureLogic

/// Front Face hands ARKit's sensor-landscape frames to Vision; the body points are read with the
/// frame turned upright, then put in the units of a 720 × 1280 frame whatever the aspect.
final class FrontFaceOrientationTests: XCTestCase {

    func test_referenceUnits_leaveA720x1280FrameUnchanged() {
        let p = CGPoint(x: 0.3, y: 0.7)
        XCTAssertEqual(FrameOrientation.referenceUnits(p, width: 720, height: 1280), p)
    }

    func test_referenceUnits_keepHeightOverWidthRatios_on4by3() {
        // 0.2 across and 0.1 down on a 1440×1920 upright frame: 288 px across, 192 px down.
        let a = FrameOrientation.referenceUnits(CGPoint(x: 0.4, y: 0.5), width: 1440, height: 1920)
        let b = FrameOrientation.referenceUnits(CGPoint(x: 0.6, y: 0.6), width: 1440, height: 1920)
        XCTAssertEqual(Double((b.y - a.y) * 1280 / ((b.x - a.x) * 720)), 192.0 / 288.0, accuracy: 1e-6)
    }

    func test_orientedSize_swapsForQuarterTurns() {
        XCTAssertTrue(PoseService.orientedSize(width: 1920, height: 1440, orientation: .right) == (1440, 1920))
        XCTAssertTrue(PoseService.orientedSize(width: 1280, height: 720, orientation: .up) == (1280, 720))
        XCTAssertTrue(PoseService.orientedSize(width: 1920, height: 1440, orientation: .leftMirrored) == (1440, 1920))
    }

    func test_mirrorCheck() {
        XCTAssertEqual(FrontFaceMirrorCheck.classify(visionNoseX: 0.42, projectedFaceX: 0.45), .matches)
        XCTAssertEqual(FrontFaceMirrorCheck.classify(visionNoseX: 0.30, projectedFaceX: 0.68), .mirrored)
        XCTAssertEqual(FrontFaceMirrorCheck.classify(visionNoseX: 0.50, projectedFaceX: 0.50), .unclear)
    }

    func test_frontFrames_keepTheirKeypoints() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 720, 1280, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let frame = InputFrame(timestamp: 0, pixelBuffer: try XCTUnwrap(buffer), depthMap: nil, cameraIntrinsics: nil)
        XCTAssertEqual(frame.visionOrientation, .up)
        let found = [Keypoint(joint: .nose, position: CGPoint(x: 0.3, y: 0.2), confidence: 0.9),
                     Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.6, y: 0.5), confidence: 0.8)]
        let out = PoseService.keypoints(found, in: frame)
        XCTAssertEqual(out.map(\.joint), found.map(\.joint))
        XCTAssertEqual(out.map(\.position), found.map(\.position))
        XCTAssertEqual(out.map(\.confidence), found.map(\.confidence))
    }

    func test_turnedFrame_putsKeypointsInReferenceUnits() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 1920, 1440, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let frame = InputFrame(timestamp: 0, pixelBuffer: try XCTUnwrap(buffer), depthMap: nil, cameraIntrinsics: nil, visionOrientation: .right)
        let found = [Keypoint(joint: .nose, position: CGPoint(x: 0.3, y: 0.6), confidence: 0.9)]
        let out = PoseService.keypoints(found, in: frame)
        let expected = FrameOrientation.referenceUnits(CGPoint(x: 0.3, y: 0.6), width: 1440, height: 1920)
        XCTAssertEqual(out[0].position, expected)
        XCTAssertEqual(out[0].joint, .nose)
    }
}
