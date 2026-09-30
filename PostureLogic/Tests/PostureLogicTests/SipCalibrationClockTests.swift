import XCTest
@testable import PostureLogic

/// Sip calibration has to time a capture on the clock its frames use.
///
/// On a device, frame timestamps count seconds since boot (670,636 in the 2026-09-29 session).
/// `AppModel` started and ended the capture with `Date().timeIntervalSince1970`, about 1.79
/// billion. So the 10-second auto-end, measured from frames, never came. And a capture that
/// ended with the wrist still near the face recorded a sip lasting about 1.79 billion seconds.
/// With one sip required, that became the detector's minimum sip duration, so after calibrating
/// no real sip could ever be detected.
///
/// `SipCalibrationCaptureTests` couldn't see this: they start the capture and feed frames on one
/// synthetic clock. These tests do what the app does, on a since-boot clock. Written against the
/// old code first, they failed with a 3-second sip recorded as 1,790,077,433 seconds, a derived
/// minimum of 1,432,061,946 seconds, and no auto-end. `beginCapture` and `endCapture` no longer
/// take a time, so the calendar clock can't be passed in.
final class SipCalibrationClockTests: XCTestCase {

    /// When the first device session's frames started, in seconds since boot.
    private let bootClockStart: TimeInterval = 670_636

    /// Wrist beside the nose: inside the capture's proximity zone for the whole window.
    private func wristAtMouth(timestamp: TimeInterval) -> PoseObservation {
        let nose = Keypoint(joint: .nose, position: CGPoint(x: 0.5, y: 0.3), confidence: 0.99)
        return PoseObservation(
            timestamp: timestamp,
            keypoints: [
                nose,
                Keypoint(joint: .leftShoulder, position: CGPoint(x: 0.35, y: 0.5), confidence: 0.99),
                Keypoint(joint: .rightShoulder, position: CGPoint(x: 0.65, y: 0.5), confidence: 0.99),
                Keypoint(joint: .leftWrist, position: CGPoint(x: 0.53, y: 0.33), confidence: 0.99),
            ],
            confidence: 0.99)
    }

    /// The app ends a capture with its own 10-second timer. If the wrist is still at the mouth
    /// when it does, the sip's duration runs from when the wrist arrived to the end.
    func test_aCaptureEndedWithTheWristAtTheMouth_recordsARealDuration() throws {
        let capture = SipCalibrationCapture()

        capture.beginCapture()                                        // what AppModel does
        for i in 0..<30 {                                              // 3 s at 10 fps
            capture.process(wristAtMouth(timestamp: bootClockStart + Double(i) * 0.1))
        }
        capture.endCapture()                                          // what AppModel does

        let sip = try XCTUnwrap(capture.recordedSamples.last)
        XCTAssertEqual(sip.duration, 2.9, accuracy: 0.05,
                       "first close frame to last frame, on the frame clock")
    }

    /// The capture also ends itself after 10 seconds of frames, whatever the app's timer does.
    func test_aCapture_endsItself_afterTenSecondsOfFrames() {
        let capture = SipCalibrationCapture()

        capture.beginCapture()                                        // what AppModel does
        for i in 0...105 {                                             // 10.5 s at 10 fps
            capture.process(wristAtMouth(timestamp: bootClockStart + Double(i) * 0.1))
        }

        XCTAssertEqual(capture.recordedSipCount, 1)
    }

    /// The consequence that mattered: with one sip required, its duration becomes the
    /// detector's minimum. It has to be a sip-sized number.
    func test_theDerivedMinimumSipDuration_isSipSized() throws {
        let capture = SipCalibrationCapture()

        capture.beginCapture()                                        // what AppModel does
        for i in 0..<30 {
            capture.process(wristAtMouth(timestamp: bootClockStart + Double(i) * 0.1))
        }
        capture.endCapture()                                          // what AppModel does

        let thresholds = try XCTUnwrap(capture.derivedThresholds)
        XCTAssertLessThan(thresholds.minDuration, 10)
    }
}
