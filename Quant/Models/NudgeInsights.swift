import Foundation
import PostureLogic

/// Pure-value snapshot of nudge effectiveness statistics derived from recorded
/// nudge events.
///
/// All computation happens in `init` — no stored closures, no side effects.
/// Takes an array of `NudgeEvent` (written each time a nudge fires) and
/// computes acknowledgement rates, response times, reason breakdowns, and
/// temporal patterns.
///
/// Usage:
/// ```swift
/// let insights = NudgeInsights(events: store.nudgeEvents)
/// print(insights.totalCount)            // 8
/// print(insights.acknowledgementRate)   // 75.0
/// print(insights.averageResponseTime)   // 14.2 (seconds)
/// print(insights.dominantReason)        // .sustainedSlouch
/// ```
struct NudgeInsights: Equatable {

    // MARK: - Core Counts

    /// Total nudge events recorded.
    let totalCount: Int

    /// Nudges the user acknowledged (corrected posture after).
    let acknowledgedCount: Int

    /// Nudges the user ignored (did not correct).
    let ignoredCount: Int

    /// Percentage of nudges acknowledged (0–100), or `nil` if no events.
    let acknowledgementRate: Float?

    // MARK: - Response Time Stats

    /// Average time (seconds) from nudge to posture correction, or `nil`
    /// if no acknowledged nudges.
    let averageResponseTime: TimeInterval?

    /// Fastest response time (seconds), or `nil` if none acknowledged.
    let fastestResponse: TimeInterval?

    /// Slowest response time (seconds), or `nil` if none acknowledged.
    let slowestResponse: TimeInterval?

    /// Median response time (seconds), or `nil` if none acknowledged.
    let medianResponse: TimeInterval?

    /// Population standard deviation of response times (seconds), or
    /// `nil` if fewer than two acknowledged nudges. A single response
    /// has no measurable spread.
    let responseTimeStandardDeviation: TimeInterval?

    // MARK: - Reason Breakdown

    /// Number of nudges fired for sustained slouch.
    let sustainedSlouchCount: Int

    /// Number of nudges fired for forward creep.
    let forwardCreepCount: Int

    /// Number of nudges fired for head drop.
    let headDropCount: Int

    /// The most common nudge reason, or `nil` if no events.
    let dominantReason: NudgeReason?

    // MARK: - Temporal Patterns

    /// Duration from first to last nudge event (seconds), or `nil` if
    /// fewer than two events.
    let activeDuration: TimeInterval?

    /// Timestamp of the first nudge, or `nil` if no events.
    let firstTimestamp: TimeInterval?

    /// Timestamp of the most recent nudge, or `nil` if no events.
    let lastTimestamp: TimeInterval?

    /// Average time between consecutive nudges (seconds), or `nil` if
    /// fewer than two events.
    let averageInterval: TimeInterval?

    /// Population standard deviation of inter-nudge gaps (seconds), or
    /// `nil` if fewer than two gaps (i.e. fewer than three events). A
    /// single gap has no measurable spread, so we return `nil` rather
    /// than `0` — `0` would falsely imply "perfectly regular cadence."
    let intervalStandardDeviation: TimeInterval?

    /// A 0.0–1.0 score capturing how regular the nudge cadence is, or
    /// `nil` if fewer than three events. Computed as `1 - CV` (where
    /// CV is the coefficient of variation, `stddev / mean`), clamped
    /// to `[0, 1]`. `1.0` means perfectly even gaps; `0.0` means very
    /// erratic.
    let intervalRegularityScore: Double?

    /// Number of nudges in each hour (0–23). Always has 24 entries.
    let hourlyDistribution: [Int]

    /// The hour (0–23) with the most nudges, or `nil` if no events.
    let peakHour: Int?

    // MARK: - Initialization

    /// Computes insights from an array of nudge events.
    ///
    /// - Parameters:
    ///   - events: Recorded nudge events (need not be pre-sorted).
    ///   - calendar: Calendar for hour extraction. Defaults to `.current`.
    init(events: [NudgeEvent], calendar: Calendar = .current) {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }

        self.totalCount = sorted.count
        self.firstTimestamp = sorted.first?.timestamp
        self.lastTimestamp = sorted.last?.timestamp

        // Acknowledged vs ignored
        let acked = sorted.filter { $0.acknowledged }
        self.acknowledgedCount = acked.count
        self.ignoredCount = sorted.count - acked.count
        self.acknowledgementRate = sorted.isEmpty
            ? nil
            : Float(acked.count) / Float(sorted.count) * 100

        // Response time stats — only from acknowledged nudges
        let responseTimes = acked.compactMap { $0.responseTime }
        if responseTimes.isEmpty {
            self.averageResponseTime = nil
            self.fastestResponse = nil
            self.slowestResponse = nil
            self.medianResponse = nil
            self.responseTimeStandardDeviation = nil
        } else {
            let mean = responseTimes.reduce(0, +) / Double(responseTimes.count)
            self.averageResponseTime = mean
            self.fastestResponse = responseTimes.min()
            self.slowestResponse = responseTimes.max()
            let sortedTimes = responseTimes.sorted()
            let mid = sortedTimes.count / 2
            if sortedTimes.count.isMultiple(of: 2) {
                self.medianResponse = (sortedTimes[mid - 1] + sortedTimes[mid]) / 2.0
            } else {
                self.medianResponse = sortedTimes[mid]
            }

            // Standard deviation requires ≥ 2 response times for
            // variability to be meaningful.
            if responseTimes.count >= 2 {
                let squaredDeviations = responseTimes.map { ($0 - mean) * ($0 - mean) }
                let variance = squaredDeviations.reduce(0, +) / Double(responseTimes.count)
                self.responseTimeStandardDeviation = variance.squareRoot()
            } else {
                self.responseTimeStandardDeviation = nil
            }
        }

        // Reason breakdown
        var slouch = 0, creep = 0, drop = 0
        for event in sorted {
            switch event.reason {
            case .sustainedSlouch: slouch += 1
            case .forwardCreep: creep += 1
            case .headDrop: drop += 1
            }
        }
        self.sustainedSlouchCount = slouch
        self.forwardCreepCount = creep
        self.headDropCount = drop

        // Dominant reason — the one with the highest count
        if sorted.isEmpty {
            self.dominantReason = nil
        } else {
            let counts: [(NudgeReason, Int)] = [
                (.sustainedSlouch, slouch),
                (.forwardCreep, creep),
                (.headDrop, drop),
            ]
            self.dominantReason = counts.max(by: { $0.1 < $1.1 })?.0
        }

        // Active duration
        if let first = sorted.first?.timestamp,
           let last = sorted.last?.timestamp, sorted.count >= 2 {
            self.activeDuration = last - first
        } else {
            self.activeDuration = nil
        }

        // Average interval between consecutive nudges
        if sorted.count >= 2 {
            let gaps = zip(sorted.dropLast(), sorted.dropFirst()).map {
                $1.timestamp - $0.timestamp
            }
            let mean = gaps.reduce(0, +) / Double(gaps.count)
            self.averageInterval = mean

            // Spread + regularity require ≥ 2 gaps for variability to be
            // meaningful. A single gap has stddev 0 by convention, but
            // that would falsely report "perfect regularity" from one
            // data point.
            if gaps.count >= 2 {
                let squaredDeviations = gaps.map { ($0 - mean) * ($0 - mean) }
                let variance = squaredDeviations.reduce(0, +) / Double(gaps.count)
                let stddev = variance.squareRoot()
                self.intervalStandardDeviation = stddev
                if mean > 0 {
                    let cv = stddev / mean
                    self.intervalRegularityScore = max(0.0, min(1.0, 1.0 - cv))
                } else {
                    self.intervalRegularityScore = nil
                }
            } else {
                self.intervalStandardDeviation = nil
                self.intervalRegularityScore = nil
            }
        } else {
            self.averageInterval = nil
            self.intervalStandardDeviation = nil
            self.intervalRegularityScore = nil
        }

        // Hourly distribution
        var hourly = Array(repeating: 0, count: 24)
        for event in sorted {
            let date = Date(timeIntervalSinceReferenceDate: event.timestamp)
            let hour = calendar.component(.hour, from: date)
            hourly[hour] += 1
        }
        self.hourlyDistribution = hourly
        if sorted.isEmpty {
            self.peakHour = nil
        } else {
            self.peakHour = hourly.enumerated().max(by: { $0.element < $1.element })?.offset
        }
    }

    // MARK: - Convenience

    /// A plain-English description of the acknowledgement rate,
    /// e.g. "75% effective". Returns `nil` if no events.
    var effectivenessDescription: String? {
        guard let rate = acknowledgementRate else { return nil }
        return "\(Int(rate))% effective"
    }

    /// A plain-English description of the average response time,
    /// e.g. "14 sec". Returns `nil` if no acknowledged nudges.
    var averageResponseDescription: String? {
        guard let avg = averageResponseTime else { return nil }
        let seconds = Int(avg)
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if remainingSeconds == 0 { return "\(minutes) min" }
        return "\(minutes) min \(remainingSeconds) sec"
    }

    /// A plain-English description of the dominant nudge reason,
    /// e.g. "Mostly sustained slouch". Returns `nil` if no events.
    var dominantReasonDescription: String? {
        guard let reason = dominantReason else { return nil }
        switch reason {
        case .sustainedSlouch: return "Mostly sustained slouch"
        case .forwardCreep: return "Mostly forward creep"
        case .headDrop: return "Mostly head drop"
        }
    }
}
