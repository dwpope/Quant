import XCTest
@testable import PostureLogic

/// Sinking down in the chair (2026-10-05).
///
/// In session 7 Dave slouched by sinking: head and shoulders went down together. Nothing measured
/// saw it. Forward creep needs the shoulders closer to the camera, and head drop is the head
/// measured against the shoulders, so all five slouches read like sitting upright. Shoulder sink
/// is the shoulders' own drop in the frame since calibration, in calibrated shoulder widths.
/// It's recorded and shown, not judged, until a session shows where the line is.
final class ShoulderSinkTests: XCTestCase {

    /// Calibrated with the shoulders at y 0.67 of the frame and 0.42 wide. Image y runs DOWN
    /// (PoseService flips Vision's), so a larger y is lower.
    private let baseline = Baseline(timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0.5, 0.67, 0),
                                    headPosition: SIMD3<Float>(0, -0.38, 0), torsoAngle: 45,
                                    shoulderWidth: 0.42, depthAvailable: false)

    private func sample(shoulderY: Float, mode: DepthMode = .twoDOnly) -> PoseSample {
        PoseSample(timestamp: 1, depthMode: mode, headPosition: SIMD3<Float>(0, -0.38, 0),
                   shoulderMidpoint: SIMD3<Float>(0.5, shoulderY, 0),
                   leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                   torsoAngle: 45, headForwardOffset: 0, shoulderTwist: 0,
                   shoulderWidthRaw: 0.42, trackingQuality: .good)
    }

    func test_shouldersLowerInTheFrame_readPositive() {
        var engine = MetricsEngine()
        let m = engine.compute(from: sample(shoulderY: 0.712), baseline: baseline)
        XCTAssertEqual(m.shoulderSink, 0.1, accuracy: 0.001, "0.042 lower is 0.1 shoulder widths")
    }

    func test_shouldersHigher_readNegative() {
        var engine = MetricsEngine()
        XCTAssertLessThan(engine.compute(from: sample(shoulderY: 0.65), baseline: baseline).shoulderSink, 0)
    }

    func test_sittingAsCalibrated_readsZero() {
        var engine = MetricsEngine()
        XCTAssertEqual(engine.compute(from: sample(shoulderY: 0.67), baseline: baseline).shoulderSink, 0,
                       accuracy: 1e-6)
    }

    /// The depth path's shoulder midpoint is in metres, not the frame: no honest sink there.
    func test_withDepth_itIsNotMeasured() {
        var engine = MetricsEngine()
        XCTAssertEqual(engine.compute(from: sample(shoulderY: 0.9, mode: .depthFusion), baseline: baseline)
            .shoulderSink, 0)
    }

    func test_withoutABaseline_itIsZero() {
        var engine = MetricsEngine()
        XCTAssertEqual(engine.compute(from: sample(shoulderY: 0.9), baseline: nil).shoulderSink, 0)
    }

    /// Smoothed like the others, so one jittery frame doesn't move it.
    func test_theSmoother_carriesIt() {
        var smoother = MetricsSmoother()
        let first = smoother.smooth(metrics(sink: 0.1, at: 0), sample: sample(shoulderY: 0.712))
        XCTAssertEqual(first.shoulderSink, 0.1, accuracy: 1e-6, "the first sample passes through")
        let second = smoother.smooth(metrics(sink: 0.3, at: 0.1), sample: sample(shoulderY: 0.796))
        XCTAssertGreaterThan(second.shoulderSink, 0.1)
        XCTAssertLessThan(second.shoulderSink, 0.3)
    }

    private func metrics(sink: Float, at t: TimeInterval) -> RawMetrics {
        RawMetrics(timestamp: t, forwardCreep: 0, headDrop: 0, shoulderRounding: 0, lateralLean: 0,
                   twist: 0, movementLevel: 0, headMovementPattern: .still, shoulderSink: sink)
    }
}
