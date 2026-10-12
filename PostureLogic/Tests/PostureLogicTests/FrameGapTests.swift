import XCTest
@testable import PostureLogic

/// A long pause between frames is a break for every timer, not time spent (2026-10-11).
///
/// The nudge engine already treated more than 60 s without frames as a break. The posture
/// engine added the whole gap to the drift time, so the first frame back after a pause read
/// "bad" at once; and the head-turn tracker kept its episode, so a head still turned after a
/// pause was nudged on the first frame back.
final class FrameGapTests: XCTestCase {

    private func slouched(at t: TimeInterval) -> RawMetrics {
        RawMetrics(timestamp: t, forwardCreep: 0.15, headDrop: 0, shoulderRounding: 0,
                   lateralLean: 0.02, twist: 5, movementLevel: 0, headMovementPattern: .still)
    }

    func test_thePostureEngine_doesntCountAPauseAsDrifting() {
        let engine = PostureEngine(thresholds: PostureThresholds())
        var state = PostureState.absent
        for t in stride(from: 0.0, through: 10, by: 1) {
            state = engine.update(metrics: slouched(at: t), taskMode: .unknown, trackingQuality: .good)
        }
        guard case .drifting = state else { return XCTFail("drifting after 10 s, got \(state)") }
        // Five minutes with no frames (app in the background), then still slouched.
        let after = engine.update(metrics: slouched(at: 310), taskMode: .unknown, trackingQuality: .good)
        guard case .drifting = after else { return XCTFail("the pause isn't drift time, got \(after)") }
    }

    func test_theHeadTurnTracker_startsAgainAfterAPause() {
        let tracker = HeadTurnTracker(thresholds: HeadTurnThresholds())
        for t in stride(from: 0.0, through: 60, by: 1) {
            tracker.update(headYaw: 60, forwardCreep: 0.05, trackingQuality: .good, timestamp: t)
        }
        let since = tracker.update(headYaw: 60, forwardCreep: 0.05, trackingQuality: .good, timestamp: 420)
        XCTAssertEqual(since, 420, "turned since the frame back, not since before the pause")
    }
}
