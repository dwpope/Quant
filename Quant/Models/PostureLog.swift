import Combine
import Foundation
import PostureLogic

/// One line of the posture log: a change in the posture state, the nudge decision or the task
/// mode, at a calendar time.
///
/// Asked for on 2026-10-07: Dave worked for an hour, saw a countdown, and got no nudge, and nothing
/// recorded why. A state change carries the numbers behind it; a nudge decision carries its reason
/// and, while pending, how long was left.
struct PostureLogEvent: Codable, Equatable {
    /// Seconds since 1970.
    var t: TimeInterval
    /// "state", "nudge", "task" or "watch".
    var kind: String
    /// "good", "drifting", "bad", "absent", "calibrating"; "none", "pending:<reason>",
    /// "fire:<reason>", "suppressed:<reason>"; a task mode; or how a nudge left for the Watch
    /// (`NudgeDelivery`).
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
}

/// Decides what's worth a line: only changes. The countdown ticks every frame and is not one.
struct PostureLogRecorder {
    private var lastState: String?
    private var lastNudge: String?
    private var lastTask: String?

    mutating func events(state: PostureState, decision: NudgeDecision, taskMode: TaskMode,
                         metrics: RawMetrics?, headYaw: Float?, now: Date) -> [PostureLogEvent] {
        let t = now.timeIntervalSince1970
        var out: [PostureLogEvent] = []

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
            out.append(event)
        }

        let taskName = taskMode.rawValue
        if taskName != lastTask {
            lastTask = taskName
            out.append(PostureLogEvent(t: t, kind: "task", value: taskName))
        }
        return out
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
                        wristSession: arrival.wristSession)
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

    init() {
        count = Self.dayFiles().reduce(0) { total, url in
            total + ((try? String(contentsOf: url, encoding: .utf8))?
                .split(separator: "\n").count ?? 0)
        }
    }

    func append(_ events: [PostureLogEvent]) {
        guard !events.isEmpty else { return }
        count += events.count
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
    func exportJSONL() throws -> URL {
        Self.flushPendingWrites()
        let joined = Self.dayFiles()
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined()
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("posture-log-to-\(dateKey(for: Date())).jsonl")
        try Data(joined.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Blocks until queued writes complete.
    nonisolated static func flushPendingWrites() {
        persistQueue.sync {}
    }

    private nonisolated static let persistQueue = DispatchQueue(label: "com.quant.postureLog.persist",
                                                                qos: .utility)

    private nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private nonisolated static func fileURL(for key: String) -> URL {
        documents.appendingPathComponent("posture-log-\(key).jsonl")
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
