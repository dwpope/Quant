import XCTest
@testable import PostureLogic

/// Telling a slumped recline from a healthy lean back (2026-10-06).
///
/// Session 11: two slumped reclines (hips slid forward while leaning back) sank the shoulders
/// +0.142, twice as far as any of the seven lean-backs so far (+0.020 to +0.083). They also moved
/// the shoulders far enough back to be excused as reclined, so the thresholds called them good.
/// While reclined, a sink of +0.11 or more now still counts. And one lean-back sat at forward creep
/// -0.150, a hair outside the -0.15 recline line, so the line moves to -0.125; sinks so far reach
/// only -0.101.
final class SlumpedReclineTests: XCTestCase {

    func test_theLines() {
        let t = PostureThresholds()
        XCTAssertEqual(t.reclineMaxForwardCreep, -0.125)
        XCTAssertEqual(t.reclinedSinkThreshold, 0.11)
    }

    /// What the posture engine says for a capture's forward creep, sink and head drop, with the
    /// head facing ahead, the way the pipeline works out "reclined".
    private func verdict(creep: Float, sink: Float, headDrop: Float = 0) -> PostureState {
        let t = PostureThresholds()
        let reclined = PostureEngine.isReclined(forwardCreep: creep, headYawFromCalibration: 0,
                                                thresholds: t, headTurn: HeadTurnThresholds())
        let engine = PostureEngine(thresholds: t)
        engine.update(metrics: RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                          lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still),
                      taskMode: .unknown, trackingQuality: .good)
        let m = RawMetrics(timestamp: 1, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                           lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still,
                           shoulderSink: sink)
        return engine.update(metrics: m, taskMode: .unknown, trackingQuality: .good, reclined: reclined)
    }

    private func drifts(_ s: PostureState) -> Bool {
        if case .drifting = s { return true }
        return false
    }

    func test_bothSlumpedReclines_areASlouch() {
        XCTAssertTrue(drifts(verdict(creep: -0.205, sink: 0.142, headDrop: -0.010)))
        XCTAssertTrue(drifts(verdict(creep: -0.251, sink: 0.142, headDrop: -0.014)))
    }

    /// Every lean-back so far, sessions 9 to 11: [forward creep, sink, head drop].
    func test_everyLeanBack_isFinePosture() {
        let leanBacks: [(Float, Float, Float)] = [
            (-0.232, 0.083, -0.039), (-0.233, 0.078, -0.100), (-0.129, 0.021, -0.059), (-0.097, 0.027, -0.045),
            (-0.150, 0.055, -0.016), (-0.170, 0.070, -0.024), (-0.184, 0.072, -0.026),
        ]
        for (fc, sink, hd) in leanBacks {
            XCTAssertEqual(verdict(creep: fc, sink: sink, headDrop: hd), .good, "\(fc) \(sink) \(hd)")
        }
    }

    /// Every sink so far, sessions 8 to 11: [forward creep, sink]. None leans back far enough to be
    /// excused, so all still count.
    func test_everySink_isStillASlouch() {
        let sinks: [(Float, Float)] = [
            (-0.052, 0.103), (-0.046, 0.096), (-0.033, 0.100), (-0.080, 0.088), (-0.083, 0.086),
            (-0.078, 0.087), (-0.053, 0.065), (-0.057, 0.082), (0.030, 0.111), (0.037, 0.112),
            (-0.097, 0.102), (-0.059, 0.084), (-0.101, 0.092),
        ]
        for (fc, sink) in sinks {
            XCTAssertTrue(drifts(verdict(creep: fc, sink: sink)), "\(fc) \(sink)")
        }
    }
}
