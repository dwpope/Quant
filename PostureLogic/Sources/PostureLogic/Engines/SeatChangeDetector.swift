import Foundation

/// Why the app is asking whether the seat has moved.
public enum SeatChangeTrigger: Equatable, Sendable {
    /// The same reading brushed its line `count` times in five minutes without ever turning bad.
    case nearMisses(reason: NudgeReason, count: Int)
    /// After a long absence the sitting is offset past half a line, in a slouch direction.
    case onReturn(reasons: Set<NudgeReason>)
}

public struct SeatChangeSuggestion: Equatable, Sendable {
    public let trigger: SeatChangeTrigger
    public let at: TimeInterval
    /// The values that raised the question, keyed by the reason's raw value. Near-misses: the
    /// peak of each counted near-miss, in the slouch direction. On return: the two window
    /// medians, `[first, second]`, for each offset reading.
    public let evidence: [String: [Float]]

    public init(trigger: SeatChangeTrigger, at: TimeInterval, evidence: [String: [Float]] = [:]) {
        self.trigger = trigger
        self.at = at
        self.evidence = evidence
    }
}

/// Notices that the calibration no longer matches where Dave sits: either he keeps nearly
/// slouching on the same reading, or he comes back from a break sitting off the baseline.
/// Pure and clocked by frame time only. Wiring into `Pipeline` is separate.
struct SeatChangeDetector {
    private static let readings: [NudgeReason] = [.headDrop, .forwardCreep, .sideLean, .sink]

    private static let nearMissesNeeded = 5
    private static let nearMissWindow: TimeInterval = 300
    /// A drift whose peak stays within this many lines was a near-miss, not a real slouch.
    private static let nearMissPeakLines: Float = 1.5
    /// Past half a line counts as offset.
    private static let toleranceLines: Float = 0.5
    private static let settle: TimeInterval = 5
    private static let firstWindowEnd: TimeInterval = 15
    private static let secondWindowEnd: TimeInterval = 25

    /// The drift episode now open: its reasons and each reading's peak in the slouch direction.
    private var episodeReasons: Set<NudgeReason>?
    private var episodePeaks: [NudgeReason: Float] = [:]
    /// Whether any frame of the open drift had metrics: without them the peak is unknown.
    private var episodeHadMetrics = false

    private var nearMissTimes: [NudgeReason: [(t: TimeInterval, peak: Float)]] = [:]
    private var quiet = false

    private var absentSince: TimeInterval?
    private var returnStart: TimeInterval?
    private var firstWindow: [NudgeReason: [Float]] = [:]
    private var secondWindow: [NudgeReason: [Float]] = [:]

    init() {}

    /// One judged frame. Returns a suggestion at most once until `reset()` or the next return.
    mutating func observe(state: PostureState, signals: Set<NudgeReason>, metrics: RawMetrics?,
                          thresholds: PostureThresholds, at t: TimeInterval) -> SeatChangeSuggestion? {
        trackAbsenceAndReturn(state: state, thresholds: thresholds, at: t)
        let onReturn = collectReturn(state: state, metrics: metrics, thresholds: thresholds, at: t)
        let nearMiss = trackEpisode(state: state, signals: signals, metrics: metrics,
                                    thresholds: thresholds, at: t)
        if let onReturn { return onReturn }
        return nearMiss
    }

    /// After Recalibrate, Dismiss, timeout or away: forget near-misses, stay quiet until the next return.
    mutating func quietUntilNextReturn() {
        returnStart = nil
        firstWindow = [:]
        secondWindow = [:]
        nearMissTimes = [:]
        episodeReasons = nil
        episodePeaks = [:]
        episodeHadMetrics = false
        quiet = true
    }

    /// New baseline: forget everything, not quiet.
    mutating func reset() {
        self = SeatChangeDetector()
    }

    /// Log-only: start the count again, stay listening.
    mutating func forgetNearMisses() {
        nearMissTimes = [:]
        episodeReasons = nil
        episodePeaks = [:]
        episodeHadMetrics = false
        quiet = false
    }

    // MARK: Return check

    private mutating func trackAbsenceAndReturn(state: PostureState, thresholds: PostureThresholds,
                                                at t: TimeInterval) {
        if state == .absent {
            if absentSince == nil { absentSince = t }
            returnStart = nil
            return
        }
        guard let since = absentSince else { return }
        absentSince = nil
        guard t - since >= thresholds.absentResumeThreshold else { return }
        // A long break ends the old count: the near-misses were against the old sitting.
        nearMissTimes = [:]
        // The pipeline never emits `.calibrating`; the real protection is the reset on a baseline change.
        guard state != .calibrating else { return }
        returnStart = t
        firstWindow = [:]
        secondWindow = [:]
        quiet = false
    }

    private mutating func collectReturn(state: PostureState, metrics: RawMetrics?,
                                        thresholds: PostureThresholds,
                                        at t: TimeInterval) -> SeatChangeSuggestion? {
        guard let start = returnStart else { return nil }
        // The pipeline never emits `.calibrating`; the real protection is the reset on a baseline change.
        if state == .absent || state == .calibrating {
            returnStart = nil
            return nil
        }
        let elapsed = t - start
        if let m = metrics, elapsed >= Self.settle, elapsed <= Self.secondWindowEnd {
            for reason in Self.readings {
                let amount = Self.slouchAmount(reason, m)
                if elapsed < Self.firstWindowEnd {
                    firstWindow[reason, default: []].append(amount)
                } else {
                    secondWindow[reason, default: []].append(amount)
                }
            }
        }
        guard elapsed >= Self.secondWindowEnd else { return nil }
        returnStart = nil
        var evidence: [String: [Float]] = [:]
        var offset: Set<NudgeReason> = []
        for reason in Self.readings {
            let tolerance = Self.toleranceLines * Self.line(reason, thresholds)
            guard let a = Self.median(firstWindow[reason]), let b = Self.median(secondWindow[reason]),
                  a > tolerance, b > tolerance else { continue }
            offset.insert(reason)
            evidence[reason.rawValue] = [a, b]
        }
        firstWindow = [:]
        secondWindow = [:]
        guard !offset.isEmpty else { return nil }
        quiet = true
        return SeatChangeSuggestion(trigger: .onReturn(reasons: offset), at: t, evidence: evidence)
    }

    // MARK: Near-misses

    private mutating func trackEpisode(state: PostureState, signals: Set<NudgeReason>, metrics: RawMetrics?,
                                       thresholds: PostureThresholds,
                                       at t: TimeInterval) -> SeatChangeSuggestion? {
        switch state {
        case .drifting:
            var reasons = episodeReasons ?? []
            reasons.formUnion(signals.intersection(Self.readings))
            episodeReasons = reasons
            if let m = metrics {
                episodeHadMetrics = true
                for reason in Self.readings {
                    episodePeaks[reason] = max(episodePeaks[reason] ?? 0, Self.slouchAmount(reason, m))
                }
            }
            return nil
        case .good:
            defer { episodeReasons = nil; episodePeaks = [:]; episodeHadMetrics = false }
            guard let reasons = episodeReasons, episodeHadMetrics else { return nil }
            for reason in reasons {
                let peak = episodePeaks[reason] ?? 0
                if peak <= Self.nearMissPeakLines * Self.line(reason, thresholds) {
                    nearMissTimes[reason, default: []].append((t, peak))
                }
            }
            return suggestFromNearMisses(at: t)
        case .bad, .absent, .calibrating:
            episodeReasons = nil
            episodePeaks = [:]
            episodeHadMetrics = false
            return nil
        }
    }

    private mutating func suggestFromNearMisses(at t: TimeInterval) -> SeatChangeSuggestion? {
        for reason in Self.readings {
            nearMissTimes[reason] = nearMissTimes[reason]?.filter { t - $0.t <= Self.nearMissWindow }
        }
        guard !quiet else { return nil }
        for reason in Self.readings {
            let counted = nearMissTimes[reason] ?? []
            if counted.count >= Self.nearMissesNeeded {
                quiet = true
                return SeatChangeSuggestion(trigger: .nearMisses(reason: reason, count: counted.count), at: t,
                                            evidence: [reason.rawValue: counted.map(\.peak)])
            }
        }
        return nil
    }

    // MARK: Readings

    /// The reading in its slouch direction: positive means slouched, whatever the sign convention.
    private static func slouchAmount(_ reason: NudgeReason, _ m: RawMetrics) -> Float {
        switch reason {
        case .headDrop: return -m.headDrop
        case .forwardCreep: return m.forwardCreep
        case .sideLean: return m.lateralLean
        case .sink: return m.shoulderSink
        default: return 0
        }
    }

    private static func line(_ reason: NudgeReason, _ thresholds: PostureThresholds) -> Float {
        switch reason {
        case .headDrop: return thresholds.headDropThreshold
        case .forwardCreep: return thresholds.forwardCreepThreshold
        case .sideLean: return thresholds.sideLeanThreshold
        case .sink: return thresholds.shoulderSinkThreshold
        default: return .infinity
        }
    }

    private static func median(_ values: [Float]?) -> Float? {
        guard let values, !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
