import Foundation
import simd

/// Utility to generate synthetic golden recordings for testing
public struct GoldenRecordingGenerator {

    // MARK: - Good Posture (5 minutes)

    /// Generates 5 minutes of sustained good posture
    /// - Sampling at 10 FPS = 3000 samples
    /// - Minimal variation around baseline
    /// - High tracking quality throughout
    public static func generateGoodPosture5Min() -> RecordedSession {
        let startTime = Date(timeIntervalSince1970: 1704067200) // Jan 1, 2024 00:00:00
        let duration: TimeInterval = 300 // 5 minutes
        let fps = 10.0
        let sampleCount = Int(duration * fps)

        var samples: [PoseSample] = []
        var tags: [Tag] = []

        // Baseline good posture position
        let baselineHead = SIMD3<Float>(0.0, 0.15, 0.88)
        let baselineShoulder = SIMD3<Float>(0.0, 0.0, 0.90)
        let baselineLeftShoulder = SIMD3<Float>(-0.18, 0.0, 0.90)
        let baselineRightShoulder = SIMD3<Float>(0.18, 0.0, 0.90)

        // Add initial tag
        tags.append(Tag(timestamp: startTime.timeIntervalSince1970, label: .goodPosture, source: .automatic))

        for i in 0..<sampleCount {
            let timestamp = startTime.timeIntervalSince1970 + Double(i) / fps

            // Add subtle random variation (breathing, micro-movements)
            let noise = Float.random(in: -0.005...0.005)
            let breathingOffset = sin(Float(i) * 0.1) * 0.003 // Breathing cycle

            let sample = PoseSample(
                timestamp: timestamp,
                depthMode: .depthFusion,
                headPosition: baselineHead + SIMD3<Float>(noise, breathingOffset, noise),
                shoulderMidpoint: baselineShoulder + SIMD3<Float>(noise * 0.5, breathingOffset, noise * 0.5),
                leftShoulder: baselineLeftShoulder + SIMD3<Float>(noise, breathingOffset, noise),
                rightShoulder: baselineRightShoulder + SIMD3<Float>(noise, breathingOffset, noise),
                torsoAngle: 2.0 + noise * 5,
                headForwardOffset: 0.02 + noise * 0.01,
                shoulderTwist: 0.0 + noise * 2,
                trackingQuality: .good
            )
            samples.append(sample)
        }

        // Add mid-point tag
        tags.append(Tag(
            timestamp: startTime.timeIntervalSince1970 + 150,
            label: .goodPosture,
            source: .manual
        ))

        let endTime = startTime.addingTimeInterval(duration)

        return RecordedSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startTime: startTime,
            endTime: endTime,
            samples: samples,
            tags: tags,
            metadata: SessionMetadata(
                deviceModel: "iPhone15,3",
                depthAvailable: true,
                thresholds: PostureThresholds()
            )
        )
    }

    // MARK: - Gradual Slouch (10 minutes)

    /// Generates 10 minutes starting with good posture, gradually deteriorating
    /// - First 2 minutes: Good posture
    /// - Minutes 2-6: Gradual forward creep
    /// - Minutes 6-10: Sustained bad posture with head drop
    public static func generateGradualSlouch() -> RecordedSession {
        let startTime = Date(timeIntervalSince1970: 1704070800) // Jan 1, 2024 01:00:00
        let duration: TimeInterval = 600 // 10 minutes
        let fps = 10.0
        let sampleCount = Int(duration * fps)

        var samples: [PoseSample] = []
        var tags: [Tag] = []

        // Baseline positions
        let baselineHead = SIMD3<Float>(0.0, 0.15, 0.88)
        let baselineShoulder = SIMD3<Float>(0.0, 0.0, 0.90)
        let baselineLeftShoulder = SIMD3<Float>(-0.18, 0.0, 0.90)
        let baselineRightShoulder = SIMD3<Float>(0.18, 0.0, 0.90)

        // End positions (slouched)
        let slouchedHead = SIMD3<Float>(0.0, 0.10, 0.75) // Lower, closer
        let slouchedShoulder = SIMD3<Float>(0.0, -0.02, 0.82) // Lower, closer
        let slouchedLeftShoulder = SIMD3<Float>(-0.18, -0.02, 0.82)
        let slouchedRightShoulder = SIMD3<Float>(0.18, -0.02, 0.82)

        tags.append(Tag(timestamp: startTime.timeIntervalSince1970, label: .goodPosture, source: .automatic))

        for i in 0..<sampleCount {
            let timestamp = startTime.timeIntervalSince1970 + Double(i) / fps
            let elapsedMinutes = Double(i) / (fps * 60)

            // Calculate interpolation factor based on time
            var t: Float = 0.0
            if elapsedMinutes < 2.0 {
                // First 2 minutes: good posture
                t = 0.0
                if i % 600 == 0 { // Every minute
                    tags.append(Tag(timestamp: timestamp, label: .goodPosture, source: .automatic))
                }
            } else if elapsedMinutes < 6.0 {
                // Minutes 2-6: gradual transition
                t = Float((elapsedMinutes - 2.0) / 4.0)
                if i == Int(2 * 60 * fps) {
                    tags.append(Tag(timestamp: timestamp, label: .slouching, source: .voice))
                }
            } else {
                // Minutes 6-10: sustained bad posture
                t = 1.0
                if i == Int(6 * 60 * fps) {
                    tags.append(Tag(timestamp: timestamp, label: .slouching, source: .automatic))
                }
            }

            // Smooth interpolation with noise
            let noise = Float.random(in: -0.005...0.005)
            let breathingOffset = sin(Float(i) * 0.1) * 0.003

            let currentHead = mix(baselineHead, slouchedHead, t: t)
            let currentShoulder = mix(baselineShoulder, slouchedShoulder, t: t)
            let currentLeftShoulder = mix(baselineLeftShoulder, slouchedLeftShoulder, t: t)
            let currentRightShoulder = mix(baselineRightShoulder, slouchedRightShoulder, t: t)

            let sample = PoseSample(
                timestamp: timestamp,
                depthMode: .depthFusion,
                headPosition: currentHead + SIMD3<Float>(noise, breathingOffset, noise),
                shoulderMidpoint: currentShoulder + SIMD3<Float>(noise * 0.5, breathingOffset, noise * 0.5),
                leftShoulder: currentLeftShoulder + SIMD3<Float>(noise, breathingOffset, noise),
                rightShoulder: currentRightShoulder + SIMD3<Float>(noise, breathingOffset, noise),
                torsoAngle: 2.0 + t * 13.0 + noise * 5, // 2° to 15°
                headForwardOffset: 0.02 + t * 0.08, // 2cm to 10cm
                shoulderTwist: 0.0 + noise * 2,
                trackingQuality: .good
            )
            samples.append(sample)
        }

        let endTime = startTime.addingTimeInterval(duration)

        return RecordedSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            startTime: startTime,
            endTime: endTime,
            samples: samples,
            tags: tags,
            metadata: SessionMetadata(
                deviceModel: "iPhone15,3",
                depthAvailable: true,
                thresholds: PostureThresholds()
            )
        )
    }

    // MARK: - Reading vs Typing (8 minutes)

    /// Generates alternating reading and typing segments
    /// - Minute 0-2: Reading (still, small movements)
    /// - Minute 2-4: Typing (more movement, slight forward lean)
    /// - Minute 4-6: Reading again
    /// - Minute 6-8: Typing again
    public static func generateReadingVsTyping() -> RecordedSession {
        let startTime = Date(timeIntervalSince1970: 1704074400) // Jan 1, 2024 02:00:00
        let duration: TimeInterval = 480 // 8 minutes
        let fps = 10.0
        let sampleCount = Int(duration * fps)

        var samples: [PoseSample] = []
        var tags: [Tag] = []

        let baselineHead = SIMD3<Float>(0.0, 0.15, 0.88)
        let baselineShoulder = SIMD3<Float>(0.0, 0.0, 0.90)
        let baselineLeftShoulder = SIMD3<Float>(-0.18, 0.0, 0.90)
        let baselineRightShoulder = SIMD3<Float>(0.18, 0.0, 0.90)

        // Typing: slightly forward
        let typingHead = SIMD3<Float>(0.0, 0.14, 0.85)
        let typingShoulder = SIMD3<Float>(0.0, -0.01, 0.87)

        for i in 0..<sampleCount {
            let timestamp = startTime.timeIntervalSince1970 + Double(i) / fps
            let elapsedMinutes = Double(i) / (fps * 60)

            let isReading = (elapsedMinutes >= 0 && elapsedMinutes < 2) || (elapsedMinutes >= 4 && elapsedMinutes < 6)
            let isTyping = (elapsedMinutes >= 2 && elapsedMinutes < 4) || (elapsedMinutes >= 6 && elapsedMinutes < 8)

            // Tag mode changes
            if i == 0 {
                tags.append(Tag(timestamp: timestamp, label: .reading, source: .automatic))
            } else if i == Int(2 * 60 * fps) {
                tags.append(Tag(timestamp: timestamp, label: .typing, source: .voice))
            } else if i == Int(4 * 60 * fps) {
                tags.append(Tag(timestamp: timestamp, label: .reading, source: .voice))
            } else if i == Int(6 * 60 * fps) {
                tags.append(Tag(timestamp: timestamp, label: .typing, source: .manual))
            }

            var headPos = baselineHead
            var shoulderPos = baselineShoulder
            var movement: Float = 0.002

            if isReading {
                // Reading: minimal movement, small head oscillations
                let readingNoise = sin(Float(i) * 0.05) * 0.008
                headPos = baselineHead + SIMD3<Float>(readingNoise, readingNoise * 0.5, 0)
                shoulderPos = baselineShoulder
                movement = 0.002
            } else if isTyping {
                // Typing: more movement, slight forward lean
                let typingNoise = Float.random(in: -0.015...0.015)
                headPos = typingHead + SIMD3<Float>(typingNoise, typingNoise * 0.3, typingNoise * 0.5)
                shoulderPos = typingShoulder + SIMD3<Float>(typingNoise * 0.3, 0, typingNoise * 0.3)
                movement = 0.015
            }

            let sample = PoseSample(
                timestamp: timestamp,
                depthMode: .depthFusion,
                headPosition: headPos,
                shoulderMidpoint: shoulderPos,
                leftShoulder: baselineLeftShoulder + SIMD3<Float>(Float.random(in: -movement...movement), 0, 0),
                rightShoulder: baselineRightShoulder + SIMD3<Float>(Float.random(in: -movement...movement), 0, 0),
                torsoAngle: isTyping ? 5.0 : 2.0,
                headForwardOffset: isTyping ? 0.05 : 0.02,
                shoulderTwist: Float.random(in: -3...3),
                trackingQuality: .good
            )
            samples.append(sample)
        }

        let endTime = startTime.addingTimeInterval(duration)

        return RecordedSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            startTime: startTime,
            endTime: endTime,
            samples: samples,
            tags: tags,
            metadata: SessionMetadata(
                deviceModel: "iPhone15,3",
                depthAvailable: true,
                thresholds: PostureThresholds()
            )
        )
    }

    // MARK: - Depth Fallback Scenario (6 minutes)

    /// Generates a session where depth is intermittently lost
    /// - Starts with depth available
    /// - Loses depth at 1 min, 3 min (switches to 2D mode)
    /// - Recovers depth at 2 min, 4 min
    /// - Tests mode switching and 2D fallback
    public static func generateDepthFallback() -> RecordedSession {
        let startTime = Date(timeIntervalSince1970: 1704078000) // Jan 1, 2024 03:00:00
        let duration: TimeInterval = 360 // 6 minutes
        let fps = 10.0
        let sampleCount = Int(duration * fps)

        var samples: [PoseSample] = []
        var tags: [Tag] = []

        let baselineHead = SIMD3<Float>(0.0, 0.15, 0.88)
        let baselineShoulder = SIMD3<Float>(0.0, 0.0, 0.90)
        let baselineLeftShoulder = SIMD3<Float>(-0.18, 0.0, 0.90)
        let baselineRightShoulder = SIMD3<Float>(0.18, 0.0, 0.90)

        for i in 0..<sampleCount {
            let timestamp = startTime.timeIntervalSince1970 + Double(i) / fps
            let elapsedSeconds = Double(i) / fps

            // Determine depth availability based on time windows
            let depthMode: DepthMode
            let trackingQuality: TrackingQuality

            if (elapsedSeconds >= 60 && elapsedSeconds < 120) || (elapsedSeconds >= 180 && elapsedSeconds < 240) {
                // Depth lost periods
                depthMode = .twoDOnly
                trackingQuality = .degraded

                if i == Int(60 * fps) || i == Int(180 * fps) {
                    tags.append(Tag(timestamp: timestamp, label: .goodPosture, source: .automatic))
                }
            } else {
                // Depth available
                depthMode = .depthFusion
                trackingQuality = .good

                if i == 0 || i == Int(120 * fps) || i == Int(240 * fps) {
                    tags.append(Tag(timestamp: timestamp, label: .goodPosture, source: .automatic))
                }
            }

            let noise = Float.random(in: -0.005...0.005)
            let breathingOffset = sin(Float(i) * 0.1) * 0.003

            let sample = PoseSample(
                timestamp: timestamp,
                depthMode: depthMode,
                headPosition: baselineHead + SIMD3<Float>(noise, breathingOffset, noise),
                shoulderMidpoint: baselineShoulder + SIMD3<Float>(noise * 0.5, breathingOffset, noise * 0.5),
                leftShoulder: baselineLeftShoulder + SIMD3<Float>(noise, breathingOffset, noise),
                rightShoulder: baselineRightShoulder + SIMD3<Float>(noise, breathingOffset, noise),
                torsoAngle: 2.0 + noise * 5,
                headForwardOffset: 0.02 + noise * 0.01,
                shoulderTwist: 0.0 + noise * 2,
                trackingQuality: trackingQuality
            )
            samples.append(sample)
        }

        let endTime = startTime.addingTimeInterval(duration)

        return RecordedSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            startTime: startTime,
            endTime: endTime,
            samples: samples,
            tags: tags,
            metadata: SessionMetadata(
                deviceModel: "iPhone14,7",
                depthAvailable: false, // Non-LiDAR device
                thresholds: PostureThresholds()
            )
        )
    }

    // MARK: - Helper Functions

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }

    // MARK: - File Writing

    /// Writes a RecordedSession to a JSON file
    public static func writeToFile(_ session: RecordedSession, filename: String, directory: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(session)

        let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(filename)
        try data.write(to: fileURL)

        print("✅ Written \(filename) (\(data.count / 1024)KB) to \(directory)")
    }

    /// Generates all four golden recordings and writes them to the specified directory
    public static func generateAll(to directory: String) throws {
        print("🎬 Generating golden recordings...")

        let recordings: [(session: RecordedSession, filename: String)] = [
            (generateGoodPosture5Min(), "good_posture_5min.json"),
            (generateGradualSlouch(), "gradual_slouch.json"),
            (generateReadingVsTyping(), "reading_vs_typing.json"),
            (generateDepthFallback(), "depth_fallback_scenario.json")
        ]

        for (session, filename) in recordings {
            try writeToFile(session, filename: filename, directory: directory)
        }

        print("✨ All golden recordings generated successfully!")
    }
}
