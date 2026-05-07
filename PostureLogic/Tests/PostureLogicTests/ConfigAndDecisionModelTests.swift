import XCTest
@testable import PostureLogic

/// Dedicated tests for configuration and decision model types:
/// `NudgeDecision`, `PostureThresholds`, `SipThresholds`, and `CalibrationStatus`.
///
/// These types are used throughout the pipeline but previously had no dedicated
/// unit tests — only indirect exercise through engine and service tests.
/// This file pins Codable round-trips (especially important for enums with
/// associated values), default threshold values, and Equatable semantics.
final class ConfigAndDecisionModelTests: XCTestCase {

    // MARK: - NudgeDecision: Codable round-trips

    func testNudgeDecision_none_roundTrips() throws {
        let original = NudgeDecision.none
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NudgeDecision.self, from: data)
        // NudgeDecision doesn't conform to Equatable, so match on case
        guard case .none = decoded else {
            return XCTFail("Expected .none, got \(decoded)")
        }
    }

    func testNudgeDecision_pending_roundTrips() throws {
        let original = NudgeDecision.pending(reason: .sustainedSlouch, timeRemaining: 42.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NudgeDecision.self, from: data)
        guard case .pending(let reason, let time) = decoded else {
            return XCTFail("Expected .pending, got \(decoded)")
        }
        XCTAssertEqual(reason, .sustainedSlouch)
        XCTAssertEqual(time, 42.5, accuracy: 0.001)
    }

    func testNudgeDecision_fire_roundTripsAllReasons() throws {
        for reason in [NudgeReason.sustainedSlouch, .forwardCreep, .headDrop] {
            let original = NudgeDecision.fire(reason: reason)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(NudgeDecision.self, from: data)
            guard case .fire(let decodedReason) = decoded else {
                return XCTFail("Expected .fire for \(reason), got \(decoded)")
            }
            XCTAssertEqual(decodedReason, reason)
        }
    }

    func testNudgeDecision_suppressed_roundTripsAllReasons() throws {
        let allReasons: [SuppressionReason] = [
            .cooldownActive, .maxNudgesReached, .userStretching,
            .lowTrackingQuality, .recentAcknowledgement
        ]
        for reason in allReasons {
            let original = NudgeDecision.suppressed(reason: reason)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(NudgeDecision.self, from: data)
            guard case .suppressed(let decodedReason) = decoded else {
                return XCTFail("Expected .suppressed for \(reason), got \(decoded)")
            }
            XCTAssertEqual(decodedReason, reason)
        }
    }

    // MARK: - NudgeReason: raw values are stable

    func testNudgeReason_rawValues() {
        XCTAssertEqual(NudgeReason.sustainedSlouch.rawValue, "sustainedSlouch")
        XCTAssertEqual(NudgeReason.forwardCreep.rawValue, "forwardCreep")
        XCTAssertEqual(NudgeReason.headDrop.rawValue, "headDrop")
    }

    // MARK: - SuppressionReason: raw values are stable

    func testSuppressionReason_rawValues() {
        XCTAssertEqual(SuppressionReason.cooldownActive.rawValue, "cooldownActive")
        XCTAssertEqual(SuppressionReason.maxNudgesReached.rawValue, "maxNudgesReached")
        XCTAssertEqual(SuppressionReason.userStretching.rawValue, "userStretching")
        XCTAssertEqual(SuppressionReason.lowTrackingQuality.rawValue, "lowTrackingQuality")
        XCTAssertEqual(SuppressionReason.recentAcknowledgement.rawValue, "recentAcknowledgement")
    }

    // MARK: - PostureThresholds: defaults

    func testPostureThresholds_defaultValues() {
        let t = PostureThresholds()

        // Detection timing
        XCTAssertEqual(t.slouchDurationBeforeNudge, 300)
        XCTAssertEqual(t.recoveryGracePeriod, 5)
        XCTAssertEqual(t.driftingToBadThreshold, 60)

        // Posture metrics
        XCTAssertEqual(t.forwardCreepThreshold, 0.03)
        XCTAssertEqual(t.twistThreshold, 15.0)
        XCTAssertEqual(t.sideLeanThreshold, 0.08)
        XCTAssertEqual(t.headDropThreshold, 0.06)
        XCTAssertEqual(t.shoulderRoundingThreshold, 10.0)

        // Confidence gates
        XCTAssertEqual(t.minTrackingQuality, 0.7)
        XCTAssertEqual(t.minKeypointVisibility, 0.7)
        XCTAssertEqual(t.depthConfidenceThreshold, 0.6)

        // Nudge behavior
        XCTAssertEqual(t.nudgeCooldown, 600)
        XCTAssertEqual(t.maxNudgesPerHour, 2)
        XCTAssertEqual(t.acknowledgementWindow, 30)

        // Mode switching
        XCTAssertEqual(t.depthRecoveryDelay, 2.0)
        XCTAssertEqual(t.absentThreshold, 1.0)
        XCTAssertEqual(t.absentResumeThreshold, 30.0)
        XCTAssertEqual(t.returnValidationWindow, 2.0)
    }

    func testPostureThresholds_codableRoundTrip() throws {
        var original = PostureThresholds()
        original.slouchDurationBeforeNudge = 120
        original.forwardCreepThreshold = 0.05
        original.maxNudgesPerHour = 5

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PostureThresholds.self, from: data)

        XCTAssertEqual(decoded.slouchDurationBeforeNudge, 120)
        XCTAssertEqual(decoded.forwardCreepThreshold, 0.05)
        XCTAssertEqual(decoded.maxNudgesPerHour, 5)
        // Untouched fields keep defaults
        XCTAssertEqual(decoded.recoveryGracePeriod, 5)
        XCTAssertEqual(decoded.twistThreshold, 15.0)
    }

    func testPostureThresholds_mutability() {
        var t = PostureThresholds()
        t.nudgeCooldown = 300
        XCTAssertEqual(t.nudgeCooldown, 300)
        t.absentThreshold = 2.0
        XCTAssertEqual(t.absentThreshold, 2.0)
    }

    // MARK: - SipThresholds: defaults

    func testSipThresholds_defaultValues() {
        let t = SipThresholds()

        XCTAssertEqual(t.proximityThreshold, 0.35)
        XCTAssertEqual(t.velocityThreshold, 0.008)
        XCTAssertEqual(t.minDuration, 1.0)
        XCTAssertEqual(t.maxDuration, 8.0)
        XCTAssertEqual(t.candidateScoreRequired, 2.0)
        XCTAssertEqual(t.cooldownDuration, 30.0)
    }

    func testSipThresholds_codableRoundTrip() throws {
        var original = SipThresholds()
        original.proximityThreshold = 0.25
        original.cooldownDuration = 15.0

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SipThresholds.self, from: data)

        XCTAssertEqual(decoded.proximityThreshold, 0.25)
        XCTAssertEqual(decoded.cooldownDuration, 15.0)
        // Untouched fields keep defaults
        XCTAssertEqual(decoded.velocityThreshold, 0.008)
        XCTAssertEqual(decoded.minDuration, 1.0)
    }

    func testSipThresholds_durationBandInvariant() {
        let t = SipThresholds()
        XCTAssertLessThan(
            t.minDuration, t.maxDuration,
            "minDuration must be less than maxDuration for a valid detection window"
        )
    }

    // MARK: - CalibrationStatus: Equatable

    func testCalibrationStatus_simpleEquality() {
        XCTAssertEqual(CalibrationStatus.waiting, .waiting)
        XCTAssertEqual(CalibrationStatus.sampling, .sampling)
        XCTAssertEqual(CalibrationStatus.validating, .validating)
        XCTAssertEqual(CalibrationStatus.success, .success)

        XCTAssertNotEqual(CalibrationStatus.waiting, .sampling)
        XCTAssertNotEqual(CalibrationStatus.success, .waiting)
    }

    func testCalibrationStatus_countdownEquality() {
        XCTAssertEqual(CalibrationStatus.countdown(3), .countdown(3))
        XCTAssertNotEqual(CalibrationStatus.countdown(3), .countdown(2))
        XCTAssertNotEqual(CalibrationStatus.countdown(1), .waiting)
    }

    func testCalibrationStatus_failedEquality() {
        XCTAssertEqual(
            CalibrationStatus.failed("too much movement"),
            .failed("too much movement")
        )
        XCTAssertNotEqual(
            CalibrationStatus.failed("too much movement"),
            .failed("insufficient data")
        )
        XCTAssertNotEqual(CalibrationStatus.failed("error"), .success)
    }

    // MARK: - MovementPattern: raw values

    func testMovementPattern_rawValues() {
        XCTAssertEqual(MovementPattern.still.rawValue, "still")
        XCTAssertEqual(MovementPattern.smallOscillations.rawValue, "smallOscillations")
        XCTAssertEqual(MovementPattern.largeMovements.rawValue, "largeMovements")
        XCTAssertEqual(MovementPattern.erratic.rawValue, "erratic")
    }

    func testMovementPattern_codableRoundTrip() throws {
        for pattern in [MovementPattern.still, .smallOscillations, .largeMovements, .erratic] {
            let data = try JSONEncoder().encode(pattern)
            let decoded = try JSONDecoder().decode(MovementPattern.self, from: data)
            XCTAssertEqual(decoded, pattern)
        }
    }

    // MARK: - TaskMode: raw values and round-trip

    func testTaskMode_rawValues() {
        XCTAssertEqual(TaskMode.unknown.rawValue, "unknown")
        XCTAssertEqual(TaskMode.reading.rawValue, "reading")
        XCTAssertEqual(TaskMode.typing.rawValue, "typing")
        XCTAssertEqual(TaskMode.meeting.rawValue, "meeting")
        XCTAssertEqual(TaskMode.stretching.rawValue, "stretching")
    }

    func testTaskMode_codableRoundTrip() throws {
        for mode in [TaskMode.unknown, .reading, .typing, .meeting, .stretching] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TaskMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }
}
