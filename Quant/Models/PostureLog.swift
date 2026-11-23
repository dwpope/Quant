import Combine
import Foundation
import PostureLogic

/// One line of the posture log: a change in the posture state, the nudge decision or the task
/// mode, at a calendar time.
///
/// Asked for on 2026-10-07: Dave worked for an hour, saw a countdown, and got no nudge, and nothing
/// recorded why. A state change carries the numbers behind it; a nudge decision carries its reason
/// and, while pending, how long was left.
nonisolated struct PostureLogEvent: Codable, Equatable {
    /// Seconds since 1970.
    var t: TimeInterval
    /// "state", "nudge", "task", "watch", "camera" (which way round its frames are), "tick":
    /// the state again, a minute after the last line, while nothing changes (2026-10-16), or
    /// "tracking": the debug panel's tracking numbers over 10 seconds it wasn't good (2026-11-17);
    /// "metrics": the judged frames' numbers over 10 seconds; "settings": the build and the lines
    /// in force; "calibration": the baseline measured from (all 2026-11-19).
    var kind: String
    /// "good", "drifting", "bad", "absent", "calibrating"; "none", "pending:<reason>",
    /// "fire:<reason>", "suppressed:<reason>"; a task mode; how a nudge left for the Watch
    /// (`NudgeDelivery`); or the tracking most frames had ("good", "degraded", "lost").
    var value: String
    var forwardCreep: Float? = nil
    var headDrop: Float? = nil
    var shoulderSink: Float? = nil
    var lateralShift: Float? = nil
    var headYaw: Float? = nil
    /// Seconds left on a pending nudge when it started counting.
    var remaining: TimeInterval? = nil
    /// For a nudge's arrival on the Watch: seconds after it was sent, how it came ("message" or
    /// "queued"), and whether the Watch app was being kept running.
    var delay: TimeInterval? = nil
    var via: String? = nil
    var wristSession: Bool? = nil
    /// Where the Watch's banner went (2026-11-09): the app's state as the nudge arrived, then,
    /// on a "banner" line, whether its notification was posted and how notifications are set.
    var appState: String? = nil
    var posted: Bool? = nil
    var error: String? = nil
    var authorization: String? = nil
    var alert: String? = nil
    var notificationCenter: String? = nil
    /// On a "notification" line (2026-11-09): whether the Watch app showed the nudge itself, and
    /// seconds after its notification was posted until watchOS offered it to the app (and what
    /// the app answered), and until it was listed in Notification Center (and the date it got).
    var onScreen: Bool? = nil
    var offeredAfter: TimeInterval? = nil
    var offeredAs: String? = nil
    var listedAfter: TimeInterval? = nil
    var datedAfter: TimeInterval? = nil
    /// On a "tracking" line (2026-11-17), the camera frames in the `over` seconds up to `t`: how
    /// many had each tracking; Vision's confidence in the whole pose (lowest, median, highest)
    /// and the median keypoint count, over those with a pose; and how many lacked each critical
    /// joint, or had no pose and why, as the panel's Missing names them ("LShldr:12,Head:3").
    var over: TimeInterval? = nil
    var framesGood: Int? = nil
    var framesDegraded: Int? = nil
    var framesLost: Int? = nil
    var poseConfLow: Float? = nil
    var poseConfMedian: Float? = nil
    var poseConfHigh: Float? = nil
    var keypoints: Int? = nil
    var missing: String? = nil
    /// On a fired nudge's line (2026-11-19), which repeat it was, as the Watch was told: 0 for a
    /// slouch's first nudge. The fire line also carries the numbers it fired on.
    var nudgeRepeat: Int? = nil
    /// On a "metrics" line (2026-11-19), the judged frames in the `over` seconds up to `t`: how
    /// many, head drop and forward lean at their lowest, median and highest (head drop's lowest
    /// is the deepest dip), the highest of the rest, seconds slouched, seconds past each line
    /// tried so far and the one in force (keyed "0.01875"), and the baseline's age in seconds.
    var frames: Int? = nil
    var headDropLow: Float? = nil
    var headDropMedian: Float? = nil
    var headDropHigh: Float? = nil
    var forwardCreepLow: Float? = nil
    var forwardCreepMedian: Float? = nil
    var forwardCreepHigh: Float? = nil
    var shoulderSinkMedian: Float? = nil
    var shoulderSinkHigh: Float? = nil
    var sideLeanMedian: Float? = nil
    var sideLeanHigh: Float? = nil
    var twistHigh: Float? = nil
    var roundingHigh: Float? = nil
    var slouched: Float? = nil
    var headDropPast: [String: Float]? = nil
    var forwardCreepPast: [String: Float]? = nil
    var baselineAge: TimeInterval? = nil
    /// On a "seat" line (2026-11-23): what raised the seat question ("nearMisses" or "onReturn"),
    /// the readings behind it (a comma list, sorted) and, for near-misses, how many.
    var trigger: String? = nil
    var reason: String? = nil
    var count: Int? = nil
    /// On a "seat" line: the values that raised the question, by reading. Near-misses: each counted
    /// near-miss's peak. On return: the two window medians. Five decimals.
    var evidence: [String: [Float]]? = nil
    /// On a "settings" line (2026-11-19): every line the engines decide by, by name.
    var lines: [String: Float]? = nil
    /// On a "calibration" line (2026-11-19): the baseline's numbers, by name.
    var baseline: [String: Float]? = nil
}

/// Decides what's worth a line: changes, and a tick a minute while nothing changes. The
/// countdown ticks every frame and is not one.
///
/// The tick (2026-10-16): with only changes written, sitting well for 25 minutes wrote nothing,
/// and the timeline read 10 minutes of nothing as the app having closed. Each day's file also
/// starts with where things stand, so it reads on its own.
struct PostureLogRecorder {
    /// Which day's file a line goes in, as `PostureLogStore` names them.
    var calendar = Calendar.current
    private var lastState: String?
    private var lastNudge: String?
    private var lastTask: String?
    private var lastDay: String?
    private var lastLineAt: TimeInterval?

    /// A line at least this often while frames come in.
    static let tickEvery: TimeInterval = 60

    mutating func events(state: PostureState, decision: NudgeDecision, taskMode: TaskMode,
                         metrics: RawMetrics?, headYaw: Float?, nudgeRepeat: Int? = nil,
                         now: Date) -> [PostureLogEvent] {
        let t = now.timeIntervalSince1970
        var out: [PostureLogEvent] = []
        defer { if !out.isEmpty { lastLineAt = t } }

        let day = PostureLogStore.dayKey(for: now, calendar: calendar)
        if day != lastDay {
            lastDay = day
            lastState = nil
            lastNudge = nil
            lastTask = nil
        }

        let stateName = Self.name(of: state)
        if stateName != lastState {
            lastState = stateName
            out.append(PostureLogEvent(
                t: t, kind: "state", value: stateName,
                forwardCreep: metrics?.forwardCreep, headDrop: metrics?.headDrop,
                shoulderSink: metrics?.shoulderSink, lateralShift: metrics?.lateralLeanSigned,
                headYaw: headYaw))
        }

        let nudgeName = Self.name(of: decision)
        if nudgeName != lastNudge {
            lastNudge = nudgeName
            var event = PostureLogEvent(t: t, kind: "nudge", value: nudgeName)
            if case .pending(_, let remaining) = decision { event.remaining = remaining.rounded() }
            if case .fire = decision {
                event.forwardCreep = metrics?.forwardCreep
                event.headDrop = metrics?.headDrop
                event.shoulderSink = metrics?.shoulderSink
                event.lateralShift = metrics?.lateralLeanSigned
                event.headYaw = headYaw
                event.nudgeRepeat = nudgeRepeat
            }
            out.append(event)
        }

        let taskName = taskMode.rawValue
        if taskName != lastTask {
            lastTask = taskName
            out.append(PostureLogEvent(t: t, kind: "task", value: taskName))
        }

        if out.isEmpty, let last = lastLineAt, t - last >= Self.tickEvery {
            out.append(PostureLogEvent(
                t: t, kind: "tick", value: stateName,
                forwardCreep: metrics?.forwardCreep, headDrop: metrics?.headDrop,
                shoulderSink: metrics?.shoulderSink, lateralShift: metrics?.lateralLeanSigned,
                headYaw: headYaw))
        }
        return out
    }

    /// One camera frame's tracking, as the debug panel shows it.
    struct TrackingFrame {
        var quality: TrackingQuality
        /// Vision's confidence in the whole pose; 0 with no pose.
        var poseConfidence: Float
        /// 0 with no pose.
        var keypoints: Int
        /// "none", the critical joints missing ("LShldr,Head"), or why there was no pose.
        var missing: String
    }

    /// How many seconds of frames a "tracking" line sums up.
    static let trackingEvery: TimeInterval = 10

    private var trackingWindow: [(t: TimeInterval, frame: TrackingFrame)] = []

    /// A "tracking" line for the last `trackingEvery` seconds of frames, when they weren't all
    /// good (2026-11-17). With the phone on its side, tracking was mostly degraded, which holds
    /// off judging, and Dave was Away 73% of the time with nothing in the log to say why: the
    /// whole pose's confidence too low, or a joint missing. The panel shows it, but reading the
    /// panel means moving. Separate from `events` so these lines don't put off a tick: they
    /// don't say the state.
    mutating func trackingEvents(_ frame: TrackingFrame, now: Date) -> [PostureLogEvent] {
        let t = now.timeIntervalSince1970
        var out: [PostureLogEvent] = []
        if let start = trackingWindow.first?.t, t - start >= Self.trackingEvery {
            if let line = Self.trackingLine(trackingWindow) { out.append(line) }
            trackingWindow = []
        }
        trackingWindow.append((t, frame))
        return out
    }

    /// Ends at the window's last frame, so a window cut off by the app going to the background
    /// covers only the frames it had. It's written when frames come again: if the app is closed
    /// first, its last few seconds go unlogged. Medians are the upper middle value for an even
    /// count.
    private static func trackingLine(_ window: [(t: TimeInterval, frame: TrackingFrame)]) -> PostureLogEvent? {
        let frames = window.map(\.frame)
        guard let first = window.first, let last = window.last,
              frames.contains(where: { $0.quality != .good }) else { return nil }

        func count(_ quality: TrackingQuality) -> Int { frames.filter { $0.quality == quality }.count }
        // Worst first: `max` keeps the first of equal counts, so a tie says the worse.
        let counts: [(TrackingQuality, Int)] = [(.lost, count(.lost)), (.degraded, count(.degraded)),
                                                (.good, count(.good))]
        let most = counts.max { $0.1 < $1.1 }?.0 ?? .lost

        let posed = frames.filter { $0.keypoints > 0 }
        let confidences = posed.map(\.poseConfidence).sorted()
        let keypoints = posed.map(\.keypoints).sorted()
        func hundredths(_ x: Float?) -> Float? { x.map { ($0 * 100).rounded() / 100 } }

        var missingCounts: [String: Int] = [:]
        for f in frames where f.missing != "none" && !f.missing.isEmpty {
            for joint in f.missing.split(separator: ",") { missingCounts[String(joint), default: 0] += 1 }
        }
        let missing = missingCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")

        var line = PostureLogEvent(t: last.t, kind: "tracking", value: most.rawValue)
        line.over = ((last.t - first.t) * 10).rounded() / 10
        line.framesGood = count(.good)
        line.framesDegraded = count(.degraded)
        line.framesLost = count(.lost)
        line.poseConfLow = hundredths(confidences.first)
        line.poseConfMedian = hundredths(confidences.isEmpty ? nil : confidences[confidences.count / 2])
        line.poseConfHigh = hundredths(confidences.last)
        line.keypoints = keypoints.isEmpty ? nil : keypoints[keypoints.count / 2]
        line.missing = missing.isEmpty ? nil : missing
        return line
    }

    // MARK: - For tuning (2026-11-19)

    /// Head drop lines tried so far and either side, summed up on every "metrics" line with the
    /// one in force, so a line can be tried again on a past session.
    static let headDropLines: [Float] = [0.015, 0.0175, 0.01875, 0.02, 0.0225, 0.025]
    /// Forward lean's, with 0.078: 0.06 in reading mode, which is most of the time.
    static let forwardCreepLines: [Float] = [0.06, 0.07, 0.078, 0.09, 0.1]
    /// How many seconds of judged frames a "metrics" line sums up.
    static let metricsEvery: TimeInterval = 10

    private struct JudgedFrame {
        var t: TimeInterval
        var state: String
        var metrics: RawMetrics
    }
    private var metricsWindow: [JudgedFrame] = []
    private var metricsBaselineTakenAt: Date?
    private var lastSettings: [String: Float]?
    private var settingsDay: String?
    private var lastBaselineTakenAt: Date?
    private var calibrationDay: String?

    /// A "metrics" line for the last `metricsEvery` seconds of judged frames (2026-11-19). The
    /// state and tick lines carry the numbers only as a line is crossed, so they all sit by the
    /// line: on 11-18, 885 of them for about 64,200 frames. Separate from `events`, like the
    /// tracking line, so it doesn't put off a tick.
    mutating func metricsEvents(state: PostureState, metrics: RawMetrics, baselineTakenAt: Date,
                                headDropLine: Float, forwardCreepLine: Float, now: Date) -> [PostureLogEvent] {
        let t = now.timeIntervalSince1970
        var out: [PostureLogEvent] = []
        if let start = metricsWindow.first?.t, t - start >= Self.metricsEvery {
            if let line = Self.metricsLine(metricsWindow, baselineTakenAt: metricsBaselineTakenAt,
                                           headDropLines: Self.headDropLines + [headDropLine],
                                           forwardCreepLines: Self.forwardCreepLines + [forwardCreepLine]) {
                out.append(line)
            }
            metricsWindow = []
        }
        metricsWindow.append(JudgedFrame(t: t, state: Self.name(of: state), metrics: metrics))
        metricsBaselineTakenAt = baselineTakenAt
        return out
    }

    /// Ends at the window's last frame, as the tracking line does. Seconds are the share of
    /// frames times the window, to a tenth: frames come about 10 a second. Past a line means as
    /// the posture engine has it: head drop at or past it, forward lean over it.
    private static func metricsLine(_ window: [JudgedFrame], baselineTakenAt: Date?,
                                    headDropLines: [Float], forwardCreepLines: [Float]) -> PostureLogEvent? {
        guard let first = window.first, let last = window.last else { return nil }
        let over = ((last.t - first.t) * 10).rounded() / 10
        let n = Float(window.count)
        func seconds(_ count: Int) -> Float { (Float(count) / n * Float(over) * 10).rounded() / 10 }
        func fine(_ x: Float) -> Float { (x * 100_000).rounded() / 100_000 }
        func spread(_ values: [Float]) -> (low: Float, median: Float, high: Float) {
            let sorted = values.sorted()
            return (fine(sorted[0]), fine(sorted[sorted.count / 2]), fine(sorted[sorted.count - 1]))
        }

        let states = window.map(\.state)
        // Most frames' state; a tie says the worse, as the tracking line does.
        let most = ["bad", "drifting", "good"].max { a, b in
            states.filter { $0 == a }.count < states.filter { $0 == b }.count
        } ?? "good"

        let drops = window.map(\.metrics.headDrop)
        let creeps = window.map(\.metrics.forwardCreep)
        var headDropPast: [String: Float] = [:]
        for line in headDropLines {
            headDropPast[key(line)] = seconds(drops.filter { -$0 >= line }.count)
        }
        var forwardCreepPast: [String: Float] = [:]
        for line in forwardCreepLines {
            forwardCreepPast[key(line)] = seconds(creeps.filter { $0 > line }.count)
        }

        var event = PostureLogEvent(t: last.t, kind: "metrics", value: most)
        event.over = over
        event.frames = window.count
        (event.headDropLow, event.headDropMedian, event.headDropHigh) = spread(drops)
        (event.forwardCreepLow, event.forwardCreepMedian, event.forwardCreepHigh) = spread(creeps)
        let sinks = window.map(\.metrics.shoulderSink)
        let leans = window.map(\.metrics.lateralLean)
        (_, event.shoulderSinkMedian, event.shoulderSinkHigh) = spread(sinks)
        (_, event.sideLeanMedian, event.sideLeanHigh) = spread(leans)
        event.twistHigh = fine(window.map(\.metrics.twist).max() ?? 0)
        event.roundingHigh = fine(window.map(\.metrics.shoulderRounding).max() ?? 0)
        event.slouched = seconds(states.filter { $0 == "drifting" || $0 == "bad" }.count)
        event.headDropPast = headDropPast
        event.forwardCreepPast = forwardCreepPast
        event.baselineAge = baselineTakenAt.map { (last.t - $0.timeIntervalSince1970).rounded() }
        return event
    }

    /// A line's key: to 5 places without trailing zeros, "0.01875", "0.06".
    static func key(_ line: Float) -> String {
        var text = String(format: "%.5f", line)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// A "settings" line with the build and every line in force (2026-11-19): at the first frame,
    /// when one changes, and at the start of each day. The log said neither, so which line a
    /// session ran on had to be worked out from where its crossings sat.
    mutating func settingsEvents(_ lines: [String: Float], build: String, now: Date) -> [PostureLogEvent] {
        let day = PostureLogStore.dayKey(for: now, calendar: calendar)
        guard lines != lastSettings || day != settingsDay else { return [] }
        lastSettings = lines
        settingsDay = day
        var event = PostureLogEvent(t: now.timeIntervalSince1970, kind: "settings", value: build)
        event.lines = lines
        return [event]
    }

    /// Every line the posture and nudge engines decide by, by name. Forward lean's is before
    /// the task mode's allowance (1.3 times it while reading); the task line says the mode.
    static func lines(of thresholds: PostureThresholds) -> [String: Float] {
        [
            "headDrop": thresholds.headDropThreshold,
            "headDropMinForwardCreep": thresholds.headDropMinForwardCreep,
            "forwardCreep": thresholds.forwardCreepThreshold,
            "sideLean": thresholds.sideLeanThreshold,
            "twist": thresholds.twistThreshold,
            "shoulderRounding": thresholds.shoulderRoundingThreshold,
            "shoulderSink": thresholds.shoulderSinkThreshold,
            "reclinedSink": thresholds.reclinedSinkThreshold,
            "reclineMaxForwardCreep": thresholds.reclineMaxForwardCreep,
            "slouchSeconds": Float(thresholds.slouchDurationBeforeNudge),
            "driftGrace": Float(thresholds.driftingToBadThreshold),
            "nudgeCooldown": Float(thresholds.nudgeCooldown),
            "maxNudgesPerHour": Float(thresholds.maxNudgesPerHour),
        ]
    }

    /// A "calibration" line with the baseline measured from (2026-11-19): when one is taken or
    /// loaded, and at the start of each day, with its age. Readings from two calibrations sat on
    /// one scale, and nothing said whether 0.001 apart was the body or the calibration pose.
    mutating func calibrationEvents(_ baseline: Baseline?, now: Date) -> [PostureLogEvent] {
        guard let baseline else { return [] }
        let day = PostureLogStore.dayKey(for: now, calendar: calendar)
        guard baseline.timestamp != lastBaselineTakenAt || day != calibrationDay else { return [] }
        lastBaselineTakenAt = baseline.timestamp
        calibrationDay = day
        func fine(_ x: Float) -> Float { (x * 100_000).rounded() / 100_000 }
        var event = PostureLogEvent(t: now.timeIntervalSince1970, kind: "calibration",
                                    value: baseline.orientation.rawValue)
        event.baselineAge = now.timeIntervalSince(baseline.timestamp).rounded()
        event.baseline = [
            "shoulderWidth": fine(baseline.shoulderWidth),
            "neckHeight": fine(baseline.neckHeight),
            "headYaw": fine(baseline.headYaw),
            "torsoAngle": fine(baseline.torsoAngle),
            "shoulderTwist": fine(baseline.shoulderTwist),
            "shoulderX": fine(baseline.shoulderMidpoint.x),
            "shoulderY": fine(baseline.shoulderMidpoint.y),
        ]
        return [event]
    }

    /// How a fired nudge left for the Watch (2026-10-08): the phone fired twice in Dave's second
    /// hour and he felt one buzz, and nothing said which way each went.
    static func watchEvent(_ delivery: NudgeDelivery, now: Date) -> PostureLogEvent {
        PostureLogEvent(t: now.timeIntervalSince1970, kind: "watch", value: delivery.rawValue)
    }

    /// When a nudge reached the Watch, as the Watch reported it (2026-10-10): session 3's nudges
    /// arrived late, and nothing said how late.
    static func arrivalEvent(_ arrival: NudgeArrival) -> PostureLogEvent {
        PostureLogEvent(t: arrival.arrivedAt.timeIntervalSince1970, kind: "watch", value: "arrived",
                        delay: arrival.arrivedAt.timeIntervalSince(arrival.sentAt), via: arrival.via,
                        wristSession: arrival.wristSession, appState: arrival.appState)
    }

    /// What became of a nudge's notification on the Watch (2026-11-09), at the nudge's sending
    /// time, beside its "sent" or "queued" line.
    static func bannerEvent(_ banner: NudgeBanner) -> PostureLogEvent {
        PostureLogEvent(t: banner.sentAt.timeIntervalSince1970, kind: "watch", value: "banner",
                        posted: banner.posted, error: banner.error,
                        authorization: banner.authorization, alert: banner.alert,
                        notificationCenter: banner.notificationCenter)
    }

    /// What watchOS did with a nudge's notification (2026-11-09), at the nudge's sending time,
    /// beside its "banner" line.
    static func notificationEvent(_ times: NudgeNotificationTimes) -> PostureLogEvent {
        PostureLogEvent(t: times.sentAt.timeIntervalSince1970, kind: "watch", value: "notification",
                        onScreen: times.onScreen, offeredAfter: times.offeredAfter,
                        offeredAs: times.offeredAs, listedAfter: times.listedAfter,
                        datedAfter: times.datedAfter)
    }

    /// Which way round the camera's frames came (2026-11-11): once at the first frame, and again
    /// each time the phone is turned. Head drop and sink are measured the same either way.
    static func cameraEvent(_ orientation: FrameOrientation, now: Date) -> PostureLogEvent {
        PostureLogEvent(t: now.timeIntervalSince1970, kind: "camera", value: orientation.rawValue)
    }

    static func name(of state: PostureState) -> String {
        switch state {
        case .good: return "good"
        case .drifting: return "drifting"
        case .bad: return "bad"
        case .absent: return "absent"
        case .calibrating: return "calibrating"
        }
    }

    static func name(of decision: NudgeDecision) -> String {
        switch decision {
        case .none: return "none"
        case .pending(let reason, _): return "pending:\(reason.rawValue)"
        case .fire(let reason): return "fire:\(reason.rawValue)"
        case .suppressed(let reason): return "suppressed:\(reason.rawValue)"
        }
    }
}

/// Keeps the posture log on the phone, one JSON line per event in a file per day, and exports
/// every day's lines as one file. Local only: it leaves the phone when Dave shares the export.
@MainActor
final class PostureLogStore: ObservableObject {

    nonisolated deinit {}

    /// Lines kept across every day.
    @Published private(set) var count = 0

    private let calendar = Calendar.current

    /// Lines appended since launch, so a recount can add the ones that came while it read.
    private var appended = 0

    init() {
        count = Self.lineCount()
    }

    /// Counts the lines again, after older days were deleted (2026-10-11). Off the main thread
    /// since the 2026-10-16 audit: it read every day's file there, and the screen waited. On the
    /// write queue, so every line already handed to it is on disk first; lines appended while it
    /// reads are added on.
    func recount(counting: @escaping @Sendable () -> Int = PostureLogStore.lineCount) async {
        let appendedBefore = appended
        let lines = await withCheckedContinuation { done in
            Self.persistQueue.async { done.resume(returning: counting()) }
        }
        count = lines + (appended - appendedBefore)
    }

    /// Lines across every day's file.
    nonisolated static func lineCount() -> Int {
        dayFiles().reduce(0) { total, url in
            total + ((try? String(contentsOf: url, encoding: .utf8))?
                .split(separator: "\n").count ?? 0)
        }
    }

    func append(_ events: [PostureLogEvent]) {
        guard !events.isEmpty else { return }
        count += events.count
        appended += events.count
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = events.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .map { $0 + "\n" }
            .joined()
        let url = Self.fileURL(for: dateKey(for: Date()))
        Self.persistQueue.async {
            let data = Data(lines.utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Every day's lines, oldest day first, as `posture-log-to-<today>.jsonl` in the caches folder.
    /// Written on the write queue, so every line already handed to it is on disk first. Not on
    /// the main thread since the 2026-10-16 audit: it waited there behind a recount, then read
    /// every day's file, and the screen waited too.
    func exportJSONL() async throws -> URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("posture-log-to-\(dateKey(for: Date())).jsonl")
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            Self.persistQueue.async {
                let joined = Self.dayFiles()
                    .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                    .joined()
                done.resume(with: Result { try Data(joined.utf8).write(to: url, options: .atomic) })
            }
        }
        return url
    }

    /// Copies each day's file into `folder` where the copy there is a different size (2026-11-17),
    /// for `PostureLogFolder`. Lines are only ever added, so a day the same size hasn't changed.
    /// On the write queue, so every line already handed to it is in. Returns the names copied.
    func copy(to folder: URL) async throws -> [String] {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<[String], Error>) in
            Self.persistQueue.async {
                done.resume(with: Result { try Self.copyDays(to: folder) })
            }
        }
    }

    /// A folder chosen in Files is only open to the app while it says it's using it, and iCloud
    /// Drive wants each write coordinated, so its own sync doesn't read a half-written file.
    private nonisolated static func copyDays(to folder: URL) throws -> [String] {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        func size(_ url: URL) -> Int? { (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }

        var copied: [String] = []
        for key in dayKeys().reversed() {
            let name = "posture-log-\(key).jsonl"
            let source = documents.appendingPathComponent(name)
            let copy = folder.appendingPathComponent(name)
            guard size(source) != size(copy) else { continue }
            let data = try Data(contentsOf: source)
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: copy, options: .forReplacing,
                                           error: &coordinationError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
            copied.append(name)
        }
        return copied
    }

    /// Blocks until queued writes complete.
    nonisolated static func flushPendingWrites() {
        persistQueue.sync {}
    }

    private nonisolated static let persistQueue = DispatchQueue(label: "com.quant.postureLog.persist",
                                                                qos: .utility)

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private nonisolated static func fileURL(for key: String) -> URL {
        documents.appendingPathComponent("posture-log-\(key).jsonl")
    }

    // MARK: - Reading a day back (2026-10-13), for the timeline

    /// The days with a log, newest first, as `YYYY-MM-DD`.
    nonisolated static func dayKeys(in folder: URL = documents) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { $0.hasPrefix("posture-log-") && $0.hasSuffix(".jsonl") && !$0.hasPrefix("posture-log-to-") }
            .map { String($0.dropFirst("posture-log-".count).dropLast(".jsonl".count)) }
            .sorted(by: >)
    }

    /// A day's lines, skipping any that don't read. Waits for queued writes first.
    nonisolated static func events(dayKey: String, in folder: URL = documents) -> [PostureLogEvent] {
        if folder == documents { flushPendingWrites() }
        let url = folder.appendingPathComponent("posture-log-\(dayKey).jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(PostureLogEvent.self, from: Data($0.utf8))
        }
    }

    /// `YYYY-MM-DD` for a day, as the files are named.
    nonisolated static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private nonisolated static func dayFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        return names
            .filter { $0.hasPrefix("posture-log-") && $0.hasSuffix(".jsonl") && !$0.hasPrefix("posture-log-to-") }
            .sorted()
            .map { documents.appendingPathComponent($0) }
    }

    private func dateKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension PostureLogEvent {
    /// A seat-change suggestion: "would-ask" while only logging, "asked" when the question is put
    /// (`via` says how the Watch was told).
    static func seatEvent(_ suggestion: SeatChangeSuggestion, mode: SeatChangeMode,
                          via: String? = nil) -> PostureLogEvent {
        var event = PostureLogEvent(t: suggestion.at, kind: "seat",
                                    value: mode == .ask ? "asked" : "would-ask")
        event.via = via
        if !suggestion.evidence.isEmpty {
            event.evidence = suggestion.evidence.mapValues { $0.map { ($0 * 100_000).rounded() / 100_000 } }
        }
        switch suggestion.trigger {
        case let .nearMisses(reason, count):
            event.trigger = "nearMisses"
            event.reason = reason.rawValue
            event.count = count
        case let .onReturn(reasons):
            event.trigger = "onReturn"
            event.reason = reasons.map(\.rawValue).sorted().joined(separator: ",")
        }
        return event
    }

    /// How an open seat-change question ended.
    static func seatEvent(closed outcome: SeatChangeOutcome, at t: TimeInterval) -> PostureLogEvent {
        PostureLogEvent(t: t, kind: "seat", value: "closed:\(outcome.rawValue)")
    }
}
