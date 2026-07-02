import simd
import XCTest
@testable import PostureLogic

/// Codable round-trip and default-value tests for model types that previously
/// only had indirect coverage through engine / service tests.
///
/// Covers: SipThresholds, PostureThresholds, PoseSample, RawMetrics,
/// MovementPattern, DepthMode, TaskMode, RecordedSession, Tag, TagLabel,
/// TagSource, SessionMetadata, ThermalLevel, Joint.
final class CoreModelCodableTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - SipThresholds

    func testSipThresholds_defaultValues() {
        let t = SipThresholds()
        XCTAssertEqual(t.proximityThreshold, 0.35)
        XCTAssertEqual(t.velocityThreshold, 0.008)
        XCTAssertEqual(t.minDuration, 1.0)
        XCTAssertEqual(t.maxDuration, 8.0)
        XCTAssertEqual(t.candidateScoreRequired, 2.0)
        XCTAssertEqual(t.cooldownDuration, 30.0)
    }

    func testSipThresholds_codableRoundTrip_defaults() throws {
        let original = SipThresholds()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SipThresholds.self, from: data)
        XCTAssertEqual(decoded.proximityThreshold, original.proximityThreshold)
        XCTAssertEqual(decoded.velocityThreshold, original.velocityThreshold)
        XCTAssertEqual(decoded.minDuration, original.minDuration)
        XCTAssertEqual(decoded.maxDuration, original.maxDuration)
        XCTAssertEqual(decoded.candidateScoreRequired, original.candidateScoreRequired)
        XCTAssertEqual(decoded.cooldownDuration, original.cooldownDuration)
    }

    func testSipThresholds_codableRoundTrip_customValues() throws {
        var original = SipThresholds()
        original.proximityThreshold = 0.5
        original.velocityThreshold = 0.02
        original.minDuration = 0.5
        original.maxDuration = 12.0
        original.candidateScoreRequired = 3.0
        original.cooldownDuration = 60.0
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SipThresholds.self, from: data)
        XCTAssertEqual(decoded.proximityThreshold, 0.5)
        XCTAssertEqual(decoded.velocityThreshold, 0.02)
        XCTAssertEqual(decoded.minDuration, 0.5)
        XCTAssertEqual(decoded.maxDuration, 12.0)
        XCTAssertEqual(decoded.candidateScoreRequired, 3.0)
        XCTAssertEqual(decoded.cooldownDuration, 60.0)
    }

    // MARK: - PostureThresholds

    func testPostureThresholds_defaultValues() {
        let t = PostureThresholds()
        XCTAssertEqual(t.slouchDurationBeforeNudge, 300)
        XCTAssertEqual(t.recoveryGracePeriod, 5)
        XCTAssertEqual(t.driftingToBadThreshold, 60)
        XCTAssertEqual(t.forwardCreepThreshold, 0.03)
        XCTAssertEqual(t.twistThreshold, 15.0)
        XCTAssertEqual(t.sideLeanThreshold, 0.08)
        XCTAssertEqual(t.headDropThreshold, 0.06)
        XCTAssertEqual(t.shoulderRoundingThreshold, 10.0)
        XCTAssertEqual(t.nudgeCooldown, 600)
        XCTAssertEqual(t.maxNudgesPerHour, 2)
        XCTAssertEqual(t.absentThreshold, 1.0)
    }

    func testPostureThresholds_codableRoundTrip() throws {
        var original = PostureThresholds()
        original.forwardCreepThreshold = 0.05
        original.twistThreshold = 20.0
        original.maxNudgesPerHour = 5
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PostureThresholds.self, from: data)
        XCTAssertEqual(decoded.forwardCreepThreshold, 0.05)
        XCTAssertEqual(decoded.twistThreshold, 20.0)
        XCTAssertEqual(decoded.maxNudgesPerHour, 5)
        // Unchanged fields keep defaults
        XCTAssertEqual(decoded.slouchDurationBeforeNudge, 300)
    }

    // MARK: - DepthMode

    func testDepthMode_codableRoundTrip_allCases() throws {
        for mode in [DepthMode.depthFusion, .twoDOnly] {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(DepthMode.self, from: data)
            XCTAssertEqual(decoded, mode, "Round-trip failed for \(mode)")
        }
    }

    func testDepthMode_rawValues() {
        XCTAssertEqual(DepthMode.depthFusion.rawValue, "depthFusion")
        XCTAssertEqual(DepthMode.twoDOnly.rawValue, "twoDOnly")
    }

    // MARK: - TaskMode

    func testTaskMode_codableRoundTrip_allCases() throws {
        let allCases: [TaskMode] = [.unknown, .reading, .typing, .meeting, .stretching]
        for mode in allCases {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(TaskMode.self, from: data)
            XCTAssertEqual(decoded, mode, "Round-trip failed for \(mode)")
        }
    }

    // MARK: - MovementPattern

    func testMovementPattern_codableRoundTrip_allCases() throws {
        let allCases: [MovementPattern] = [.still, .smallOscillations, .largeMovements, .erratic]
        for pattern in allCases {
            let data = try encoder.encode(pattern)
            let decoded = try decoder.decode(MovementPattern.self, from: data)
            XCTAssertEqual(decoded, pattern, "Round-trip failed for \(pattern)")
        }
    }

    // MARK: - RawMetrics

    func testRawMetrics_codableRoundTrip() throws {
        let original = RawMetrics(
            timestamp: 1000.0,
            forwardCreep: 0.02,
            headDrop: 0.04,
            shoulderRounding: 8.0,
            lateralLean: 0.01,
            twist: 3.0,
            movementLevel: 0.5,
            headMovementPattern: .smallOscillations
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RawMetrics.self, from: data)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.forwardCreep, original.forwardCreep)
        XCTAssertEqual(decoded.headDrop, original.headDrop)
        XCTAssertEqual(decoded.shoulderRounding, original.shoulderRounding)
        XCTAssertEqual(decoded.lateralLean, original.lateralLean)
        XCTAssertEqual(decoded.twist, original.twist)
        XCTAssertEqual(decoded.movementLevel, original.movementLevel)
        XCTAssertEqual(decoded.headMovementPattern, .smallOscillations)
    }

    func testRawMetrics_preservesZeroValues() throws {
        let original = RawMetrics(
            timestamp: 0,
            forwardCreep: 0,
            headDrop: 0,
            shoulderRounding: 0,
            lateralLean: 0,
            twist: 0,
            movementLevel: 0,
            headMovementPattern: .still
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RawMetrics.self, from: data)
        XCTAssertEqual(decoded.timestamp, 0)
        XCTAssertEqual(decoded.forwardCreep, 0)
        XCTAssertEqual(decoded.headMovementPattern, .still)
    }

    // MARK: - PoseSample

    func testPoseSample_codableRoundTrip() throws {
        let original = PoseSample(
            timestamp: 42.0,
            depthMode: .depthFusion,
            headPosition: SIMD3<Float>(0.5, 0.3, 0.75),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.5, 0.8),
            leftShoulder: SIMD3<Float>(0.3, 0.5, 0.8),
            rightShoulder: SIMD3<Float>(0.7, 0.5, 0.8),
            torsoAngle: 5.0,
            headForwardOffset: 0.02,
            shoulderTwist: 2.5,
            shoulderWidthRaw: 0.4,
            trackingQuality: .good
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PoseSample.self, from: data)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.depthMode, .depthFusion)
        XCTAssertEqual(decoded.headPosition, original.headPosition)
        XCTAssertEqual(decoded.shoulderMidpoint, original.shoulderMidpoint)
        XCTAssertEqual(decoded.leftShoulder, original.leftShoulder)
        XCTAssertEqual(decoded.rightShoulder, original.rightShoulder)
        XCTAssertEqual(decoded.torsoAngle, original.torsoAngle)
        XCTAssertEqual(decoded.headForwardOffset, original.headForwardOffset)
        XCTAssertEqual(decoded.shoulderTwist, original.shoulderTwist)
        XCTAssertEqual(decoded.shoulderWidthRaw, original.shoulderWidthRaw)
        XCTAssertEqual(decoded.trackingQuality, .good)
    }

    func testPoseSample_codableRoundTrip_twoDOnlyMode() throws {
        let original = PoseSample(
            timestamp: 10.0,
            depthMode: .twoDOnly,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .lost
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PoseSample.self, from: data)
        XCTAssertEqual(decoded.depthMode, .twoDOnly)
        XCTAssertEqual(decoded.trackingQuality, .lost)
        XCTAssertEqual(decoded.headPosition, .zero)
    }

    func testPoseSample_headOrientation_codableRoundTrip_nonNil() throws {
        let quat = SIMD4<Float>(0.1, -0.2, 0.3, 0.927)
        let original = PoseSample(
            timestamp: 7.0,
            depthMode: .depthFusion,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .good,
            headOrientation: quat
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PoseSample.self, from: data)
        XCTAssertEqual(decoded.headOrientation, quat)
    }

    func testPoseSample_headOrientation_defaultsNil() {
        let sample = PoseSample(
            timestamp: 0,
            depthMode: .twoDOnly,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .lost
        )
        XCTAssertNil(sample.headOrientation)
    }

    /// Backward-compat: a `PoseSample` encoded without `headOrientation` (an old
    /// recording) decodes with the field `nil`. Encoding a nil-headOrientation
    /// sample and decoding must round-trip to nil.
    func testPoseSample_headOrientation_nilRoundTrip() throws {
        let original = PoseSample(
            timestamp: 3.0,
            depthMode: .depthFusion,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .good
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PoseSample.self, from: data)
        XCTAssertNil(decoded.headOrientation)
    }

    func testPoseSample_neckHeight_codableRoundTrip() throws {
        let original = PoseSample(
            timestamp: 5.0,
            depthMode: .twoDOnly,
            headPosition: .zero,
            shoulderMidpoint: .zero,
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 0,
            headForwardOffset: 0,
            shoulderTwist: 0,
            shoulderWidthRaw: 0,
            trackingQuality: .good,
            neckHeight: 0.73
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PoseSample.self, from: data)
        XCTAssertEqual(decoded.neckHeight, 0.73, accuracy: 0.0001)
    }

    /// Backward-compat: JSON for a `PoseSample` written before `neckHeight` existed
    /// (no such key) must decode with `neckHeight == 0` so old recordings still load.
    func testPoseSample_neckHeight_missingKey_decodesToZero() throws {
        let sample = PoseSample(
            timestamp: 5.0,
            depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0.1, 0.2, 0),
            shoulderMidpoint: SIMD3<Float>(0.1, 0.1, 0),
            leftShoulder: .zero,
            rightShoulder: .zero,
            torsoAngle: 3,
            headForwardOffset: 0,
            shoulderTwist: 1,
            shoulderWidthRaw: 0.2,
            trackingQuality: .good,
            neckHeight: 0.9
        )
        // Encode, then strip the `neckHeight` key to simulate an old recording.
        let data = try encoder.encode(sample)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["neckHeight"], "Precondition: current encoding writes the key")
        object.removeValue(forKey: "neckHeight")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder.decode(PoseSample.self, from: stripped)
        XCTAssertEqual(decoded.neckHeight, 0, "Missing neckHeight must default to 0")
        // The rest of the record still decodes intact.
        XCTAssertEqual(decoded.torsoAngle, 3, accuracy: 0.0001)
        XCTAssertEqual(decoded.shoulderWidthRaw, 0.2, accuracy: 0.0001)
    }

    // MARK: - Baseline

    func testBaseline_codableRoundTrip_withNeckHeight() throws {
        let original = Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.4, 0),
            headPosition: SIMD3<Float>(0.5, 0.25, 0),
            torsoAngle: 2,
            shoulderTwist: 1.5,
            shoulderWidth: 0.3,
            depthAvailable: true,
            neckHeight: 0.42
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Baseline.self, from: data)
        XCTAssertEqual(decoded.torsoAngle, 2, accuracy: 0.0001)
        XCTAssertEqual(decoded.shoulderTwist, 1.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.shoulderWidth, 0.3, accuracy: 0.0001)
        XCTAssertTrue(decoded.depthAvailable)
        XCTAssertEqual(decoded.neckHeight, 0.42, accuracy: 0.0001)
    }

    /// Backward-compat: a persisted `Baseline` without `neckHeight` decodes with the
    /// field defaulting to 0.
    func testBaseline_neckHeight_missingKey_decodesToZero() throws {
        let baseline = Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.4, 0),
            headPosition: SIMD3<Float>(0.5, 0.25, 0),
            torsoAngle: 2,
            shoulderTwist: 1.5,
            shoulderWidth: 0.3,
            depthAvailable: false,
            neckHeight: 0.42
        )
        let data = try encoder.encode(baseline)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "neckHeight")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder.decode(Baseline.self, from: stripped)
        XCTAssertEqual(decoded.neckHeight, 0, "Missing neckHeight must default to 0")
        XCTAssertEqual(decoded.shoulderWidth, 0.3, accuracy: 0.0001)
        XCTAssertEqual(decoded.shoulderTwist, 1.5, accuracy: 0.0001)
    }

    /// Backward-compat: a `Baseline` also predating `shoulderTwist` (neither key)
    /// still decodes, both additive fields defaulting to 0.
    func testBaseline_missingShoulderTwistAndNeckHeight_decodeToZero() throws {
        let baseline = Baseline(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            shoulderMidpoint: .zero,
            headPosition: .zero,
            torsoAngle: 0,
            shoulderWidth: 0.3,
            depthAvailable: false
        )
        let data = try encoder.encode(baseline)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "shoulderTwist")
        object.removeValue(forKey: "neckHeight")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder.decode(Baseline.self, from: stripped)
        XCTAssertEqual(decoded.shoulderTwist, 0)
        XCTAssertEqual(decoded.neckHeight, 0)
    }

    // MARK: - ThermalLevel

    func testThermalLevel_codableRoundTrip_allCases() throws {
        for level in ThermalLevel.allCases {
            let data = try encoder.encode(level)
            let decoded = try decoder.decode(ThermalLevel.self, from: data)
            XCTAssertEqual(decoded, level, "Round-trip failed for \(level)")
        }
    }

    func testThermalLevel_rawValueOrdering() {
        XCTAssertEqual(ThermalLevel.nominal.rawValue, 0)
        XCTAssertEqual(ThermalLevel.fair.rawValue, 1)
        XCTAssertEqual(ThermalLevel.serious.rawValue, 2)
        XCTAssertEqual(ThermalLevel.critical.rawValue, 3)
    }

    // MARK: - Recording types

    func testTag_codableRoundTrip() throws {
        let original = Tag(timestamp: 500.0, label: .slouching, source: .automatic)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Tag.self, from: data)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.label, .slouching)
        XCTAssertEqual(decoded.source, .automatic)
    }

    func testTagLabel_codableRoundTrip_allCases() throws {
        let allCases: [TagLabel] = [
            .goodPosture, .slouching, .reading, .typing, .stretching, .absent
        ]
        for label in allCases {
            let data = try encoder.encode(label)
            let decoded = try decoder.decode(TagLabel.self, from: data)
            XCTAssertEqual(decoded, label, "Round-trip failed for \(label)")
        }
    }

    func testTagSource_codableRoundTrip_allCases() throws {
        let allCases: [TagSource] = [.manual, .voice, .automatic]
        for source in allCases {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(TagSource.self, from: data)
            XCTAssertEqual(decoded, source, "Round-trip failed for \(source)")
        }
    }

    func testSessionMetadata_codableRoundTrip() throws {
        let original = SessionMetadata(
            deviceModel: "iPhone15,2",
            depthAvailable: true,
            thresholds: PostureThresholds()
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SessionMetadata.self, from: data)
        XCTAssertEqual(decoded.deviceModel, "iPhone15,2")
        XCTAssertTrue(decoded.depthAvailable)
        XCTAssertEqual(decoded.thresholds.slouchDurationBeforeNudge, 300)
    }

    func testRecordedSession_codableRoundTrip() throws {
        let sessionID = UUID()
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)
        let sample = PoseSample(
            timestamp: 1.0,
            depthMode: .depthFusion,
            headPosition: SIMD3<Float>(0.5, 0.3, 0.75),
            shoulderMidpoint: SIMD3<Float>(0.5, 0.5, 0.8),
            leftShoulder: SIMD3<Float>(0.3, 0.5, 0.8),
            rightShoulder: SIMD3<Float>(0.7, 0.5, 0.8),
            torsoAngle: 5.0,
            headForwardOffset: 0.02,
            shoulderTwist: 2.5,
            shoulderWidthRaw: 0.4,
            trackingQuality: .good
        )
        let tag = Tag(timestamp: 10.0, label: .goodPosture, source: .manual)
        let metadata = SessionMetadata(
            deviceModel: "iPhone15,2",
            depthAvailable: true,
            thresholds: PostureThresholds()
        )
        let original = RecordedSession(
            id: sessionID,
            startTime: start,
            endTime: end,
            samples: [sample],
            tags: [tag],
            metadata: metadata
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RecordedSession.self, from: data)
        XCTAssertEqual(decoded.id, sessionID)
        XCTAssertEqual(decoded.startTime, start)
        XCTAssertEqual(decoded.endTime, end)
        XCTAssertEqual(decoded.samples.count, 1)
        XCTAssertEqual(decoded.samples[0].torsoAngle, 5.0)
        XCTAssertEqual(decoded.tags.count, 1)
        XCTAssertEqual(decoded.tags[0].label, .goodPosture)
        XCTAssertEqual(decoded.metadata.deviceModel, "iPhone15,2")
    }

    func testRecordedSession_codableRoundTrip_emptySamplesAndTags() throws {
        let original = RecordedSession(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1700000000),
            endTime: Date(timeIntervalSince1970: 1700000001),
            samples: [],
            tags: [],
            metadata: SessionMetadata(
                deviceModel: "iPhone14,3",
                depthAvailable: false,
                thresholds: PostureThresholds()
            )
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RecordedSession.self, from: data)
        XCTAssertTrue(decoded.samples.isEmpty)
        XCTAssertTrue(decoded.tags.isEmpty)
        XCTAssertFalse(decoded.metadata.depthAvailable)
    }

    // MARK: - Joint (enum)

    func testJoint_codableRoundTrip_allCases() throws {
        for joint in Joint.allCases {
            let data = try encoder.encode(joint)
            let decoded = try decoder.decode(Joint.self, from: data)
            XCTAssertEqual(decoded, joint, "Round-trip failed for \(joint)")
        }
    }

    func testJoint_allCases_count() {
        // Lock in the expected joint count so additions require a test update.
        XCTAssertEqual(Joint.allCases.count, 17)
    }
}
