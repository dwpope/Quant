import Foundation
import simd

public struct CalibrationConfig {
    public let requiredSamples: Int
    public let samplingDuration: TimeInterval
    public let maxPositionVariance: Float
    public let maxAngleVariance: Float
    public let minTrackingQuality: TrackingQuality

    public init(
        requiredSamples: Int = 30,
        samplingDuration: TimeInterval = 5.0,
        maxPositionVariance: Float = 0.02,
        maxAngleVariance: Float = 3.0,
        minTrackingQuality: TrackingQuality = .good
    ) {
        self.requiredSamples = requiredSamples
        self.samplingDuration = samplingDuration
        self.maxPositionVariance = maxPositionVariance
        self.maxAngleVariance = maxAngleVariance
        self.minTrackingQuality = minTrackingQuality
    }
}

public final class CalibrationEngine {
    private let config: CalibrationConfig
    private var collectedSamples: [PoseSample] = []
    private var startTime: TimeInterval?

    public private(set) var status: CalibrationStatus = .waiting

    public init(config: CalibrationConfig = CalibrationConfig()) {
        self.config = config
    }

    /// Call this each time a new PoseSample arrives during calibration.
    /// Returns the current status after processing.
    public func addSample(_ sample: PoseSample) -> CalibrationStatus {
        switch status {
        case .success, .failed, .countdown:
            return status

        case .waiting:
            guard sample.trackingQuality >= config.minTrackingQuality else {
                return status
            }
            startTime = sample.timestamp
            collectedSamples = [sample]
            status = .sampling
            return status

        case .sampling, .validating:
            guard sample.trackingQuality >= config.minTrackingQuality else {
                status = .failed("Tracking quality dropped during calibration")
                return status
            }

            collectedSamples.append(sample)

            guard let start = startTime else {
                status = .failed("Internal error: no start time")
                return status
            }

            let elapsed = sample.timestamp - start
            if elapsed >= config.samplingDuration && collectedSamples.count >= config.requiredSamples {
                status = .validating
                return validate()
            }

            return status
        }
    }

    public var progress: Float {
        guard let start = startTime, let last = collectedSamples.last else { return 0 }
        let elapsed = last.timestamp - start
        return min(1.0, Float(elapsed / config.samplingDuration))
    }

    public func reset() {
        collectedSamples = []
        startTime = nil
        status = .waiting
        resultBaseline = nil
    }

    // MARK: - Validation

    private func validate() -> CalibrationStatus {
        guard collectedSamples.count >= config.requiredSamples else {
            status = .failed("Not enough samples collected")
            return status
        }

        // Compute variance of key positions
        let shoulderMidpoints = collectedSamples.map { $0.shoulderMidpoint }
        let headPositions = collectedSamples.map { $0.headPosition }
        let torsoAngles = collectedSamples.map { $0.torsoAngle }

        let shoulderVariance = positionalVariance(shoulderMidpoints)
        let headVariance = positionalVariance(headPositions)
        let angleVariance = scalarVariance(torsoAngles)

        let maxPosVariance = max(shoulderVariance, headVariance)

        if maxPosVariance > config.maxPositionVariance {
            status = .failed("Too much movement detected — hold still and try again")
            return status
        }

        if angleVariance > config.maxAngleVariance {
            status = .failed("Torso angle varied too much — sit upright and hold still")
            return status
        }

        // Build baseline from averaged samples
        let baseline = buildBaseline()
        self.resultBaseline = baseline
        status = .success
        return status
    }

    /// The validated baseline, available after status becomes `.success`.
    public private(set) var resultBaseline: Baseline?

    private func buildBaseline() -> Baseline {
        let count = Float(collectedSamples.count)

        let avgShoulderMidpoint = collectedSamples
            .map { $0.shoulderMidpoint }
            .reduce(SIMD3<Float>.zero, +) / count

        let avgHeadPosition = collectedSamples
            .map { $0.headPosition }
            .reduce(SIMD3<Float>.zero, +) / count

        let avgTorsoAngle = collectedSamples
            .map { $0.torsoAngle }
            .reduce(Float(0), +) / count

        let avgShoulderWidth = collectedSamples
            .map { $0.shoulderWidthRaw }
            .reduce(Float(0), +) / count

        let hasDepth = collectedSamples.contains { $0.depthMode == .depthFusion }

        return Baseline(
            timestamp: Date(),
            shoulderMidpoint: avgShoulderMidpoint,
            headPosition: avgHeadPosition,
            torsoAngle: avgTorsoAngle,
            shoulderWidth: avgShoulderWidth,
            depthAvailable: hasDepth
        )
    }

    // MARK: - Variance Helpers

    private func positionalVariance(_ positions: [SIMD3<Float>]) -> Float {
        guard positions.count > 1 else { return 0 }
        let count = Float(positions.count)
        let mean = positions.reduce(SIMD3<Float>.zero, +) / count
        let sumSquaredDiffs = positions.reduce(Float(0)) { acc, pos in
            let diff = pos - mean
            return acc + simd_dot(diff, diff)
        }
        return sqrt(sumSquaredDiffs / count)
    }

    private func scalarVariance(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let count = Float(values.count)
        let mean = values.reduce(0, +) / count
        let sumSquaredDiffs = values.reduce(Float(0)) { acc, v in
            let diff = v - mean
            return acc + diff * diff
        }
        return sqrt(sumSquaredDiffs / count)
    }
}
