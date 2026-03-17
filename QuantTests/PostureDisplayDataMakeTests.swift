import XCTest
@testable import Quant
import PostureLogic

final class PostureDisplayDataMakeTests: XCTestCase {

    private let defaultThresholds = PostureThresholds()

    // MARK: - (a) forwardCreep at threshold => ratio 1.0

    func test_forwardCreepAtThreshold_ratioIsOne() {
        let raw = RawMetrics(
            timestamp: 0,
            forwardCreep: defaultThresholds.forwardCreepThreshold,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: 0,
            twist: 0,
            movementLevel: 0,
            headMovementPattern: .still
        )
        let data = PostureDisplayData.make(
            from: raw,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        let forwardCreep = data.metric(for: .forwardCreep)
        XCTAssertEqual(forwardCreep.ratio, 1.0, accuracy: 0.001)
    }

    // MARK: - (b) nil RawMetrics => all ratios 0.0

    func test_nilRawMetrics_allRatiosAreZero() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        for info in data.metrics {
            XCTAssertEqual(info.ratio, 0.0, "\(info.key) should have ratio 0.0")
        }
    }

    // MARK: - (c) worstOffender is highest ratio or nil when all zero

    func test_worstOffender_isHighestRatio() {
        let raw = RawMetrics(
            timestamp: 0,
            forwardCreep: 0,
            headDrop: defaultThresholds.headDropThreshold * 2,
            shoulderRounding: defaultThresholds.shoulderRoundingThreshold * 0.5,
            lateralLean: 0,
            twist: 0,
            movementLevel: 0,
            headMovementPattern: .still
        )
        let data = PostureDisplayData.make(
            from: raw,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertEqual(data.worstOffender?.key, .headDrop)
        XCTAssertTrue(data.worstOffender?.isWorstOffender == true)
    }

    func test_worstOffender_nilWhenAllZero() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertNil(data.worstOffender)
    }

    // MARK: - (d) aggregateScore 1.0 when all zero and 0.0 when all at threshold

    func test_aggregateScore_oneWhenAllZero() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertEqual(data.aggregateScore, 1.0, accuracy: 0.001)
    }

    func test_aggregateScore_zeroWhenAllAtThreshold() {
        let raw = RawMetrics(
            timestamp: 0,
            forwardCreep: defaultThresholds.forwardCreepThreshold,
            headDrop: defaultThresholds.headDropThreshold,
            shoulderRounding: defaultThresholds.shoulderRoundingThreshold,
            lateralLean: defaultThresholds.sideLeanThreshold,
            twist: defaultThresholds.twistThreshold,
            movementLevel: 0,
            headMovementPattern: .still
        )
        let data = PostureDisplayData.make(
            from: raw,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertEqual(data.aggregateScore, 0.0, accuracy: 0.001)
    }

    // MARK: - (e) isAlertMode true for drifting/bad, false for good/absent/calibrating

    func test_isAlertMode_trueForDrifting() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .drifting(since: Date().timeIntervalSince1970),
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertTrue(data.isAlertMode)
    }

    func test_isAlertMode_trueForBad() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .bad(since: Date().timeIntervalSince1970),
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertTrue(data.isAlertMode)
    }

    func test_isAlertMode_falseForGood() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertFalse(data.isAlertMode)
    }

    func test_isAlertMode_falseForAbsent() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .absent,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertFalse(data.isAlertMode)
    }

    func test_isAlertMode_falseForCalibrating() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .calibrating,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertFalse(data.isAlertMode)
    }

    // MARK: - (f) nudgeCountdownSeconds non-nil only for .pending

    func test_nudgeCountdown_nonNilForPending() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .pending(reason: .sustainedSlouch, timeRemaining: 42.0),
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertEqual(data.nudgeCountdownSeconds, 42.0)
    }

    func test_nudgeCountdown_nilForNone() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .none,
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertNil(data.nudgeCountdownSeconds)
    }

    func test_nudgeCountdown_nilForFire() {
        let data = PostureDisplayData.make(
            from: nil,
            postureState: .good,
            nudgeDecision: .fire(reason: .sustainedSlouch),
            trackingQuality: .good,
            thresholds: defaultThresholds
        )
        XCTAssertNil(data.nudgeCountdownSeconds)
    }
}
