import Foundation
import PostureLogic

/// Pure-value snapshot of posture session statistics derived from pose samples.
///
/// All computation happens in `init` — no stored closures, no side effects.
/// Takes an array of `PoseSample` (the same type the Pipeline produces each
/// frame) and computes tracking quality breakdown, depth mode distribution,
/// and summary statistics for geometric posture metrics.
///
/// Usage:
/// ```swift
/// let summary = PostureSessionSummary(samples: session.samples)
/// print(summary.sampleCount)            // 1200
/// print(summary.sessionDuration)        // 3600.0 (seconds)
/// print(summary.goodTrackingPercent)    // 92.5
/// print(summary.averageHeadForward)     // 0.024
/// ```
struct PostureSessionSummary: Equatable {

    // MARK: - Session Overview

    /// Total number of pose samples in the session.
    let sampleCount: Int

    /// Duration from first to last sample (seconds), or `nil` if fewer
    /// than two samples.
    let sessionDuration: TimeInterval?

    /// Timestamp of the first sample, or `nil` if empty.
    let firstTimestamp: TimeInterval?

    /// Timestamp of the last sample, or `nil` if empty.
    let lastTimestamp: TimeInterval?

    // MARK: - Tracking Quality Breakdown

    /// Number of samples with `.good` tracking quality.
    let goodTrackingCount: Int

    /// Number of samples with `.degraded` tracking quality.
    let degradedTrackingCount: Int

    /// Number of samples with `.lost` tracking quality.
    let lostTrackingCount: Int

    /// Percentage of samples with `.good` tracking (0–100), or `nil` if
    /// no samples.
    let goodTrackingPercent: Float?

    // MARK: - Depth Mode Breakdown

    /// Number of samples using depth fusion (LiDAR).
    let depthFusionCount: Int

    /// Number of samples using 2D-only mode.
    let twoDOnlyCount: Int

    /// Percentage of samples using depth fusion (0–100), or `nil` if no
    /// samples.
    let depthFusionPercent: Float?

    // MARK: - Geometric Metric Summaries
    //
    // Computed only from samples with `.good` tracking quality, since
    // degraded/lost samples have unreliable geometry.

    /// Number of good-tracking samples used for metric stats.
    let goodSampleCount: Int

    /// Average head-forward offset across good-tracking samples, or `nil`
    /// if no good samples.
    let averageHeadForward: Float?

    /// Peak (maximum) head-forward offset, or `nil` if no good samples.
    let peakHeadForward: Float?

    /// Average torso angle (shoulder rounding signal) across good-tracking
    /// samples, or `nil` if no good samples.
    let averageTorsoAngle: Float?

    /// Peak torso angle, or `nil` if no good samples.
    let peakTorsoAngle: Float?

    /// Average shoulder twist across good-tracking samples, or `nil` if
    /// no good samples.
    let averageShoulderTwist: Float?

    /// Peak shoulder twist, or `nil` if no good samples.
    let peakShoulderTwist: Float?

    // MARK: - Initialization

    /// Computes session summary from an array of pose samples.
    ///
    /// - Parameter samples: The session's pose samples (need not be pre-sorted).
    init(samples: [PoseSample]) {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }

        self.sampleCount = sorted.count
        self.firstTimestamp = sorted.first?.timestamp
        self.lastTimestamp = sorted.last?.timestamp

        // Session duration
        if let first = sorted.first?.timestamp,
           let last = sorted.last?.timestamp, sorted.count >= 2 {
            self.sessionDuration = last - first
        } else {
            self.sessionDuration = nil
        }

        // Tracking quality breakdown
        var good = 0, degraded = 0, lost = 0
        for sample in sorted {
            switch sample.trackingQuality {
            case .good: good += 1
            case .degraded: degraded += 1
            case .lost: lost += 1
            }
        }
        self.goodTrackingCount = good
        self.degradedTrackingCount = degraded
        self.lostTrackingCount = lost
        self.goodTrackingPercent = sorted.isEmpty ? nil : Float(good) / Float(sorted.count) * 100

        // Depth mode breakdown
        var depthFusion = 0, twoDOnly = 0
        for sample in sorted {
            switch sample.depthMode {
            case .depthFusion: depthFusion += 1
            case .twoDOnly: twoDOnly += 1
            }
        }
        self.depthFusionCount = depthFusion
        self.twoDOnlyCount = twoDOnly
        self.depthFusionPercent = sorted.isEmpty ? nil : Float(depthFusion) / Float(sorted.count) * 100

        // Geometric metrics — only from good-tracking samples
        let goodSamples = sorted.filter { $0.trackingQuality == .good }
        self.goodSampleCount = goodSamples.count

        if goodSamples.isEmpty {
            self.averageHeadForward = nil
            self.peakHeadForward = nil
            self.averageTorsoAngle = nil
            self.peakTorsoAngle = nil
            self.averageShoulderTwist = nil
            self.peakShoulderTwist = nil
        } else {
            let headForwards = goodSamples.map { abs($0.headForwardOffset) }
            let torsoAngles = goodSamples.map { abs($0.torsoAngle) }
            let twists = goodSamples.map { abs($0.shoulderTwist) }

            self.averageHeadForward = headForwards.reduce(0, +) / Float(headForwards.count)
            self.peakHeadForward = headForwards.max()

            self.averageTorsoAngle = torsoAngles.reduce(0, +) / Float(torsoAngles.count)
            self.peakTorsoAngle = torsoAngles.max()

            self.averageShoulderTwist = twists.reduce(0, +) / Float(twists.count)
            self.peakShoulderTwist = twists.max()
        }
    }

    // MARK: - Convenience

    /// A plain-English description of the session duration, e.g. "1 hr 23 min".
    /// Returns `nil` if no duration is available.
    var durationDescription: String? {
        guard let duration = sessionDuration else { return nil }
        let totalMinutes = Int(duration / 60)
        if totalMinutes < 1 { return "<1 min" }
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        if remainingMinutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainingMinutes) min"
    }

    /// A plain-English summary of tracking quality, e.g. "92% good tracking".
    /// Returns `nil` if no samples.
    var trackingQualityDescription: String? {
        guard let percent = goodTrackingPercent else { return nil }
        return "\(Int(percent))% good tracking"
    }
}
