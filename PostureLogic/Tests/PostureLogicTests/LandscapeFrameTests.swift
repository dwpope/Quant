import XCTest
import Combine
import CoreVideo
@testable import PostureLogic

/// The phone on its side (2026-11-11, Dave: "The camera in portrait mode is too narrow on my
/// desk. What happened to the landscape mode?"). The front camera turns its frames upright for
/// however the phone is held, so on its side they come wide: 1280 × 720 instead of 720 × 1280.
///
/// Every posture line was set on the upright phone's frames, in coordinates that run 0…1 across
/// each side of the frame. Across a wide frame those units stretch: the same head drop reads
/// 3.2 times larger against the same shoulders. So a wide frame's keypoints are put back into the
/// upright frame's units first, and a baseline is only good for the way it was taken.
final class LandscapeFrameTests: XCTestCase {

    // MARK: - Which way the frame is turned

    func test_aFrameWiderThanTall_isLandscape() {
        XCTAssertEqual(FrameOrientation(width: 1280, height: 720), .landscape)
        XCTAssertEqual(FrameOrientation(width: 720, height: 1280), .portrait)
        XCTAssertEqual(FrameOrientation(width: 480, height: 480), .portrait, "square: as before")
    }

    // MARK: - Keypoints in the upright frame's units

    func test_anUprightFrame_keepsItsPoints() {
        let point = CGPoint(x: 0.31, y: 0.72)
        XCTAssertEqual(FrameOrientation.portraitUnits(point, width: 720, height: 1280), point)
    }

    /// The same pixels from the frame's centre, on the phone held either way, give the same point.
    func test_aWideFramesPoint_readsAsInTheUprightFrame() {
        let offsets: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (-150, -300), (200, 120), (-500, 330)]
        for (dx, dy) in offsets {
            let upright = CGPoint(x: 0.5 + dx / 720, y: 0.5 + dy / 1280)
            let wide = CGPoint(x: 0.5 + dx / 1280, y: 0.5 + dy / 720)

            let mapped = FrameOrientation.portraitUnits(wide, width: 1280, height: 720)

            XCTAssertEqual(mapped.x, upright.x, accuracy: 1e-9, "offset (\(dx), \(dy))")
            XCTAssertEqual(mapped.y, upright.y, accuracy: 1e-9, "offset (\(dx), \(dy))")
        }
    }

    /// Head drop is the ears' height over the shoulders in shoulder widths. Unmapped, a wide frame
    /// reads it (1280/720)² ≈ 3.2 times larger, so a head drop line of 0.020 would fire at a third
    /// of the drop.
    func test_neckHeightInShoulderWidths_isTheSameEitherWay() {
        // Ears 260 px above the shoulders, which are 300 px apart, in both frames.
        func neckHeight(ears: CGPoint, left: CGPoint, right: CGPoint) -> CGFloat {
            let width = hypot(left.x - right.x, left.y - right.y)
            return (ears.y - (left.y + right.y) / 2) / width
        }
        let uprightNeck = neckHeight(
            ears: CGPoint(x: 360.0 / 720, y: 440.0 / 1280),
            left: CGPoint(x: 510.0 / 720, y: 700.0 / 1280),
            right: CGPoint(x: 210.0 / 720, y: 700.0 / 1280))

        let map = { (p: CGPoint) in FrameOrientation.portraitUnits(p, width: 1280, height: 720) }
        let wideNeck = neckHeight(
            ears: map(CGPoint(x: 640.0 / 1280, y: 100.0 / 720)),
            left: map(CGPoint(x: 790.0 / 1280, y: 360.0 / 720)),
            right: map(CGPoint(x: 490.0 / 1280, y: 360.0 / 720)))

        XCTAssertEqual(wideNeck, uprightNeck, accuracy: 1e-9)
        XCTAssertEqual(uprightNeck, -260.0 / 300 * 720 / 1280, accuracy: 1e-9,
                       "the upright frame's own units, as every line was set in")
    }

    // MARK: - Pose detection puts a wide frame's keypoints in the upright frame's units

    private let found = [
        Keypoint(joint: .nose, position: CGPoint(x: 0.5, y: 0.14), confidence: 0.9),
        Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.62, y: 0.5), confidence: 0.8),
    ]

    func test_aLandscapeFramesKeypoints_areInTheUprightFramesUnits() throws {
        let frame = try cameraFrame(.landscape, at: 1)
        let keypoints = PoseService.keypoints(found, in: frame)

        XCTAssertEqual(keypoints.map(\.joint), [.nose, .leftShoulder])
        XCTAssertEqual(keypoints.map(\.confidence), [0.9, 0.8])
        for (mapped, raw) in zip(keypoints, found) {
            let expected = FrameOrientation.portraitUnits(raw.position, width: 128, height: 72)
            XCTAssertEqual(mapped.position.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(mapped.position.y, expected.y, accuracy: 1e-9)
        }
        XCTAssertNotEqual(keypoints[0].position, found[0].position)
    }

    func test_anUprightFramesKeypoints_areAsFound() throws {
        let keypoints = PoseService.keypoints(found, in: try cameraFrame(.portrait, at: 1))
        XCTAssertEqual(keypoints.map(\.position), found.map(\.position))
    }

    /// ARKit's frames come wide whichever way the phone is held, and say portrait: as before.
    func test_aWideFrameThatSaysPortrait_isAsFound() throws {
        let arkitFrame = InputFrame(timestamp: 1, pixelBuffer: try pixelBuffer(width: 128, height: 72),
                                    depthMap: nil, cameraIntrinsics: nil)
        let keypoints = PoseService.keypoints(found, in: arkitFrame)
        XCTAssertEqual(keypoints.map(\.position), found.map(\.position))
    }

    // MARK: - A baseline is for one way round

    private func baseline(_ orientation: FrameOrientation? = nil) -> Baseline {
        let made = Baseline(
            timestamp: Date(timeIntervalSince1970: 1_790_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), headPosition: SIMD3<Float>(0, -0.9, 0),
            torsoAngle: 45, shoulderTwist: -1, shoulderWidth: 0.42, depthAvailable: false,
            neckHeight: -0.34, headYaw: -2)
        return orientation.map { made.oriented($0) } ?? made
    }

    func test_aBaseline_isUprightUnlessSaid() {
        XCTAssertEqual(baseline().orientation, .portrait)
    }

    func test_orientingABaseline_keepsEverythingElse() {
        let turned = baseline(.landscape)
        XCTAssertEqual(turned.orientation, .landscape)
        XCTAssertEqual(turned.timestamp, baseline().timestamp)
        XCTAssertEqual(turned.shoulderMidpoint, baseline().shoulderMidpoint)
        XCTAssertEqual(turned.headPosition, baseline().headPosition)
        XCTAssertEqual(turned.torsoAngle, 45)
        XCTAssertEqual(turned.shoulderTwist, -1)
        XCTAssertEqual(turned.shoulderWidth, 0.42)
        XCTAssertFalse(turned.depthAvailable)
        XCTAssertEqual(turned.neckHeight, -0.34)
        XCTAssertEqual(turned.headYaw, -2)
    }

    func test_aLandscapeBaseline_isSavedAsOne() throws {
        let data = try JSONEncoder().encode(baseline(.landscape))
        XCTAssertEqual(try JSONDecoder().decode(Baseline.self, from: data).orientation, .landscape)
    }

    /// One saved by a later version, turned some way this one doesn't know, still loads.
    func test_aBaselineTurnedAnUnknownWay_readsAsUpright() throws {
        let data = try JSONEncoder().encode(baseline(.landscape))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["orientation"] = "upsideDown"
        let later = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Baseline.self, from: later)
        XCTAssertEqual(decoded.orientation, .portrait)
        XCTAssertEqual(decoded.shoulderWidth, 0.42, accuracy: 0.0001)
    }

    /// Every baseline saved before this was taken upright.
    func test_aBaselineSavedBeforeLandscape_readsAsUpright() throws {
        let data = try JSONEncoder().encode(baseline(.landscape))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "orientation")
        let old = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Baseline.self, from: old)
        XCTAssertEqual(decoded.orientation, .portrait)
        XCTAssertEqual(decoded.shoulderWidth, 0.42, accuracy: 0.0001)
    }

    // MARK: - The pipeline says which way the camera is

    private func pixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func cameraFrame(_ orientation: FrameOrientation, at t: TimeInterval) throws -> InputFrame {
        let (w, h) = orientation == .landscape ? (128, 72) : (72, 128)
        return InputFrame(timestamp: t, pixelBuffer: try pixelBuffer(width: w, height: h), depthMap: nil,
                          cameraIntrinsics: nil, orientation: orientation)
    }

    /// Emits a camera frame every half second for `seconds`, from `start`.
    private func emit(_ orientation: FrameOrientation, from start: TimeInterval, for seconds: TimeInterval,
                      via provider: MockPoseProvider) throws {
        for t in stride(from: start, to: start + seconds, by: 0.5) {
            provider.emit(frame: try cameraFrame(orientation, at: t))
        }
    }

    /// Every orientation the pipeline published, once the frames sent so far are all processed.
    private func published(by pipeline: Pipeline, after send: () throws -> Void) async throws -> [FrameOrientation] {
        var seen: [FrameOrientation] = []
        let watch = pipeline.$frameOrientation.compactMap { $0 }.sink { seen.append($0) }
        try send()
        let drained = XCTestExpectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 5)
        watch.cancel()
        return seen
    }

    func test_theCamerasFrames_sayWhichWayItIs() async throws {
        let provider = MockPoseProvider()
        try await provider.start()
        let pipeline = Pipeline(provider: provider)
        XCTAssertNil(pipeline.frameOrientation, "nothing seen yet")

        let seen = try await published(by: pipeline) {
            try emit(.portrait, from: 1_790_000_000, for: 3, via: provider)
            try emit(.landscape, from: 1_790_000_003, for: 3, via: provider)
            try emit(.portrait, from: 1_790_000_006, for: 3, via: provider)
        }

        XCTAssertEqual(seen, [.portrait, .landscape, .portrait], "once per turn")
    }

    /// Review, 2026-11-11: lifting the phone off its stand for a moment and putting it back
    /// dropped the baseline, and a new one was taken in whatever posture came next.
    func test_aMomentTheOtherWayRound_isntATurn() async throws {
        let provider = MockPoseProvider()
        try await provider.start()
        let pipeline = Pipeline(provider: provider)

        let seen = try await published(by: pipeline) {
            try emit(.landscape, from: 1_790_000_000, for: 3, via: provider)
            try emit(.portrait, from: 1_790_000_003, for: 1.5, via: provider)
            try emit(.landscape, from: 1_790_000_004.5, for: 3, via: provider)
        }

        XCTAssertEqual(seen, [.landscape])
    }

    /// Nor the first frames: the turn takes a moment to settle as the camera starts.
    func test_theFirstFrames_countOnlyOnceSettled() async throws {
        let provider = MockPoseProvider()
        try await provider.start()
        let pipeline = Pipeline(provider: provider)

        let seen = try await published(by: pipeline) {
            try emit(.portrait, from: 1_790_000_000, for: 1, via: provider)
            try emit(.landscape, from: 1_790_000_001, for: 1.5, via: provider)
        }

        XCTAssertEqual(seen, [])
    }

    func test_aFrameWithNoPicture_saysNothingAboutTheCamera() async throws {
        let provider = MockPoseProvider()
        try await provider.start()
        let pipeline = Pipeline(provider: provider)

        let seen = try await published(by: pipeline) {
            for t in stride(from: 1_790_000_000.0, to: 1_790_000_004, by: 0.5) {
                provider.emit(frame: InputFrame(timestamp: t, pixelBuffer: nil, depthMap: nil,
                                                cameraIntrinsics: nil, orientation: .landscape))
            }
        }

        XCTAssertEqual(seen, [])
    }

    /// A replay's samples carry no picture and say nothing about the phone.
    func test_aReplayFrame_saysNothingAboutTheCamera() async throws {
        let provider = MockPoseProvider()
        try await provider.start()
        let pipeline = Pipeline(provider: provider)
        let sample = PoseSample(
            timestamp: 1_790_000_000, depthMode: .twoDOnly, headPosition: SIMD3<Float>(0, -0.9, 0),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), leftShoulder: SIMD3<Float>(-0.5, 0, 0),
            rightShoulder: SIMD3<Float>(0.5, 0, 0), torsoAngle: 45, headForwardOffset: 0,
            shoulderTwist: 0, shoulderWidthRaw: 0.42, trackingQuality: .good)
        let processed = XCTestExpectation(description: "replay frame processed")
        let watch = pipeline.$latestSample.compactMap { $0 }.sink { _ in processed.fulfill() }

        provider.emit(frame: InputFrame(timestamp: 1_790_000_000, pixelBuffer: nil, depthMap: nil,
                                        cameraIntrinsics: nil, precomputedSample: sample,
                                        orientation: .landscape))
        await fulfillment(of: [processed], timeout: 5)
        watch.cancel()

        XCTAssertNil(pipeline.frameOrientation)
    }
}
