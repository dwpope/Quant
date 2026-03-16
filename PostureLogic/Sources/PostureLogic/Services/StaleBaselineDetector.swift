import Foundation

/// Result of checking whether the current baseline is still valid.
public enum StaleBaselineResult: Equatable {
    case fresh
    case positionShifted(percent: Float)
    case timeExpired(age: TimeInterval)
    case bothStale(percent: Float, age: TimeInterval)
}

/// Detects when the calibration baseline no longer matches the user's current position.
/// Checks for significant shoulder-width shift and time-based expiry.
public struct StaleBaselineDetector: DebugDumpable {

    public init() {}

    /// Check whether the baseline is stale relative to the current pose sample.
    ///
    /// - Parameters:
    ///   - current: The most recent pose sample from the camera.
    ///   - baseline: The calibration baseline to compare against.
    ///   - baselineAge: How long ago the baseline was captured, in seconds.
    /// - Returns: A `StaleBaselineResult` indicating freshness or staleness reason.
    public func check(current: PoseSample, baseline: Baseline, baselineAge: TimeInterval) -> StaleBaselineResult {
        let shiftPercent = abs(current.shoulderWidthRaw - baseline.shoulderWidth) / baseline.shoulderWidth
        let shifted = shiftPercent > 0.30
        let expired = baselineAge > 3600

        switch (shifted, expired) {
        case (true, true):
            return .bothStale(percent: shiftPercent, age: baselineAge)
        case (true, false):
            return .positionShifted(percent: shiftPercent)
        case (false, true):
            return .timeExpired(age: baselineAge)
        case (false, false):
            return .fresh
        }
    }

    // MARK: - DebugDumpable

    public var debugState: [String: Any] {
        ["type": "StaleBaselineDetector"]
    }
}
