import XCTest
import PostureLogic
@testable import Quant

/// The metrics line carries the head's pitch and size (2026-11-26), logged only, to see whether
/// they catch what head drop can't: looking down (the nose drops towards the ear line while the
/// ears stay put) and craning towards the screen (the head grows against the shoulders).
@MainActor
final class PostureLogHeadShapeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(_ joint: Joint, _ x: CGFloat, _ y: CGFloat, _ confidence: Float = 0.9) -> Keypoint {
        Keypoint(joint: joint, position: CGPoint(x: x, y: y), confidence: confidence)
    }

    private func pose(earConfidence: Float = 0.9) -> [Keypoint] {
        [point(.leftEar, 0.4, 0.3, earConfidence), point(.rightEar, 0.6, 0.3, earConfidence),
         point(.leftShoulder, 0.3, 0.6), point(.rightShoulder, 0.7, 0.6)]
    }

    private func metrics() -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0, lateralLean: 0,
                   twist: 0, movementLevel: 0, headMovementPattern: .still)
    }

    func test_headSize_isEarSpanOverShoulderSpan() throws {
        let shape = PostureLogRecorder.HeadShape(keypoints: pose(), pitch: 12)
        XCTAssertEqual(try XCTUnwrap(shape.size), 0.5, accuracy: 1e-6)
        XCTAssertEqual(shape.pitch, 12)
    }

    func test_unsureEars_giveNoSize() {
        XCTAssertNil(PostureLogRecorder.HeadShape(keypoints: pose(earConfidence: 0.2), pitch: 0).size)
    }

    func test_noShoulders_giveNoSize() {
        XCTAssertNil(PostureLogRecorder.HeadShape(keypoints: Array(pose().prefix(2)), pitch: 0).size)
    }

    private func window(_ shapes: [PostureLogRecorder.HeadShape?]) -> PostureLogEvent? {
        var recorder = PostureLogRecorder()
        var out: [PostureLogEvent] = []
        for (i, shape) in shapes.enumerated() {
            out += recorder.metricsEvents(state: .good, metrics: metrics(), head: shape,
                                          baselineTakenAt: t0.addingTimeInterval(-600),
                                          headDropLine: 0.01875, forwardCreepLine: 0.06,
                                          now: t0.addingTimeInterval(Double(i)))
        }
        out += recorder.metricsEvents(state: .good, metrics: metrics(), head: nil,
                                      baselineTakenAt: t0.addingTimeInterval(-600),
                                      headDropLine: 0.01875, forwardCreepLine: 0.06,
                                      now: t0.addingTimeInterval(10))
        return out.first { $0.kind == "metrics" }
    }

    func test_metricsLine_carriesHeadPitchAndSize() throws {
        let line = try XCTUnwrap(window([
            .init(pitch: 2, size: 0.50), .init(pitch: 6, size: 0.54), .init(pitch: 4, size: 0.52),
        ]))
        XCTAssertEqual(line.headPitchLow, 2)
        XCTAssertEqual(line.headPitchMedian, 4)
        XCTAssertEqual(line.headPitchHigh, 6)
        XCTAssertEqual(try XCTUnwrap(line.headSizeLow), 0.50, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.headSizeMedian), 0.52, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.headSizeHigh), 0.54, accuracy: 1e-6)
    }

    func test_framesWithoutSize_leaveSizeOut_butKeepPitch() throws {
        let line = try XCTUnwrap(window([.init(pitch: 3, size: nil), .init(pitch: 5, size: nil)]))
        XCTAssertNil(line.headSizeMedian)
        XCTAssertEqual(line.headPitchMedian, 5, "upper middle of an even count, as the other medians")
    }

    func test_noHead_noHeadFields() throws {
        let line = try XCTUnwrap(window([nil, nil]))
        XCTAssertNil(line.headPitchMedian)
        XCTAssertNil(line.headSizeMedian)
        let json = String(data: try JSONEncoder().encode(line), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("headPitch"))
    }
}
