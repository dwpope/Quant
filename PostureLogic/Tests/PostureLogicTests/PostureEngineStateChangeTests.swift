import XCTest
@testable import PostureLogic

/// When the posture will next change colour on its own (2026-11-22): drifting turns bad after
/// `driftingToBadThreshold` of slouching, and bad turns good after `recoveryGracePeriod` of
/// sitting well. For the countdown drawn over the camera's picture.
final class PostureEngineStateChangeTests: XCTestCase {
    private func metrics(_ t: TimeInterval, lean: Float) -> RawMetrics {
        RawMetrics(timestamp: t, forwardCreep: 0.02, headDrop: 0, shoulderRounding: 0,
                   lateralLean: lean, twist: 3, movementLevel: 0, headMovementPattern: .still)
    }
    private let well: Float = 0.01, leaning: Float = 0.12

    @discardableResult
    private func update(_ engine: PostureEngine, _ t: TimeInterval, lean: Float) -> PostureState {
        engine.update(metrics: metrics(t, lean: lean), taskMode: .unknown, trackingQuality: .good)
    }

    func test_sittingWell_nothingIsDue() {
        let engine = PostureEngine()
        update(engine, 1, lean: well)
        XCTAssertNil(engine.stateChangeDueAt)
    }

    func test_drifting_turnsBadAfterTheDriftTime() {
        let engine = PostureEngine()
        update(engine, 1, lean: well)
        update(engine, 2, lean: leaning)
        XCTAssertEqual(engine.stateChangeDueAt, 62)
        update(engine, 12, lean: leaning)
        XCTAssertEqual(engine.stateChangeDueAt, 62)
        XCTAssertEqual(update(engine, 62, lean: leaning), .bad(since: 2))
        XCTAssertNil(engine.stateChangeDueAt, "bad and still slouching: it stays bad")
    }

    func test_bad_turnsGoodAfterTheGracePeriodOfSittingWell() {
        let engine = PostureEngine()
        update(engine, 1, lean: well)
        for t in stride(from: 2.0, through: 62, by: 1) { update(engine, t, lean: leaning) }
        update(engine, 63, lean: well)
        XCTAssertEqual(engine.stateChangeDueAt, 63 + engine.thresholds.recoveryGracePeriod)
        update(engine, 64, lean: leaning)
        XCTAssertNil(engine.stateChangeDueAt, "slouched again: the recovery starts over")
    }

    func test_withNoPose_theCountdownPauses() {
        let engine = PostureEngine()
        update(engine, 1, lean: well)
        update(engine, 2, lean: leaning)
        engine.updateWithoutPose(at: 3, quality: .degraded)
        XCTAssertNil(engine.stateChangeDueAt)
    }
}
