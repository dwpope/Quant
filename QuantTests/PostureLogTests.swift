import XCTest
import PostureLogic
@testable import Quant

/// A log of what posture and nudges did, for a real-use hour (2026-10-07).
///
/// Dave worked for an hour, saw a countdown, and got no nudge. Nothing recorded why. The log keeps
/// one line per change: the posture state (with the numbers behind it), the nudge decision (with
/// its reason), and the task mode. It goes into its own export, so the next real-use hour can be
/// read back instead of guessed at.
@MainActor
final class PostureLogTests: XCTestCase {

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    private func clean() {
        PostureLogStore.flushPendingWrites()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        where name.hasPrefix("posture-log-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }
    override func setUpWithError() throws { clean() }
    override func tearDownWithError() throws { clean() }

    private func metrics(creep: Float = 0.08, sink: Float = 0.01) -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: creep, headDrop: -0.02, shoulderRounding: 0, lateralLean: 0.01,
                   twist: 0, movementLevel: 0, headMovementPattern: .still, shoulderSink: sink)
    }

    // MARK: - What's worth a line

    func test_theFirstFrame_logsTheState_theDecision_andTheTaskMode() {
        var recorder = PostureLogRecorder()
        let events = recorder.events(state: .good, decision: .none, taskMode: .reading,
                                     metrics: metrics(), headYaw: 2, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(events.map(\.kind), ["state", "nudge", "task"])
        XCTAssertEqual(events.map(\.value), ["good", "none", "reading"])
        XCTAssertEqual(events.first?.t, 1_800_000_000)
    }

    func test_nothingChanged_nothingLogged() {
        var recorder = PostureLogRecorder()
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        XCTAssertEqual(recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                                       headYaw: 0, now: Date()), [])
    }

    /// The countdown ticks every frame; only a change of kind or reason is a line.
    func test_aCountdownTicking_isNotALine() {
        var recorder = PostureLogRecorder()
        _ = recorder.events(state: .drifting(since: 1), decision: .pending(reason: .sustainedSlouch, timeRemaining: 100),
                            taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        let next = recorder.events(state: .drifting(since: 1),
                                   decision: .pending(reason: .sustainedSlouch, timeRemaining: 99),
                                   taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        XCTAssertEqual(next, [])
    }

    /// A state change carries the numbers behind it, so the log says why.
    func test_aStateChange_carriesTheNumbers() throws {
        var recorder = PostureLogRecorder()
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        let events = recorder.events(state: .drifting(since: 5), decision: .pending(reason: .sink, timeRemaining: 120),
                                     taskMode: .reading, metrics: metrics(creep: -0.05, sink: 0.11), headYaw: 3, now: Date())
        let state = try XCTUnwrap(events.first { $0.kind == "state" })
        XCTAssertEqual(state.value, "drifting")
        XCTAssertEqual(try XCTUnwrap(state.shoulderSink), 0.11, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(state.forwardCreep), -0.05, accuracy: 1e-6)
        XCTAssertEqual(state.headYaw, 3)
        let nudge = try XCTUnwrap(events.first { $0.kind == "nudge" })
        XCTAssertEqual(nudge.value, "pending:sink")
        XCTAssertEqual(nudge.remaining, 120)
    }

    func test_aNudgeAndWhatHeldItBack_areLines() {
        var recorder = PostureLogRecorder()
        _ = recorder.events(state: .bad(since: 0), decision: .pending(reason: .sustainedSlouch, timeRemaining: 1),
                            taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        let fired = recorder.events(state: .bad(since: 0), decision: .fire(reason: .sustainedSlouch),
                                    taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        XCTAssertEqual(fired.map(\.value), ["fire:sustainedSlouch"])
        let held = recorder.events(state: .bad(since: 0), decision: .suppressed(reason: .cooldownActive),
                                   taskMode: .reading, metrics: metrics(), headYaw: 0, now: Date())
        XCTAssertEqual(held.map(\.value), ["suppressed:cooldownActive"])
    }

    // MARK: - On disk and in the export

    func test_linesAreKept_andCountedAfterARelaunch() {
        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 1, kind: "state", value: "good"),
                      PostureLogEvent(t: 2, kind: "state", value: "drifting")])
        PostureLogStore.flushPendingWrites()
        XCTAssertEqual(PostureLogStore().count, 2)
    }

    func test_theExport_holdsEveryDay_oneLinePerEvent() throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
        let key = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        let old = String(data: try JSONEncoder().encode(PostureLogEvent(t: 1, kind: "state", value: "bad")),
                         encoding: .utf8)! + "\n"
        try Data(old.utf8).write(to: documents.appendingPathComponent("posture-log-\(key).jsonl"))

        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 2, kind: "nudge", value: "fire:sink")])
        PostureLogStore.flushPendingWrites()

        let url = try store.exportJSONL()
        XCTAssertTrue(url.lastPathComponent.hasPrefix("posture-log-to-"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let values = try lines.map { try JSONDecoder().decode(PostureLogEvent.self, from: Data($0.utf8)).value }
        XCTAssertEqual(values, ["bad", "fire:sink"])
    }
}
