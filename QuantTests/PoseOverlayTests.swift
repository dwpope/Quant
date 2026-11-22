import XCTest
import SwiftUI
import UIKit
import CoreGraphics
import PostureLogic
@testable import Quant

/// The points the camera tracks, drawn over the picture (2026-11-22, Dave: "draw the points that
/// are being tracked on top of the camera feed … so it's easier to explain what the measurements
/// track"). The picture is the front camera's, shown as in a mirror and filling the screen, so
/// each point has to land where that part of him is on screen.
@MainActor
final class PoseOverlayTests: XCTestCase {
    private let phone = CGSize(width: 390, height: 844)
    private let phoneOnItsSide = CGSize(width: 844, height: 390)

    private func point(_ joint: Joint, _ x: CGFloat, _ y: CGFloat, _ confidence: Float = 0.9) -> Keypoint {
        Keypoint(joint: joint, position: CGPoint(x: x, y: y), confidence: confidence)
    }

    // MARK: - Where a point lands

    func test_theMiddleOfTheFrame_isTheMiddleOfTheScreen() {
        let p = PoseOverlay.screenPoint(CGPoint(x: 0.5, y: 0.5), orientation: .portrait, in: phone)
        XCTAssertEqual(p.x, 195, accuracy: 0.001)
        XCTAssertEqual(p.y, 422, accuracy: 0.001)
    }

    func test_thePictureIsAMirror_soHisLeftIsOnTheRight() {
        // 720 × 1280 filling 390 × 844: the height fits (scale 0.659), and 5.7 points of each side
        // are cut off. x 0.25 in the frame is x 0.75 in the mirror.
        let p = PoseOverlay.screenPoint(CGPoint(x: 0.25, y: 0), orientation: .portrait, in: phone)
        let scale = 844.0 / 1280.0
        XCTAssertEqual(p.x, 0.75 * 720 * scale - (720 * scale - 390) / 2, accuracy: 0.001)
        XCTAssertEqual(p.y, 0, accuracy: 0.001)
    }

    func test_onItsSide_aPointIsPutBackOnTheWideFrame() {
        // The pipeline measures a wide frame's points in the upright frame's units; drawing undoes it.
        let found = CGPoint(x: 0.3, y: 0.6)
        let measured = FrameOrientation.portraitUnits(found, width: 1280, height: 720)
        let p = PoseOverlay.screenPoint(measured, orientation: .landscape, in: phoneOnItsSide)
        let scale = max(844.0 / 1280.0, 390.0 / 720.0)
        let offsetY = (390 - 720 * scale) / 2
        XCTAssertEqual(p.x, (1 - 0.3) * 1280 * scale - (1280 * scale - 844) / 2, accuracy: 0.001)
        XCTAssertEqual(p.y, 0.6 * 720 * scale + offsetY, accuracy: 0.001)
    }

    // MARK: - What's drawn

    private let sitting: [Keypoint] = [
        Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.30, y: 0.60), confidence: 0.9),
        Keypoint(joint: .rightShoulder, position: CGPoint(x: 0.70, y: 0.60), confidence: 0.9),
        Keypoint(joint: .leftEar, position: CGPoint(x: 0.42, y: 0.46), confidence: 0.9),
        Keypoint(joint: .rightEar, position: CGPoint(x: 0.58, y: 0.46), confidence: 0.9),
        Keypoint(joint: .nose, position: CGPoint(x: 0.50, y: 0.45), confidence: 0.9),
        Keypoint(joint: .leftWrist, position: CGPoint(x: 0.20, y: 0.95), confidence: 0.5),
    ]

    func test_everyTrackedPoint_isDrawn() {
        let overlay = PoseOverlay(keypoints: sitting, orientation: .portrait, baseline: nil, in: phone)
        XCTAssertEqual(Set(overlay.dots.map(\.joint)), [.leftShoulder, .rightShoulder, .leftEar, .rightEar, .nose, .leftWrist])
        XCTAssertEqual(overlay.dots.first { $0.joint == .leftWrist }?.part, .other)
        XCTAssertEqual(overlay.dots.first { $0.joint == .nose }?.part, .head)
        XCTAssertEqual(overlay.dots.first { $0.joint == .leftShoulder }?.part, .shoulders)
    }

    func test_aPointTooUnsureToMeasure_isMarkedSo() {
        // The measurements use a point only at 0.3 or more.
        let unsure = sitting + [point(.leftEye, 0.46, 0.44, 0.2)]
        let overlay = PoseOverlay(keypoints: unsure, orientation: .portrait, baseline: nil, in: phone)
        XCTAssertFalse(overlay.dots.first { $0.joint == .leftEye }!.measured)
        XCTAssertTrue(overlay.dots.first { $0.joint == .nose }!.measured)
    }

    func test_theLinesTheMeasurementsUse() {
        let overlay = PoseOverlay(keypoints: sitting, orientation: .portrait, baseline: nil, in: phone)
        XCTAssertEqual(Set(overlay.lines.map(\.kind)), [.shoulders, .ears, .headHeight])
        let height = overlay.lines.first { $0.kind == .headHeight }!
        XCTAssertEqual(height.from, PoseOverlay.screenPoint(CGPoint(x: 0.5, y: 0.46), orientation: .portrait, in: phone))
        XCTAssertEqual(height.to, PoseOverlay.screenPoint(CGPoint(x: 0.5, y: 0.60), orientation: .portrait, in: phone))
    }

    func test_withoutShoulders_thereAreNoMeasuringLines() {
        let headOnly = sitting.filter { $0.joint != .leftShoulder && $0.joint != .rightShoulder }
        let overlay = PoseOverlay(keypoints: headOnly, orientation: .portrait, baseline: nil, in: phone)
        XCTAssertEqual(overlay.lines.map(\.kind), [.ears])
    }

    // MARK: - Against the calibration

    private func baseline(_ orientation: FrameOrientation = .portrait) -> Baseline {
        // Shoulders 0.4 wide centred at (0.48, 0.58); ears 0.35 shoulder widths above them.
        Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.48, 0.58, 0),
                 headPosition: .zero, torsoAngle: 0, shoulderWidth: 0.4,
                 depthAvailable: false, neckHeight: -0.35, orientation: orientation)
    }

    func test_theCalibratedPlaces_areDrawnToCompareWith() {
        let overlay = PoseOverlay(keypoints: sitting, orientation: .portrait, baseline: baseline(), in: phone)
        let map = { PoseOverlay.screenPoint($0, orientation: .portrait, in: self.phone) }

        // Side lean and sink: where the middle of the shoulders was.
        // (The calibration is kept in Float, so to a thousandth of a point.)
        assertNear(overlay.calibratedCentre, map(CGPoint(x: 0.48, y: 0.58)))

        // Leaning in: the calibrated width, on today's shoulders.
        let width = overlay.lines.first { $0.kind == .calibratedShoulders }!
        assertNear(width.from, map(CGPoint(x: 0.30, y: 0.60)))
        assertNear(width.to, map(CGPoint(x: 0.70, y: 0.60)))

        // Head drop: where the ears were over today's shoulders, 0.35 widths up (0.40 wide now).
        let head = overlay.lines.first { $0.kind == .calibratedHeadHeight }!
        let earY = 0.60 - 0.35 * 0.40
        XCTAssertEqual(head.from.y, map(CGPoint(x: 0.5, y: earY)).y, accuracy: 0.001)
        XCTAssertEqual(head.to.y, head.from.y, accuracy: 0.001)
        // Half a shoulder width across.
        XCTAssertEqual(abs(head.to.x - head.from.x),
                       abs(map(CGPoint(x: 0.6, y: 0)).x - map(CGPoint(x: 0.4, y: 0)).x), accuracy: 0.001)
    }

    private func assertNear(_ a: CGPoint?, _ b: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("no point", file: file, line: line) }
        XCTAssertEqual(a.x, b.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001, file: file, line: line)
    }

    func test_aCalibrationTheOtherWayRound_isntDrawn() {
        let overlay = PoseOverlay(keypoints: sitting, orientation: .portrait, baseline: baseline(.landscape), in: phone)
        XCTAssertNil(overlay.calibratedCentre)
        XCTAssertFalse(overlay.lines.contains { $0.kind == .calibratedShoulders || $0.kind == .calibratedHeadHeight })
    }

    func test_aDepthCalibration_isntDrawn() {
        let depth = Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0, 0, 0.6), headPosition: .zero,
                             torsoAngle: 0, shoulderWidth: 0.4, depthAvailable: true, neckHeight: -0.35)
        let overlay = PoseOverlay(keypoints: sitting, orientation: .portrait, baseline: depth, in: phone)
        XCTAssertNil(overlay.calibratedCentre)
    }

    // MARK: - Coloured by the reading (2026-11-22)

    private func status(_ kind: PoseOverlay.LineKind, _ reading: PoseReading) -> PoseOverlay.Status? {
        PoseOverlay(keypoints: sitting, orientation: .portrait, baseline: baseline(), reading: reading, in: phone)
            .lines.first { $0.kind == kind }?.status
    }

    func test_sittingWell_theReadingsAreGreen_andTheCalibratedOnesUncoloured() {
        let reading = PoseReading(state: .good, pastLines: [])
        for kind in [PoseOverlay.LineKind.shoulders, .headHeight, .centreShift, .ears] {
            XCTAssertEqual(status(kind, reading), .good, "\(kind)")
        }
        XCTAssertNil(status(.calibratedShoulders, reading))
        XCTAssertNil(status(.calibratedHeadHeight, reading))
    }

    func test_pastItsLine_aReadingIsAmber_andOnlyThatOne() {
        let reading = PoseReading(state: .drifting(since: 0), pastLines: [.headDrop])
        XCTAssertEqual(status(.headHeight, reading), .slouching)
        XCTAssertEqual(status(.shoulders, reading), .good)
        XCTAssertEqual(status(.centreShift, reading), .good)
    }

    func test_sideLeanAndSink_bothColourTheCentreLine() {
        XCTAssertEqual(status(.centreShift, PoseReading(state: .drifting(since: 0), pastLines: [.sideLean])), .slouching)
        XCTAssertEqual(status(.centreShift, PoseReading(state: .drifting(since: 0), pastLines: [.sink])), .slouching)
    }

    func test_onceTheSlouchHasGoneOn_itsLineIsRed() {
        let reading = PoseReading(state: .bad(since: 0), pastLines: [.forwardCreep])
        XCTAssertEqual(status(.shoulders, reading), .stillSlouching)
        XCTAssertEqual(status(.headHeight, reading), .good, "sat up on this one")
    }

    func test_aHeadTurned_colourTheEars() {
        XCTAssertEqual(status(.ears, PoseReading(state: .good, pastLines: [], headTurned: true)), .slouching)
    }

    func test_withNothingJudged_noReadingIsColoured() {
        XCTAssertNil(status(.shoulders, PoseReading(state: .absent, pastLines: [.forwardCreep])))
        XCTAssertNil(status(.shoulders, PoseReading(state: .calibrating, pastLines: [])))
    }

    func test_theCountdown_saysWhatChangesNextAndWhen() {
        XCTAssertNil(PoseReading(state: .good, pastLines: []).countdown)
        XCTAssertEqual(PoseReading(state: .drifting(since: 0), pastLines: [.headDrop],
                                   stateChangeIn: 41.2, nudgeIn: 29.01).countdown,
                       "red in 42 s · nudge in 30 s")
        XCTAssertEqual(PoseReading(state: .bad(since: 0), pastLines: [], stateChangeIn: 2.5).countdown,
                       "green in 3 s")
        XCTAssertEqual(PoseReading(state: .bad(since: 0), pastLines: [.sink], nudgeIn: 0).countdown,
                       "nudge in 0 s")
        XCTAssertEqual(PoseReading(state: .good, pastLines: [], headTurned: true, nudgeIn: 12).countdown,
                       "nudge in 12 s")
    }

    func test_theCountdownsColour_isThePostures() {
        XCTAssertEqual(PoseReading(state: .drifting(since: 0), pastLines: []).status, .slouching)
        XCTAssertEqual(PoseReading(state: .bad(since: 0), pastLines: []).status, .stillSlouching)
        XCTAssertEqual(PoseReading(state: .good, pastLines: []).status, .good)
    }

    /// The points never wear a posture colour, so green, amber and red only ever mean the reading.
    func test_thePointsColours_areNoneOfThePostures() {
        func hue(_ colour: Color) -> CGFloat {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(colour).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return h * 360
        }
        let postures = [PoseOverlay.Status.good, .slouching, .stillSlouching].map { hue(PoseOverlayView.colour($0)) }
        for point in [PoseOverlayView.shoulderPoint, PoseOverlayView.headPoint] {
            for posture in postures {
                let apart = min(abs(hue(point) - posture), 360 - abs(hue(point) - posture))
                XCTAssertGreaterThan(apart, 60, "a point's hue \(hue(point)) is near a posture's \(posture)")
            }
        }
    }
}
