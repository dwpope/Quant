import Foundation
import simd
@testable import PostureLogic

// MARK: - Golden Recording Factories

/// Synthetic test recordings that simulate realistic posture sessions.
/// Each factory returns a `RecordedSession` with PoseSamples at ~0.1s intervals.
enum GoldenRecordings {

    // MARK: - Shared Constants

    /// Baseline-matching "good" posture values.
    private static let goodHead = SIMD3<Float>(0, 1.0, 0)
    private static let goodShoulderMid = SIMD3<Float>(0, 0, 0)
    private static let goodLeftShoulder = SIMD3<Float>(-0.5, 0, 0)
    private static let goodRightShoulder = SIMD3<Float>(0.5, 0, 0)
    private static let goodTorsoAngle: Float = 5
    private static let goodHeadForwardOffset: Float = 0.01
    private static let goodShoulderTwist: Float = 2
    private static let goodShoulderWidthRaw: Float = 0.2

    /// Returns a baseline derived from the "good" posture constants.
    static func baselineForGoodPosture() -> Baseline {
        Baseline(
            timestamp: Date(),
            shoulderMidpoint: goodShoulderMid,
            headPosition: goodHead,
            torsoAngle: goodTorsoAngle,
            shoulderTwist: goodShoulderTwist,
            shoulderWidth: goodShoulderWidthRaw,
            depthAvailable: false
        )
    }

    // MARK: - Sample Helpers

    private static func goodSample(
        timestamp: TimeInterval,
        depthMode: DepthMode = .twoDOnly
    ) -> PoseSample {
        PoseSample(
            timestamp: timestamp,
            depthMode: depthMode,
            headPosition: goodHead,
            shoulderMidpoint: goodShoulderMid,
            leftShoulder: goodLeftShoulder,
            rightShoulder: goodRightShoulder,
            torsoAngle: goodTorsoAngle,
            headForwardOffset: goodHeadForwardOffset,
            shoulderTwist: goodShoulderTwist,
            shoulderWidthRaw: goodShoulderWidthRaw,
            trackingQuality: .good
        )
    }

    /// Linearly interpolate between two floats.
    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    /// Linearly interpolate between two SIMD3 vectors.
    private static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    // MARK: - 1. Good Posture (sustained)

    /// 30 samples of sustained good posture at 0.1s intervals.
    /// All metrics stay within default thresholds.
    static func goodPosture() -> RecordedSession {
        let count = 30
        let interval: TimeInterval = 0.1
        let samples = (0..<count).map { i in
            goodSample(timestamp: Double(i) * interval)
        }
        return makeSession(samples: samples, depthAvailable: false)
    }

    // MARK: - 2. Gradual Slouch

    /// 50 samples: first 15 are good posture, then a gradual degradation over 20 samples,
    /// followed by 15 samples of sustained bad posture.
    /// Expected transitions: good → drifting → bad.
    static func gradualSlouch() -> RecordedSession {
        let interval: TimeInterval = 0.1
        var samples: [PoseSample] = []

        // Phase 1: Good posture (samples 0-14)
        for i in 0..<15 {
            samples.append(goodSample(timestamp: Double(i) * interval))
        }

        // Slouch targets: values that clearly exceed thresholds
        let badHead = SIMD3<Float>(0, 0.85, 0)          // headDrop = 0.15 > 0.06
        let badTorsoAngle: Float = 20                     // shoulderRounding = 15 > 10
        let badShoulderWidthRaw: Float = 0.24             // forwardCreep = 0.2 > 0.03
        let badShoulderTwist: Float = 20                  // twist = 18 > 15

        // Phase 2: Gradual degradation (samples 15-34)
        for i in 0..<20 {
            let t = Float(i) / 19.0  // 0.0 → 1.0
            let ts = Double(15 + i) * interval
            samples.append(PoseSample(
                timestamp: ts,
                depthMode: .twoDOnly,
                headPosition: lerp(goodHead, badHead, t),
                shoulderMidpoint: goodShoulderMid,
                leftShoulder: goodLeftShoulder,
                rightShoulder: goodRightShoulder,
                torsoAngle: lerp(goodTorsoAngle, badTorsoAngle, t),
                headForwardOffset: lerp(goodHeadForwardOffset, 0.08, t),
                shoulderTwist: lerp(goodShoulderTwist, badShoulderTwist, t),
                shoulderWidthRaw: lerp(goodShoulderWidthRaw, badShoulderWidthRaw, t),
                trackingQuality: .good
            ))
        }

        // Phase 3: Sustained bad posture (samples 35-49)
        for i in 0..<15 {
            let ts = Double(35 + i) * interval
            samples.append(PoseSample(
                timestamp: ts,
                depthMode: .twoDOnly,
                headPosition: badHead,
                shoulderMidpoint: goodShoulderMid,
                leftShoulder: goodLeftShoulder,
                rightShoulder: goodRightShoulder,
                torsoAngle: badTorsoAngle,
                headForwardOffset: 0.08,
                shoulderTwist: badShoulderTwist,
                shoulderWidthRaw: badShoulderWidthRaw,
                trackingQuality: .good
            ))
        }

        return makeSession(samples: samples, depthAvailable: false)
    }

    // MARK: - 3. Reading vs Typing

    /// 40 samples alternating between reading-like and typing-like postures.
    /// Reading: slight forward lean (within reading-mode relaxed thresholds).
    /// Typing: upright with slight twist (within thresholds).
    static func readingVsTyping() -> RecordedSession {
        let interval: TimeInterval = 0.1
        var samples: [PoseSample] = []

        for i in 0..<40 {
            let ts = Double(i) * interval
            let phase = i / 10  // 0, 1, 2, 3 — alternating blocks of 10

            if phase % 2 == 0 {
                // Reading posture: slight forward lean, head slightly lower
                // shoulderRounding = 11 - 5 = 6 (within 10.0 threshold)
                // forwardCreep = (0.206 - 0.2) / 0.2 = 0.03 (at threshold)
                // In reading mode with 1.2x multiplier: effective threshold = 0.036, so 0.03 is fine
                samples.append(PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: SIMD3<Float>(0, 0.97, 0),
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeftShoulder,
                    rightShoulder: goodRightShoulder,
                    torsoAngle: 8,
                    headForwardOffset: 0.03,
                    shoulderTwist: goodShoulderTwist,
                    shoulderWidthRaw: 0.205,
                    trackingQuality: .good
                ))
            } else {
                // Typing posture: upright, slight twist
                // twist = |5 - 2| = 3 (within 15.0 threshold)
                samples.append(PoseSample(
                    timestamp: ts,
                    depthMode: .twoDOnly,
                    headPosition: goodHead,
                    shoulderMidpoint: goodShoulderMid,
                    leftShoulder: goodLeftShoulder,
                    rightShoulder: goodRightShoulder,
                    torsoAngle: 6,
                    headForwardOffset: 0.01,
                    shoulderTwist: 5,
                    shoulderWidthRaw: goodShoulderWidthRaw,
                    trackingQuality: .good
                ))
            }
        }

        let tags = [
            Tag(timestamp: 0, label: .reading, source: .manual),
            Tag(timestamp: 1.0, label: .typing, source: .manual),
            Tag(timestamp: 2.0, label: .reading, source: .manual),
            Tag(timestamp: 3.0, label: .typing, source: .manual),
        ]

        return makeSession(samples: samples, tags: tags, depthAvailable: false)
    }

    // MARK: - 4. Depth Fallback

    /// 40 samples: first 20 use depthFusion, then 20 use twoDOnly (simulating depth loss).
    /// Both phases maintain good posture — the test verifies the mode switch doesn't
    /// cause a false posture degradation.
    static func depthFallback() -> RecordedSession {
        let interval: TimeInterval = 0.1
        var samples: [PoseSample] = []

        // Phase 1: Depth fusion available (samples 0-19)
        for i in 0..<20 {
            let ts = Double(i) * interval
            samples.append(PoseSample(
                timestamp: ts,
                depthMode: .depthFusion,
                headPosition: goodHead,
                shoulderMidpoint: goodShoulderMid,
                leftShoulder: goodLeftShoulder,
                rightShoulder: goodRightShoulder,
                torsoAngle: goodTorsoAngle,
                headForwardOffset: goodHeadForwardOffset,
                shoulderTwist: goodShoulderTwist,
                shoulderWidthRaw: goodShoulderWidthRaw,
                trackingQuality: .good
            ))
        }

        // Phase 2: Depth lost, fall back to 2D (samples 20-39)
        // Slight natural variation but still within thresholds
        for i in 0..<20 {
            let ts = Double(20 + i) * interval
            samples.append(PoseSample(
                timestamp: ts,
                depthMode: .twoDOnly,
                headPosition: SIMD3<Float>(0, 0.99, 0),
                shoulderMidpoint: SIMD3<Float>(0.01, 0, 0),
                leftShoulder: SIMD3<Float>(-0.49, 0, 0),
                rightShoulder: SIMD3<Float>(0.51, 0, 0),
                torsoAngle: 6,
                headForwardOffset: 0.015,
                shoulderTwist: 3,
                shoulderWidthRaw: 0.201,
                trackingQuality: .good
            ))
        }

        return makeSession(samples: samples, depthAvailable: true)
    }

    // MARK: - Session Factory

    private static func makeSession(
        samples: [PoseSample],
        tags: [Tag] = [],
        depthAvailable: Bool
    ) -> RecordedSession {
        let startTime = Date()
        let duration = samples.last.map { $0.timestamp - samples[0].timestamp } ?? 0
        return RecordedSession(
            id: UUID(),
            startTime: startTime,
            endTime: startTime.addingTimeInterval(duration),
            samples: samples,
            tags: tags,
            metadata: SessionMetadata(
                deviceModel: "GoldenTest",
                depthAvailable: depthAvailable,
                thresholds: PostureThresholds()
            )
        )
    }
}
