import XCTest
@testable import PostureLogic

/// A gentle lean back isn't a head-drop slouch (2026-10-06).
///
/// Session 10's lean-backs moved the shoulders only 10–13% back (forward creep -0.129, -0.097),
/// short of the -0.15 recline line, and keeping the eyes on the screen tipped the head towards the
/// shoulders (head drop -0.059, -0.045), so the thresholds called them slouch. A dropping head in
/// a slouch comes with the shoulders forward or still: across every capture so far, the slouches
/// that tripped head drop read forward creep -0.036 or above. Head drop now counts only while the
/// shoulders haven't moved 5% or more back.
final class HeadDropShouldersBackTests: XCTestCase {

    func test_theLine_isShoulders5PercentBack() {
        XCTAssertEqual(PostureThresholds().headDropMinForwardCreep, -0.05)
    }

    private func state(headDrop: Float, creep: Float, lean: Float = 0) -> PostureState {
        let engine = PostureEngine()
        let calm = RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                              lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still)
        engine.update(metrics: calm, taskMode: .unknown, trackingQuality: .good)
        let m = RawMetrics(timestamp: 1, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                           lateralLean: lean, twist: 0, movementLevel: 0, headMovementPattern: .still)
        return engine.update(metrics: m, taskMode: .unknown, trackingQuality: .good)
    }

    private func drifts(_ s: PostureState) -> Bool {
        if case .drifting = s { return true }
        return false
    }

    /// Session 10's two gentle lean-backs, and session 9's two deeper ones.
    func test_leaningBack_isNotAHeadDropSlouch() {
        for (hd, fc): (Float, Float) in [(-0.059, -0.129), (-0.045, -0.097), (-0.039, -0.232), (-0.100, -0.233)] {
            XCTAssertEqual(state(headDrop: hd, creep: fc), .good, "\(hd) \(fc)")
        }
    }

    /// Every slouch that tripped head drop, with the shoulders back the most: still a slouch.
    func test_slouchesThatTrippedHeadDrop_stillDo() {
        for (hd, fc): (Float, Float) in [(-0.065, -0.036), (-0.020, -0.023), (-0.104, -0.006), (-0.040, -0.004)] {
            XCTAssertTrue(drifts(state(headDrop: hd, creep: fc)), "\(hd) \(fc)")
        }
    }

    /// A lean with the shoulders back still counts, by its sideways shift.
    func test_aLeanWithTheShouldersBack_stillCounts() {
        XCTAssertTrue(drifts(state(headDrop: -0.127, creep: -0.097, lean: 0.094)))
    }

    func test_limitsSavedBeforeThis_stillRead() throws {
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PostureThresholds()))
            as? [String: Any])
        older.removeValue(forKey: "headDropMinForwardCreep")
        let decoded = try JSONDecoder().decode(PostureThresholds.self, from: JSONSerialization.data(withJSONObject: older))
        XCTAssertEqual(decoded.headDropMinForwardCreep, -0.05)
    }
}
