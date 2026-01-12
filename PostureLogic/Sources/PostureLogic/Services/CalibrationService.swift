import Foundation
import simd

public enum CalibrationStatus {
    case waiting
    case sampling
    case validating
    case success
    case failed(String)
}

public struct CalibrationConfig {
    public let duration: TimeInterval
    public let requiredSamples: Int
    public let stabilityThreshold: Float

    public init(
        duration: TimeInterval = 5.0,
        requiredSamples: Int = 30,
        stabilityThreshold: Float = 0.02
    ) {
        self.duration = duration
        self.requiredSamples = requiredSamples
        self.stabilityThreshold = stabilityThreshold
    }
}

public final class CalibrationService {
    // MARK: - Public Properties

    public var status: CalibrationStatus = .waiting
    public var progress: Float = 0.0

    // MARK: - Private Properties

    private let config: CalibrationConfig
    private var collectedSamples: [PoseSample] = []
    private var startTime: TimeInterval?

    // MARK: - Initialization

    public init(config: CalibrationConfig = CalibrationConfig()) {
        self.config = config
    }

    // MARK: - Public Methods

    public func startCalibration() {
        status = .waiting
        progress = 0.0
        collectedSamples = []
        startTime = nil
    }

    public func addSample(_ sample: PoseSample) {
        // Only collect samples when we're ready
        guard status == .waiting || status == .sampling else { return }

        // Check tracking quality
        guard sample.trackingQuality == .good else {
            // Reset if tracking is poor
            if status == .sampling {
                status = .failed("Tracking quality too low. Please ensure you're visible in the camera.")
                collectedSamples = []
                startTime = nil
            }
            return
        }

        // Start timing if this is the first good sample
        if startTime == nil {
            startTime = sample.timestamp
            status = .sampling
        }

        // Add sample
        collectedSamples.append(sample)

        // Update progress
        let elapsed = sample.timestamp - (startTime ?? sample.timestamp)
        progress = min(1.0, Float(elapsed / config.duration))

        // Check if we've collected enough samples
        if elapsed >= config.duration {
            validateAndComplete()
        }
    }

    public func reset() {
        status = .waiting
        progress = 0.0
        collectedSamples = []
        startTime = nil
    }

    // MARK: - Private Methods

    private func validateAndComplete() {
        status = .validating

        // Check minimum sample count
        guard collectedSamples.count >= config.requiredSamples else {
            status = .failed("Not enough samples collected. Please try again and hold still.")
            collectedSamples = []
            startTime = nil
            return
        }

        // Validate stability (check variance in shoulder positions)
        let stability = computeStability(samples: collectedSamples)
        guard stability <= config.stabilityThreshold else {
            status = .failed("Too much movement detected. Please hold still during calibration.")
            collectedSamples = []
            startTime = nil
            return
        }

        status = .success
        progress = 1.0
    }

    public func computeBaseline() -> Baseline? {
        guard status == .success, !collectedSamples.isEmpty else {
            return nil
        }

        // Compute median values for each property
        let shoulderMidpoint = computeMedianPosition(samples: collectedSamples.map { $0.shoulderMidpoint })
        let headPosition = computeMedianPosition(samples: collectedSamples.map { $0.headPosition })
        let torsoAngle = computeMedianFloat(values: collectedSamples.map { $0.torsoAngle })

        // Compute shoulder width as median distance between shoulders
        let shoulderWidths = collectedSamples.map { sample in
            distance(sample.leftShoulder, sample.rightShoulder)
        }
        let shoulderWidth = computeMedianFloat(values: shoulderWidths)

        // Check if depth was available in most samples
        let depthSamples = collectedSamples.filter { $0.depthMode == .depthFusion }.count
        let depthAvailable = Float(depthSamples) / Float(collectedSamples.count) > 0.5

        return Baseline(
            timestamp: Date(),
            shoulderMidpoint: shoulderMidpoint,
            headPosition: headPosition,
            torsoAngle: torsoAngle,
            shoulderWidth: shoulderWidth,
            depthAvailable: depthAvailable
        )
    }

    // MARK: - Helper Methods

    private func computeStability(samples: [PoseSample]) -> Float {
        guard !samples.isEmpty else { return Float.infinity }

        // Compute variance of shoulder midpoint positions
        let positions = samples.map { $0.shoulderMidpoint }
        let mean = computeMeanPosition(positions: positions)

        let variance = positions.reduce(Float(0)) { sum, pos in
            let diff = pos - mean
            let distanceSquared = dot(diff, diff)
            return sum + distanceSquared
        } / Float(positions.count)

        // Return standard deviation
        return sqrt(variance)
    }

    private func computeMeanPosition(positions: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !positions.isEmpty else { return .zero }

        let sum = positions.reduce(SIMD3<Float>.zero) { $0 + $1 }
        return sum / Float(positions.count)
    }

    private func computeMedianPosition(samples: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !samples.isEmpty else { return .zero }

        let sortedX = samples.map { $0.x }.sorted()
        let sortedY = samples.map { $0.y }.sorted()
        let sortedZ = samples.map { $0.z }.sorted()

        let midIndex = samples.count / 2

        return SIMD3<Float>(
            x: sortedX[midIndex],
            y: sortedY[midIndex],
            z: sortedZ[midIndex]
        )
    }

    private func computeMedianFloat(values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let midIndex = sorted.count / 2

        return sorted[midIndex]
    }
}
