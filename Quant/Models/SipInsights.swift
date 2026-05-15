import Foundation
import PostureLogic

/// Pure-value snapshot of hydration statistics derived from a day's sip events.
///
/// All computation happens in `init` — no stored closures, no dependencies on
/// the file system or clock beyond the `referenceDate` you pass in. This makes
/// it trivially testable with deterministic timestamps.
///
/// Usage:
/// ```swift
/// let insights = SipInsights(sips: store.sips, referenceDate: Date())
/// print(insights.totalCount)           // 12
/// print(insights.averageInterval)      // 1800.0 (seconds)
/// print(insights.longestGap)           // 3600.0
/// print(insights.morningCount)         // 8
/// print(insights.afternoonCount)       // 4
/// ```
struct SipInsights: Equatable {

    // MARK: - Core Stats

    /// Total sips recorded.
    let totalCount: Int

    /// Average time between consecutive sips (seconds), or `nil` if fewer
    /// than two sips exist.
    let averageInterval: TimeInterval?

    /// Shortest gap between two consecutive sips (seconds), or `nil` if
    /// fewer than two sips.
    let shortestGap: TimeInterval?

    /// Longest gap between two consecutive sips (seconds), or `nil` if
    /// fewer than two sips.
    let longestGap: TimeInterval?

    /// Median gap between consecutive sips (seconds), or `nil` if fewer
    /// than two sips.
    let medianGap: TimeInterval?

    /// Population standard deviation of the inter-sip gaps (seconds), or
    /// `nil` if fewer than two gaps (i.e. fewer than three sips). A single
    /// gap has no measurable spread, so we return `nil` rather than `0`
    /// — `0` would falsely imply "perfectly regular cadence."
    let gapStandardDeviation: TimeInterval?

    /// A 0.0–1.0 score capturing how regular the user's sip cadence is,
    /// or `nil` if fewer than three sips. Computed as `1 - CV` (where
    /// CV is the coefficient of variation, `stddev / mean`), clamped
    /// to `[0, 1]`. `1.0` means perfectly even gaps; `0.0` means very
    /// erratic.
    let regularityScore: Double?

    // MARK: - Time-of-Day Breakdown

    /// Sips recorded before noon (using the reference date's calendar).
    let morningCount: Int

    /// Sips recorded at noon or later.
    let afternoonCount: Int

    // MARK: - Streak Info

    /// Duration from the first sip to the last sip (seconds), or `nil`
    /// if fewer than two sips.
    let activeDuration: TimeInterval?

    /// Timestamp of the first sip, or `nil` if no sips.
    let firstSipTimestamp: TimeInterval?

    /// Timestamp of the most recent sip, or `nil` if no sips.
    let lastSipTimestamp: TimeInterval?

    // MARK: - Hourly Distribution

    /// Number of sips in each hour (0–23). Always has 24 entries.
    let hourlyDistribution: [Int]

    /// The hour (0–23) with the most sips, or `nil` if no sips.
    let peakHour: Int?

    // MARK: - Initialization

    /// Computes insights from an array of sip events.
    ///
    /// - Parameters:
    ///   - sips: Today's sip events (need not be pre-sorted).
    ///   - referenceDate: Used to determine noon for the morning/afternoon
    ///     split. Defaults to now.
    ///   - calendar: Calendar for date component extraction. Defaults to
    ///     `.current`.
    init(
        sips: [SipEvent],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        let sorted = sips.sorted { $0.timestamp < $1.timestamp }

        self.totalCount = sorted.count
        self.firstSipTimestamp = sorted.first?.timestamp
        self.lastSipTimestamp = sorted.last?.timestamp

        // Active duration
        if let first = sorted.first?.timestamp,
           let last = sorted.last?.timestamp, sorted.count >= 2 {
            self.activeDuration = last - first
        } else {
            self.activeDuration = nil
        }

        // Inter-sip gaps
        let gaps: [TimeInterval]
        if sorted.count >= 2 {
            gaps = zip(sorted.dropLast(), sorted.dropFirst()).map { later, earlier in
                earlier.timestamp - later.timestamp
            }
        } else {
            gaps = []
        }

        if gaps.isEmpty {
            self.averageInterval = nil
            self.shortestGap = nil
            self.longestGap = nil
            self.medianGap = nil
            self.gapStandardDeviation = nil
            self.regularityScore = nil
        } else {
            let mean = gaps.reduce(0, +) / Double(gaps.count)
            self.averageInterval = mean
            self.shortestGap = gaps.min()
            self.longestGap = gaps.max()
            let sortedGaps = gaps.sorted()
            let mid = sortedGaps.count / 2
            if sortedGaps.count.isMultiple(of: 2) {
                self.medianGap = (sortedGaps[mid - 1] + sortedGaps[mid]) / 2.0
            } else {
                self.medianGap = sortedGaps[mid]
            }

            // Spread + regularity require ≥ 2 gaps for variability to be
            // meaningful. A single gap has stddev 0 by convention, but
            // that would falsely report "perfect regularity" from one
            // data point.
            if gaps.count >= 2 {
                let squaredDeviations = gaps.map { ($0 - mean) * ($0 - mean) }
                let variance = squaredDeviations.reduce(0, +) / Double(gaps.count)
                let stddev = variance.squareRoot()
                self.gapStandardDeviation = stddev
                if mean > 0 {
                    let cv = stddev / mean
                    self.regularityScore = max(0.0, min(1.0, 1.0 - cv))
                } else {
                    self.regularityScore = nil
                }
            } else {
                self.gapStandardDeviation = nil
                self.regularityScore = nil
            }
        }

        // Morning / afternoon split — noon on the reference date
        let noonComponents = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        var noonDateComponents = noonComponents
        noonDateComponents.hour = 12
        noonDateComponents.minute = 0
        noonDateComponents.second = 0
        let noonTimestamp = (calendar.date(from: noonDateComponents) ?? referenceDate)
            .timeIntervalSinceReferenceDate

        var morning = 0
        var afternoon = 0
        for sip in sorted {
            if sip.timestamp < noonTimestamp {
                morning += 1
            } else {
                afternoon += 1
            }
        }
        self.morningCount = morning
        self.afternoonCount = afternoon

        // Hourly distribution
        var hourly = Array(repeating: 0, count: 24)
        for sip in sorted {
            let date = Date(timeIntervalSinceReferenceDate: sip.timestamp)
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

    /// A plain-English description of the average interval, e.g. "32 min".
    /// Returns `nil` if no average is available.
    var averageIntervalDescription: String? {
        guard let avg = averageInterval else { return nil }
        let minutes = Int(avg / 60)
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainingMinutes) min"
    }

    /// A plain-English description of the longest gap, e.g. "1 hr 15 min".
    /// Returns `nil` if no gap data is available.
    var longestGapDescription: String? {
        guard let gap = longestGap else { return nil }
        let minutes = Int(gap / 60)
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainingMinutes) min"
    }
}
