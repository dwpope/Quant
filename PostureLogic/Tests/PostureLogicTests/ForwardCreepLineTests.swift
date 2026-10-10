import XCTest
@testable import PostureLogic

/// The forward-lean line is 6%, not 3% (2026-10-10).
///
/// In real work Dave sits well at +2% to +5% forward creep, even freshly calibrated (session 3,
/// 2026-10-10; +3.5% to +5% in hour 2 on an older calibration). Reaching for the keyboard brings
/// the shoulders a little closer to the camera. At 3% (3.9% while reading) that flickered between
/// good and drifting and added up: two of session 3's four nudges came from sitting well. In the
/// posed captures good posture reached +4.4%, every slouch between 3% and 6% also had a head drop
/// or a sink (which count on their own), and slouches by forward creep alone began at +9.2%.
final class ForwardCreepLineTests: XCTestCase {

    private func state(creep: Float, headDrop: Float = 0, taskMode: TaskMode = .unknown) -> PostureState {
        let engine = PostureEngine()
        engine.update(metrics: RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0,
                                          lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still),
                      taskMode: taskMode, trackingQuality: .good)
        let m = RawMetrics(timestamp: 1, forwardCreep: creep, headDrop: headDrop, shoulderRounding: 0,
                           lateralLean: 0, twist: 0, movementLevel: 0, headMovementPattern: .still)
        return engine.update(metrics: m, taskMode: taskMode, trackingQuality: .good)
    }

    private func drifts(_ s: PostureState) -> Bool {
        if case .drifting = s { return true }
        return false
    }

    func test_theLine_isSixPercent() {
        XCTAssertEqual(PostureThresholds().forwardCreepThreshold, 0.06)
    }

    /// Sitting well at the keyboard, as session 3 read it.
    func test_sittingWellWhileWorking_isGood() {
        for creep: Float in [0.033, 0.039, 0.044, 0.048, 0.051, 0.055] {
            XCTAssertEqual(state(creep: creep), .good, "\(creep)")
            XCTAssertEqual(state(creep: creep, taskMode: .reading), .good, "\(creep) reading")
        }
    }

    /// Slouches by forward creep alone: posed from +9.2%, real ones in session 3 at +9.7% to +19.5%.
    func test_aForwardSlouch_stillCounts() {
        for creep: Float in [0.092, 0.097, 0.165, 0.195] {
            XCTAssertTrue(drifts(state(creep: creep)), "\(creep)")
            XCTAssertTrue(drifts(state(creep: creep, taskMode: .reading)), "\(creep) reading")
        }
    }

    /// A slouch that leans in a little and drops the head is still caught, by the head drop.
    func test_aSmallLeanWithTheHeadDropping_stillCounts() {
        XCTAssertTrue(drifts(state(creep: 0.046, headDrop: -0.045)))
    }
}
