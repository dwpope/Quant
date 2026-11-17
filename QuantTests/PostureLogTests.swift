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

    // MARK: - Ticks and days (2026-10-16)

    /// A posture held writes a line a minute, with the numbers, so the timeline can tell sitting
    /// well for 25 minutes from the app having closed. Only changes were written before, and 10
    /// minutes of nothing was read as closed.
    func test_aPostureHeld_writesATickEachMinute() throws {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                            headYaw: 0, now: t0)
        XCTAssertEqual(recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                                       headYaw: 0, now: t0.addingTimeInterval(59)), [])
        let tick = recorder.events(state: .good, decision: .none, taskMode: .reading,
                                   metrics: metrics(creep: 0.03), headYaw: 0, now: t0.addingTimeInterval(60))
        XCTAssertEqual(tick.map(\.kind), ["tick"])
        XCTAssertEqual(tick.first?.value, "good")
        XCTAssertEqual(try XCTUnwrap(tick.first?.forwardCreep), 0.03, accuracy: 1e-6)
        XCTAssertEqual(recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                                       headYaw: 0, now: t0.addingTimeInterval(61)), [])
    }

    /// Any line counts as one: the next tick is a minute after the last line of any kind.
    func test_aChange_putsTheNextTickOff() {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                            headYaw: 0, now: t0)
        _ = recorder.events(state: .drifting(since: 1), decision: .pending(reason: .sink, timeRemaining: 60),
                            taskMode: .reading, metrics: metrics(), headYaw: 0, now: t0.addingTimeInterval(40))
        XCTAssertEqual(recorder.events(state: .drifting(since: 1), decision: .pending(reason: .sink, timeRemaining: 40),
                                       taskMode: .reading, metrics: metrics(), headYaw: 0,
                                       now: t0.addingTimeInterval(60)), [])
    }

    /// A day's file starts with where things stand, so the timeline reads each day on its own:
    /// a posture held over midnight wasn't in the new day's file at all.
    func test_aNewDay_startsWithTheStateTheDecisionAndTheTaskMode() {
        var recorder = PostureLogRecorder()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        recorder.calendar = utc
        let midnight = Date(timeIntervalSince1970: 1_800_057_600)   // 2027-01-16 00:00 UTC
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                            headYaw: 0, now: midnight.addingTimeInterval(-10))
        let newDay = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                                     headYaw: 0, now: midnight.addingTimeInterval(5))
        XCTAssertEqual(newDay.map(\.kind), ["state", "nudge", "task"])
        XCTAssertEqual(newDay.map(\.value), ["good", "none", "reading"])
    }

    // MARK: - Tracking (2026-11-17)

    private func frame(_ quality: TrackingQuality, conf: Float = 0.7, keypoints: Int = 17,
                       missing: String = "none") -> PostureLogRecorder.TrackingFrame {
        PostureLogRecorder.TrackingFrame(quality: quality, poseConfidence: conf, keypoints: keypoints,
                                         missing: missing)
    }

    /// Tracking good throughout says nothing: a well-tracked day's log is as it was.
    func test_trackingGoodThroughout_writesNoTrackingLine() {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for second in 0...25 {
            XCTAssertEqual(recorder.trackingEvents(frame(.good, conf: 0.9),
                                                   now: t0.addingTimeInterval(Double(second))), [])
        }
    }

    /// On its side (2026-11-16) tracking was mostly degraded, and the log couldn't say why. Each
    /// 10 seconds it isn't good throughout, a line sums up the debug panel's numbers over them.
    func test_trackingNotGood_writesALineEach10Seconds_withThePanelsNumbers() throws {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let frames = [frame(.good, conf: 0.80),
                      frame(.degraded, conf: 0.62),
                      frame(.degraded, conf: 0.60, missing: "LShldr"),
                      frame(.degraded, conf: 0.70, keypoints: 15),
                      frame(.degraded, conf: 0.64, keypoints: 13, missing: "LShldr,Head")]
        for (i, f) in frames.enumerated() {
            XCTAssertEqual(recorder.trackingEvents(f, now: t0.addingTimeInterval(Double(i) * 2)), [])
        }

        let lines = recorder.trackingEvents(frame(.good), now: t0.addingTimeInterval(10))
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.kind, "tracking")
        XCTAssertEqual(line.value, "degraded", "what most frames had")
        XCTAssertEqual(line.t, 1_800_000_008, "at the last frame it sums up")
        XCTAssertEqual(line.over, 8)
        XCTAssertEqual(line.framesGood, 1)
        XCTAssertEqual(line.framesDegraded, 4)
        XCTAssertEqual(line.framesLost, 0)
        XCTAssertEqual(try XCTUnwrap(line.poseConfLow), 0.60, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.poseConfMedian), 0.64, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.poseConfHigh), 0.80, accuracy: 1e-6)
        XCTAssertEqual(line.keypoints, 17)
        XCTAssertEqual(line.missing, "LShldr:2,Head:1", "frames without each joint, most first")
    }

    /// A frame without a pose is lost and has no confidence to sum up. Why there was no pose
    /// counts like a missing joint.
    func test_framesWithoutAPose_areLost_andLeftOutOfTheConfidence() throws {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let noPose = frame(.lost, conf: 0, keypoints: 0, missing: "no pose")
        _ = recorder.trackingEvents(noPose, now: t0)
        _ = recorder.trackingEvents(noPose, now: t0.addingTimeInterval(1))
        _ = recorder.trackingEvents(frame(.degraded, conf: 0.5, keypoints: 9, missing: "Head"),
                                    now: t0.addingTimeInterval(2))

        let line = try XCTUnwrap(recorder.trackingEvents(noPose, now: t0.addingTimeInterval(10)).first)
        XCTAssertEqual(line.value, "lost")
        XCTAssertEqual(line.framesLost, 2)
        XCTAssertEqual(line.framesDegraded, 1)
        XCTAssertEqual(try XCTUnwrap(line.poseConfLow), 0.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.poseConfMedian), 0.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.poseConfHigh), 0.5, accuracy: 1e-6)
        XCTAssertEqual(line.keypoints, 9)
        XCTAssertEqual(line.missing, "no pose:2,Head:1")

        let noneSeen = try XCTUnwrap(recorder.trackingEvents(noPose, now: t0.addingTimeInterval(20)).first)
        XCTAssertNil(noneSeen.poseConfMedian, "no pose in 10 seconds, no confidence")
        XCTAssertNil(noneSeen.keypoints)
    }

    /// With as many frames good as not, the line says the worse.
    func test_aTie_isTheWorse() throws {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = recorder.trackingEvents(frame(.good), now: t0)
        _ = recorder.trackingEvents(frame(.degraded), now: t0.addingTimeInterval(1))
        let line = try XCTUnwrap(recorder.trackingEvents(frame(.good), now: t0.addingTimeInterval(10)).first)
        XCTAssertEqual(line.value, "degraded")
    }

    /// With the app in the background, frames stop. The line ends at the last frame before,
    /// not when frames come again.
    func test_aGapInFrames_endsTheLineAtItsLastFrame() throws {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = recorder.trackingEvents(frame(.degraded), now: t0)
        _ = recorder.trackingEvents(frame(.degraded), now: t0.addingTimeInterval(3))
        let line = try XCTUnwrap(recorder.trackingEvents(frame(.good), now: t0.addingTimeInterval(600)).first)
        XCTAssertEqual(line.t, 1_800_000_003)
        XCTAssertEqual(line.over, 3)
    }

    /// A tracking line doesn't say the state, so it doesn't put off the minute's tick.
    func test_trackingLines_dontPutOffTheTick() {
        var recorder = PostureLogRecorder()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                            headYaw: 0, now: t0)
        for second in stride(from: 0, through: 60, by: 5) {
            _ = recorder.trackingEvents(frame(.degraded), now: t0.addingTimeInterval(Double(second)))
        }
        let tick = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                                   headYaw: 0, now: t0.addingTimeInterval(60))
        XCTAssertEqual(tick.map(\.kind), ["tick"])
    }

    private func trackingLines() -> [PostureLogEvent] {
        PostureLogStore.events(dayKey: PostureLogStore.dayKey(for: Date())).filter { $0.kind == "tracking" }
    }

    /// The numbers are the debug panel's, from the first camera frame on. Before it the panel's
    /// Missing is empty, and there's nothing to sum up.
    func test_theTrackingLine_isTheDebugPanelsNumbers() throws {
        let model = AppModel()
        let t0 = Date()
        model.trackingQuality = .degraded
        model.logFrame(decision: .none, now: t0)
        model.logFrame(decision: .none, now: t0.addingTimeInterval(10))
        XCTAssertEqual(trackingLines(), [], "no camera frame yet")

        model.poseConfidence = 0.61
        model.poseKeypointCount = 17
        model.missingCriticalJoints = "none"
        model.logFrame(decision: .none, now: t0.addingTimeInterval(20))
        model.logFrame(decision: .none, now: t0.addingTimeInterval(30))
        let line = try XCTUnwrap(trackingLines().first)
        XCTAssertEqual(line.value, "degraded")
        XCTAssertEqual(try XCTUnwrap(line.poseConfMedian), 0.61, accuracy: 1e-6)
        XCTAssertEqual(line.keypoints, 17)
        XCTAssertNil(line.missing, "no joint missing")
    }

    // MARK: - Replays (2026-10-16)

    /// A replayed recording isn't your posture today: its frames aren't logged, or the TODAY
    /// card would draw its slouches and nudges as real.
    func test_aReplay_isNotLogged() throws {
        let model = AppModel()
        model.startRecording()
        let url = try XCTUnwrap(model.stopRecording())
        defer { try? FileManager.default.removeItem(at: url) }
        try model.loadSession(url)

        model.startReplay()
        let before = model.postureLogStore.count
        model.logFrame(decision: .fire(reason: .sink))
        XCTAssertEqual(model.postureLogStore.count, before, "a replay's nudge isn't logged")

        model.stopReplay()
        model.logFrame(decision: .fire(reason: .sink))
        XCTAssertEqual(model.postureLogStore.count, before + 1, "a live one is")
    }

    /// A recording `seconds` long, saved where `loadSession` reads it from.
    private func recording(seconds: Double) throws -> URL {
        let samples = stride(from: 0.0, through: seconds, by: 0.1).map { t in
            PoseSample(timestamp: 1_000 + t, depthMode: .twoDOnly,
                       headPosition: SIMD3<Float>(0, 1, 0), shoulderMidpoint: .zero,
                       leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
                       torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2, shoulderWidthRaw: 0.2,
                       trackingQuality: .good)
        }
        let session = RecordedSession(
            id: UUID(), startTime: Date(timeIntervalSince1970: 1_800_000_000),
            endTime: Date(timeIntervalSince1970: 1_800_000_000 + seconds), samples: samples, tags: [],
            metadata: SessionMetadata(deviceModel: "test", depthAvailable: false, thresholds: PostureThresholds()))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID()).json")
        try encoder.encode(session).write(to: url)
        return url
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// A replay is one until the recording ends (2026-10-19 review). Starting playback returns
    /// straight away, and the app took that for the end: `isReplaying` went false on the next
    /// turn of the main thread, and a playing recording was logged as today's posture after all.
    func test_aReplay_isAReplay_whileTheRecordingPlays() async throws {
        let url = try recording(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel()
        try model.loadSession(url)

        model.startReplay()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.isReplaying, "ten seconds of recording, still playing")
        let before = model.postureLogStore.count
        model.logFrame(decision: .fire(reason: .sink))
        XCTAssertEqual(model.postureLogStore.count, before)
        model.stopReplay()
    }

    /// It ends when the recording does.
    func test_aReplay_endsWithTheRecording() async throws {
        let url = try recording(seconds: 0.3)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel()
        try model.loadSession(url)

        model.startReplay()
        try await waitFor { !model.isReplaying }
        XCTAssertFalse(model.isReplaying)
    }

    /// A replay stopped and started again stays a replay: the first one ending doesn't end it.
    func test_aReplayStartedAgain_isNotEndedByTheFirst() async throws {
        let url = try recording(seconds: 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = AppModel()
        try model.loadSession(url)

        model.startReplay()
        try await Task.sleep(for: .milliseconds(100))
        model.stopReplay()
        model.startReplay()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(model.isReplaying)
        model.stopReplay()
    }

    // MARK: - On disk and in the export

    func test_linesAreKept_andCountedAfterARelaunch() {
        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 1, kind: "state", value: "good"),
                      PostureLogEvent(t: 2, kind: "state", value: "drifting")])
        PostureLogStore.flushPendingWrites()
        XCTAssertEqual(PostureLogStore().count, 2)
    }

    nonisolated final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Bool?
        func set(_ v: Bool) { lock.lock(); _value = v; lock.unlock() }
        var value: Bool? { lock.lock(); defer { lock.unlock() }; return _value }
    }

    /// Counting again after older days are deleted reads the files off the main thread
    /// (2026-10-16 audit): it read every day's file there, and the screen waited.
    func test_aRecount_readsOffTheMainThread() async {
        let store = PostureLogStore()
        let onMain = Flag()
        await store.recount(counting: { onMain.set(Thread.isMainThread); return 7 })
        XCTAssertEqual(store.count, 7)
        XCTAssertEqual(onMain.value, false)
    }

    /// Lines added while the files are being counted aren't lost from the count.
    func test_linesAddedDuringARecount_stayCounted() async throws {
        let store = PostureLogStore()
        let counting = Flag()
        let go = DispatchSemaphore(value: 0)
        let recount = Task { await store.recount(counting: { counting.set(true); go.wait(); return 7 }) }
        let deadline = Date().addingTimeInterval(5)
        while counting.value == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }

        store.append([PostureLogEvent(t: 1, kind: "state", value: "good"),
                      PostureLogEvent(t: 2, kind: "state", value: "drifting")])
        go.signal()
        await recount.value
        XCTAssertEqual(store.count, 9)
    }

    /// Preparing the export leaves the screen free while the files are being counted (2026-10-16
    /// audit): it waited on the main thread for the count to finish, then read every day there.
    func test_theExport_waitsOffTheMainThread() async throws {
        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 1, kind: "state", value: "good")])
        let counting = Flag()
        let go = DispatchSemaphore(value: 0)
        let recount = Task {
            await store.recount(counting: { counting.set(true); _ = go.wait(timeout: .now() + 2); return 1 })
        }
        let deadline = Date().addingTimeInterval(5)
        while counting.value == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }

        let asked = Date()
        let export = Task { try await store.exportJSONL() }
        try await Task.sleep(for: .milliseconds(50))
        let heldFor = Date().timeIntervalSince(asked)
        go.signal()
        let url = try await export.value
        await recount.value

        XCTAssertLessThan(heldFor, 1, "the main thread was free while the count went on")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 1)
    }

    func test_theExport_holdsEveryDay_oneLinePerEvent() async throws {
        let yesterday = Date().addingTimeInterval(-86_400)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
        let key = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        let old = String(data: try JSONEncoder().encode(PostureLogEvent(t: 1, kind: "state", value: "bad")),
                         encoding: .utf8)! + "\n"
        try Data(old.utf8).write(to: documents.appendingPathComponent("posture-log-\(key).jsonl"))

        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 2, kind: "nudge", value: "fire:sink")])
        PostureLogStore.flushPendingWrites()

        let url = try await store.exportJSONL()
        XCTAssertTrue(url.lastPathComponent.hasPrefix("posture-log-to-"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let values = try lines.map { try JSONDecoder().decode(PostureLogEvent.self, from: Data($0.utf8)).value }
        XCTAssertEqual(values, ["bad", "fire:sink"])
    }
}
