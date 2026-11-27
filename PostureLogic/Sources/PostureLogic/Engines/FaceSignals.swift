import Foundation

/// One ARKit face reading. Pure data; the app buffers these at camera rate.
public struct FaceSample: Equatable, Sendable {
    /// Seconds since 1970.
    public let t: TimeInterval
    public let tracked: Bool
    public let eyeBlinkLeft: Float
    public let eyeBlinkRight: Float
    public let jawOpen: Float
    /// Head distance from the camera, metres.
    public let distance: Float?

    public init(t: TimeInterval, tracked: Bool, eyeBlinkLeft: Float, eyeBlinkRight: Float,
                jawOpen: Float, distance: Float?) {
        self.t = t
        self.tracked = tracked
        self.eyeBlinkLeft = eyeBlinkLeft
        self.eyeBlinkRight = eyeBlinkRight
        self.jawOpen = jawOpen
        self.distance = distance
    }
}

/// What the face did over one posture-log window.
public struct FaceSignalSummary: Equatable, Sendable {
    /// Tracked time over all time in the window.
    public let trackedShare: Float
    /// Share of tracked time with both eyes closed; nil when nothing was tracked.
    public let eyesClosedShare: Float?
    /// Closures of at least 0.3 s that ended in the window.
    public let longBlinks: Int
    /// The longest closure (any length) that ended in the window; nil when none ended.
    public let longestClosureMs: Int?
    public let yawns: Int
    public let distanceLow: Float?
    public let distanceMedian: Float?
    public let distanceHigh: Float?

    public init(trackedShare: Float, eyesClosedShare: Float?, longBlinks: Int,
                longestClosureMs: Int?, yawns: Int, distanceLow: Float?,
                distanceMedian: Float?, distanceHigh: Float?) {
        self.trackedShare = trackedShare
        self.eyesClosedShare = eyesClosedShare
        self.longBlinks = longBlinks
        self.longestClosureMs = longestClosureMs
        self.yawns = yawns
        self.distanceLow = distanceLow
        self.distanceMedian = distanceMedian
        self.distanceHigh = distanceHigh
    }
}

/// Turns frame-clocked face samples into the numbers the posture log writes. Pure.
public enum FaceSignals {
    /// Both eyes at least this closed count as closed.
    static let closedAt: Float = 0.8
    static let longBlink: TimeInterval = 0.3
    static let yawnAt: Float = 0.6
    static let yawnHold: TimeInterval = 2.0
    /// A face dropout longer than this discards an open closure or yawn.
    static let dropoutLimit: TimeInterval = 0.2
    /// A sample stands for at most this long.
    static let sampleCap: TimeInterval = 0.1
    private static let slack = 1e-6

    /// The summary for the half-open window `(from, to]`, or nil when no sample falls inside. A sample
    /// at exactly `from` belongs to the previous window, so windows that share an edge tile with no
    /// gap and no double count. Samples at or before `from` only reveal closures and yawns that
    /// began earlier; one that ends in the window counts there, one still open at `to` waits for
    /// the next window.
    public static func summary(_ samples: [FaceSample], from: TimeInterval,
                               to: TimeInterval) -> FaceSignalSummary? {
        let sorted = samples.sorted { $0.t < $1.t }
        let inWindow = sorted.indices.filter { sorted[$0].t > from && sorted[$0].t <= to }
        guard !inWindow.isEmpty else { return nil }

        var total = 0.0, tracked = 0.0, closed = 0.0
        var distances: [Float] = []
        for i in inWindow {
            let s = sorted[i]
            let next = i + 1 < sorted.count ? sorted[i + 1].t - s.t : sampleCap
            let weight = min(max(next, 0), sampleCap)
            total += weight
            guard s.tracked else { continue }
            tracked += weight
            if isClosed(s) { closed += weight }
            if let d = s.distance { distances.append(d) }
        }
        distances.sort()

        let closures = episodes(sorted, to: to, from: from, active: isClosed)
        let yawns = episodes(sorted, to: to, from: from) { $0.jawOpen >= yawnAt }

        return FaceSignalSummary(
            trackedShare: total > 0 ? Float(tracked / total) : 0,
            eyesClosedShare: tracked > 0 ? Float(closed / tracked) : nil,
            longBlinks: closures.filter { $0 >= longBlink - slack }.count,
            longestClosureMs: closures.max().map { Int(($0 * 1000).rounded()) },
            yawns: yawns.filter { $0 >= yawnHold - slack }.count,
            distanceLow: distances.first,
            distanceMedian: distances.isEmpty ? nil : distances[distances.count / 2],
            distanceHigh: distances.last)
    }

    private static func isClosed(_ s: FaceSample) -> Bool {
        s.eyeBlinkLeft >= closedAt && s.eyeBlinkRight >= closedAt
    }

    /// Durations of the episodes of `active` tracked samples that ended inside `(from, to]`.
    /// An episode ends at the first tracked sample that is not active. A dropout longer than
    /// `dropoutLimit` between active samples discards it.
    private static func episodes(_ sorted: [FaceSample], to: TimeInterval, from: TimeInterval,
                                 active: (FaceSample) -> Bool) -> [TimeInterval] {
        var result: [TimeInterval] = []
        var start: TimeInterval?
        var lastActive: TimeInterval = 0
        for s in sorted where s.t <= to {
            guard s.tracked else { continue }
            if start != nil, s.t - lastActive > dropoutLimit + slack { start = nil }
            if active(s) {
                if start == nil { start = s.t }
                lastActive = s.t
            } else if let begun = start {
                if s.t > from { result.append(s.t - begun) }
                start = nil
            }
        }
        return result
    }
}
