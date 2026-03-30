import XCTest
@testable import PostureLogic

/// Tests for the `SipDetector` three-signal scoring state machine.
///
/// Covers all state transitions and the false-positive prevention logic:
/// - idle → candidate on proximity
/// - candidate → confirmed when score ≥ threshold
/// - candidate abandonment on wrist-departure or timeout
/// - cooldown suppression after confirmed sip
/// - chin-resting (zero velocity) never confirms
/// - duration band (too short / too long) never confirms
/// - both-wrist monitoring
///
/// NOTE: `onSipConfirmed` is set inline in each test, not via a factory,
/// because Swift closures capture *references* to local variables — returning
/// the events array from a helper would return a value copy that the closure
/// never updates.
final class SipDetectorTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a `PoseObservation` with two shoulders 0.3 units apart (x)
    /// and a nose at the origin. Wrist positions are specified as multipliers
    /// of shoulder width relative to nose.
    ///
    /// - Parameters:
    ///   - leftWristOffset:  Left wrist offset from nose in shoulder-width units.
    ///     (1, 1) = 1 shoulder-width away — well outside proximity threshold.
    ///   - rightWristOffset: Right wrist offset from nose.
    ///   - timestamp: Observation time.
    private func makeObservation(
        leftWristOffset:  CGPoint = CGPoint(x: 1, y: 1),
        rightWristOffset: CGPoint = CGPoint(x: 1, y: 1),
        timestamp: TimeInterval = 0
    ) -> PoseObservation {
        let ls  = Keypoint(joint: .leftShoulder,  position: CGPoint(x: 0.35, y: 0.5), confidence: 0.99)
        let rs  = Keypoint(joint: .rightShoulder, position: CGPoint(x: 0.65, y: 0.5), confidence: 0.99)
        let n   = Keypoint(joint: .nose,          position: CGPoint(x: 0.5,  y: 0.3), confidence: 0.99)
        // shoulderWidth = rs.x − ls.x = 0.3
        let lw  = Keypoint(joint: .leftWrist,
                           position: CGPoint(x: n.position.x + leftWristOffset.x  * 0.3,
                                             y: n.position.y + leftWristOffset.y  * 0.3),
                           confidence: 0.99)
        let rw  = Keypoint(joint: .rightWrist,
                           position: CGPoint(x: n.position.x + rightWristOffset.x * 0.3,
                                             y: n.position.y + rightWristOffset.y * 0.3),
                           confidence: 0.99)
        return PoseObservation(timestamp: timestamp, keypoints: [n, ls, rs, lw, rw], confidence: 0.99)
    }

    /// Left wrist very close to nose (normalised dist ≈ 0.07, well under 0.35 threshold).
    private func nearFaceLeft(timestamp: TimeInterval) -> PoseObservation {
        makeObservation(leftWristOffset: CGPoint(x: 0.05, y: 0.05), timestamp: timestamp)
    }

    /// Both wrists far from the face.
    private func farFromFace(timestamp: TimeInterval) -> PoseObservation {
        makeObservation(leftWristOffset:  CGPoint(x: 2, y: 2),
                        rightWristOffset: CGPoint(x: 2, y: 2),
                        timestamp: timestamp)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 1: Idle, no signals → stays idle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_idle_noSignals_noEvent() {
        let detector = SipDetector()
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        for t in stride(from: 0.0, through: 5.0, by: 0.1) {
            detector.process(farFromFace(timestamp: t))
        }
        XCTAssertTrue(events.isEmpty, "No sip events should fire when wrists are far from face")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 2: Proximity alone does not confirm immediately
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_proximity_alone_doesNotConfirmImmediately() {
        // Default thresholds: velocity non-zero, minDuration = 1.0, score required = 2.0
        // A single close frame has proximity (1 point) but no velocity history yet → score = 1 < 2
        let detector = SipDetector()
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        detector.process(nearFaceLeft(timestamp: 1.0))
        XCTAssertTrue(events.isEmpty, "Single close frame should not confirm a sip")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 3: All signals → confirmed sip
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_allSignals_confirmedSip() {
        // Set velocity threshold to 0 → velocity always credits
        // minDuration = 1.0 → need at least 1s of face proximity
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 0.0
        thresholds.minDuration = 1.0
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // Wrist starts far, then approaches and stays near for > 1s
        detector.process(farFromFace(timestamp: 0.0))
        for t in stride(from: 0.1, through: 2.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }

        XCTAssertEqual(events.count, 1, "Should have confirmed exactly one sip")
        XCTAssertGreaterThan(events[0].duration, 0, "Confirmed sip should have positive duration")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 4: Confirmed → cooldown suppresses immediate repeat
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_confirmed_entersCooldown_suppressesImmediateRepeat() {
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 0.0
        thresholds.minDuration = 1.0
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // First sip
        detector.process(farFromFace(timestamp: 0.0))
        for t in stride(from: 0.1, through: 2.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertEqual(events.count, 1, "First sip should confirm")

        // Immediately try again (within cooldown period of 30s)
        detector.process(farFromFace(timestamp: 2.1))
        for t in stride(from: 2.2, through: 4.5, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertEqual(events.count, 1, "Second sip during cooldown should be suppressed")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 5: Cooldown expires → allows next sip
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_cooldownExpiry_allowsNextSip() {
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 0.0
        thresholds.minDuration = 1.0
        thresholds.cooldownDuration = 5.0  // short cooldown for testing
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // First sip at t=0–2
        detector.process(farFromFace(timestamp: 0.0))
        for t in stride(from: 0.1, through: 2.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertEqual(events.count, 1)

        // After cooldown (5s), a new sip should be detectable
        let afterCooldown = 2.0 + 5.0 + 0.5  // safely past cooldown
        detector.process(farFromFace(timestamp: afterCooldown))
        for t in stride(from: afterCooldown + 0.1, through: afterCooldown + 2.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertEqual(events.count, 2, "Second sip after cooldown should be detected")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 6: Candidate abandoned when wrist leaves proximity
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_candidateAbandoned_ifProximityLost() {
        let detector = SipDetector()
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // Enter candidate, then move wrist away before minDuration elapses
        detector.process(nearFaceLeft(timestamp: 0.0))
        detector.process(nearFaceLeft(timestamp: 0.3))
        // < 1.0s elapsed → leave proximity
        detector.process(farFromFace(timestamp: 0.5))
        for t in stride(from: 0.6, through: 2.0, by: 0.1) {
            detector.process(farFromFace(timestamp: t))
        }
        XCTAssertTrue(events.isEmpty, "Sip candidate should be abandoned when wrist leaves proximity")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 7: Both wrists near face → exactly one sip fired
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_bothWrists_triggerOnFirst_noDoubleFire() {
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 0.0
        thresholds.minDuration = 1.0
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // Both wrists very close to nose for 2+ seconds
        detector.process(farFromFace(timestamp: 0.0))
        for t in stride(from: 0.1, through: 2.5, by: 0.1) {
            let obs = makeObservation(
                leftWristOffset:  CGPoint(x: 0.05, y: 0.05),
                rightWristOffset: CGPoint(x: 0.05, y: 0.05),
                timestamp: t
            )
            detector.process(obs)
        }
        XCTAssertEqual(events.count, 1, "Both wrists near face should produce exactly one sip event")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 8: Chin-resting (requires all 3 signals) → no confirm
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_chinResting_highVelocityRequired_doesNotConfirm() {
        // Setting required score to 3 and velocity threshold very high simulates
        // a scenario where zero-movement near the face never earns the velocity signal
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 100.0   // unreachably high
        thresholds.candidateScoreRequired = 3.0 // need all 3 signals
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // Wrist near face for a long time with no significant movement
        for t in stride(from: 0.0, through: 10.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertTrue(events.isEmpty,
            "Without velocity signal, chin-resting should not confirm even with proximity + duration")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 9: Duration too short → no confirm
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_durationTooShort_noConfirm() {
        // Require all 3 signals; velocity always hits (=0 threshold);
        // minDuration = 2.0s but we only stay near for 0.8s
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 0.0
        thresholds.minDuration = 2.0
        thresholds.candidateScoreRequired = 3.0
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        detector.process(farFromFace(timestamp: 0.0))
        for t in stride(from: 0.1, through: 0.8, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        detector.process(farFromFace(timestamp: 0.9))

        XCTAssertTrue(events.isEmpty, "Duration shorter than minDuration should not confirm")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 10: Duration exceeds maxDuration → candidate abandoned
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_durationTooLong_candidateAbandoned() {
        // velocity threshold unreachably high → velocity never credits
        // With only proximity (1) + duration (1) = 2 < candidateScoreRequired (3),
        // the candidate can never confirm — and must be abandoned when maxDuration elapses.
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 100.0  // never hits → max score is 2 (proximity + duration)
        thresholds.minDuration = 1.0
        thresholds.maxDuration = 3.0          // abandon after 3 seconds
        thresholds.candidateScoreRequired = 3.0  // requires all 3 signals
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        detector.process(farFromFace(timestamp: 0.0))
        // Stay near face well past maxDuration=3.0s with no velocity
        for t in stride(from: 0.1, through: 5.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertTrue(events.isEmpty,
            "Duration exceeding maxDuration should abandon candidate (models chin-resting)")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 11: reset() clears all state
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_reset_clearsState() {
        var thresholds = SipThresholds()
        thresholds.velocityThreshold = 0.0
        thresholds.minDuration = 1.0
        let detector = SipDetector(thresholds: thresholds)
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        // Confirm first sip → enters cooldown
        detector.process(farFromFace(timestamp: 0.0))
        for t in stride(from: 0.1, through: 2.0, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertEqual(events.count, 1)

        // Reset — cooldown cleared, back to idle
        detector.reset()

        // Should detect again immediately
        detector.process(farFromFace(timestamp: 2.5))
        for t in stride(from: 2.6, through: 4.5, by: 0.1) {
            detector.process(nearFaceLeft(timestamp: t))
        }
        XCTAssertEqual(events.count, 2, "After reset(), sip detection should resume from idle")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 12: Missing keypoints → silently ignored
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func test_missingKeypoints_doesNotCrash() {
        let detector = SipDetector()
        var events: [SipEvent] = []
        detector.onSipConfirmed = { events.append($0) }

        let empty = PoseObservation(timestamp: 1.0, keypoints: [], confidence: 0.0)
        detector.process(empty)
        XCTAssertTrue(events.isEmpty)
    }
}
