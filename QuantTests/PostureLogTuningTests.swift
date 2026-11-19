import XCTest
import PostureLogic
@testable import Quant

/// Lines that let a posture line be judged and tried again on a past session (2026-11-19).
///
/// The 11-18 review found the log couldn't say whether head drop's move to 0.01875 helped:
/// values were written only as a line was crossed (885 lines for about 64,200 frames), so every
/// reading sat by the line. It held no build, no lines in force and no calibration, and a fired
/// nudge's line had no numbers. These add a summary every 10 seconds of judged frames, the
/// numbers on a fire, the lines in force and the calibration.
@MainActor
final class PostureLogTuningTests: XCTestCase {

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

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func metrics(headDrop: Float = 0, creep: Float = 0, sink: Float = 0, lean: Float = 0,
                         twist: Float = 0, rounding: Float = 0) -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: creep, headDrop: headDrop, shoulderRounding: rounding,
                   lateralLean: abs(lean), twist: twist, movementLevel: 0, headMovementPattern: .still,
                   lateralLeanSigned: lean, shoulderSink: sink)
    }

    private func baseline(at date: Date, width: Float = 0.3, neck: Float = -0.21) -> Baseline {
        Baseline(timestamp: date, shoulderMidpoint: SIMD3<Float>(0.5, 0.6, 0), headPosition: .zero,
                 torsoAngle: 2, shoulderTwist: 1, shoulderWidth: width, depthAvailable: false,
                 neckHeight: neck, headYaw: -4)
    }

    // MARK: - The numbers on a fired nudge

    /// A fire's line says what the posture was as it fired and which repeat it was: the 11-18
    /// review had to guess both from the lines around it.
    func test_aFiredNudge_carriesTheNumbers_andWhichRepeatItIs() throws {
        var recorder = PostureLogRecorder()
        _ = recorder.events(state: .drifting(since: 0), decision: .pending(reason: .headDrop, timeRemaining: 1),
                            taskMode: .reading, metrics: metrics(headDrop: -0.02), headYaw: 0, now: t0)
        let fired = recorder.events(state: .drifting(since: 0), decision: .fire(reason: .headDrop),
                                    taskMode: .reading,
                                    metrics: metrics(headDrop: -0.021, creep: 0.03, sink: 0.01, lean: -0.04),
                                    headYaw: 5, nudgeRepeat: 2, now: t0.addingTimeInterval(1))
        let line = try XCTUnwrap(fired.first { $0.kind == "nudge" })
        XCTAssertEqual(line.value, "fire:headDrop")
        XCTAssertEqual(try XCTUnwrap(line.headDrop), -0.021, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.forwardCreep), 0.03, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.shoulderSink), 0.01, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.lateralShift), -0.04, accuracy: 1e-6)
        XCTAssertEqual(line.headYaw, 5)
        XCTAssertEqual(line.nudgeRepeat, 2)
    }

    /// Only a fire carries them: a pending line is written as the count starts, not as it ends.
    func test_aPendingNudge_carriesNoNumbers() throws {
        var recorder = PostureLogRecorder()
        let events = recorder.events(state: .drifting(since: 0), decision: .pending(reason: .headDrop, timeRemaining: 60),
                                     taskMode: .reading, metrics: metrics(headDrop: -0.02), headYaw: 0,
                                     nudgeRepeat: 0, now: t0)
        let line = try XCTUnwrap(events.first { $0.kind == "nudge" })
        XCTAssertNil(line.headDrop)
        XCTAssertNil(line.nudgeRepeat)
    }

    // MARK: - A summary of judged frames, every 10 seconds

    /// Ten seconds of judged frames, one a second: the head dips past 0.01875 for 3 of them.
    private func tenSeconds(_ recorder: inout PostureLogRecorder, headDropLine: Float = 0.01875) -> [PostureLogEvent] {
        let drops: [Float] = [-0.010, -0.012, -0.018, -0.019, -0.020, -0.0195, -0.015, -0.011, -0.009, -0.010]
        let creeps: [Float] = [0.07, 0.065, 0.05, 0.04, 0.03, 0.02, 0.01, 0, -0.01, -0.02]
        var out: [PostureLogEvent] = []
        for (i, drop) in drops.enumerated() {
            let past = -drop >= headDropLine
            out += recorder.metricsEvents(state: past ? .drifting(since: 0) : .good,
                                          metrics: metrics(headDrop: drop, creep: creeps[i],
                                                           sink: 0.02, lean: i == 5 ? -0.05 : 0.01,
                                                           twist: 3, rounding: 1),
                                          baselineTakenAt: t0.addingTimeInterval(-600),
                                          headDropLine: headDropLine, forwardCreepLine: 0.06,
                                          now: t0.addingTimeInterval(Double(i)))
        }
        return out + recorder.metricsEvents(state: .good, metrics: metrics(), baselineTakenAt: t0.addingTimeInterval(-600),
                                            headDropLine: headDropLine, forwardCreepLine: 0.06,
                                            now: t0.addingTimeInterval(10))
    }

    func test_judgedFrames_writeASummaryEach10Seconds() throws {
        var recorder = PostureLogRecorder()
        let lines = tenSeconds(&recorder)
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.kind, "metrics")
        XCTAssertEqual(line.value, "good", "what most frames were")
        XCTAssertEqual(line.t, 1_800_000_009, "at the last frame it sums up")
        XCTAssertEqual(line.over, 9)
        XCTAssertEqual(line.frames, 10)
        XCTAssertEqual(try XCTUnwrap(line.headDropLow), -0.020, accuracy: 1e-6, "the deepest dip")
        XCTAssertEqual(try XCTUnwrap(line.headDropMedian), -0.012, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.headDropHigh), -0.009, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.forwardCreepLow), -0.02, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.forwardCreepMedian), 0.03, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.forwardCreepHigh), 0.07, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.shoulderSinkHigh), 0.02, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.sideLeanHigh), 0.05, accuracy: 1e-6, "either way")
        XCTAssertEqual(try XCTUnwrap(line.twistHigh), 3, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.roundingHigh), 1, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.slouched), 2.7, accuracy: 1e-6, "3 of 10 frames over 9 s")
        XCTAssertEqual(line.baselineAge, 609, "seconds since calibrating, at the last frame")
    }

    /// Seconds past each of the lines tried so far, so a line can be tried on a past session
    /// without the phone: the readings at crossings could only say where the line was.
    func test_theSummary_saysHowLongTheHeadWasPastEachLine() throws {
        var recorder = PostureLogRecorder()
        let line = try XCTUnwrap(tenSeconds(&recorder).first)
        let past = try XCTUnwrap(line.headDropPast)
        XCTAssertEqual(past["0.015"], 4.5, "5 of 10 frames")
        XCTAssertEqual(past["0.0175"], 3.6)
        XCTAssertEqual(past["0.01875"], 2.7)
        XCTAssertEqual(past["0.02"], 0.9)
        XCTAssertEqual(past["0.0225"], 0)
        XCTAssertEqual(past["0.025"], 0)
        let creep = try XCTUnwrap(line.forwardCreepPast)
        XCTAssertEqual(creep["0.06"], 1.8, "past, as the engine has it: over the line, not on it")
        XCTAssertEqual(creep["0.07"], 0, "0.07 is on the line")
        XCTAssertEqual(creep["0.078"], 0)
        XCTAssertEqual(Set(creep.keys), ["0.06", "0.07", "0.078", "0.09", "0.1"])
    }

    /// A line set on the slider that isn't one of those is added, so the line in force is
    /// always there.
    func test_theLineInForce_isAlwaysSummedUp() throws {
        var recorder = PostureLogRecorder()
        let line = try XCTUnwrap(tenSeconds(&recorder, headDropLine: 0.01625).first)
        XCTAssertEqual(line.headDropPast?["0.01625"], 3.6)
    }

    func test_summaries_dontPutOffTheTick() {
        var recorder = PostureLogRecorder()
        _ = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(), headYaw: 0, now: t0)
        for second in stride(from: 0, through: 60, by: 5) {
            _ = recorder.metricsEvents(state: .good, metrics: metrics(), baselineTakenAt: t0,
                                       headDropLine: 0.01875, forwardCreepLine: 0.06,
                                       now: t0.addingTimeInterval(Double(second)))
        }
        let tick = recorder.events(state: .good, decision: .none, taskMode: .reading, metrics: metrics(),
                                   headYaw: 0, now: t0.addingTimeInterval(60))
        XCTAssertEqual(tick.map(\.kind), ["tick"])
    }

    // MARK: - The lines in force, and the build

    func test_theLinesInForce_areALine_atTheFirstFrame_onAChange_andEachDay() throws {
        var recorder = PostureLogRecorder()
        var thresholds = PostureThresholds()
        let first = recorder.settingsEvents(PostureLogRecorder.lines(of: thresholds), build: "1.0 (61)", now: t0)
        XCTAssertEqual(first.map(\.kind), ["settings"])
        XCTAssertEqual(first.first?.value, "1.0 (61)", "the build")
        XCTAssertEqual(first.first?.lines?["headDrop"], thresholds.headDropThreshold)

        XCTAssertEqual(recorder.settingsEvents(PostureLogRecorder.lines(of: thresholds), build: "1.0 (61)",
                                               now: t0.addingTimeInterval(1)), [])
        thresholds.headDropThreshold = 0.02
        let moved = recorder.settingsEvents(PostureLogRecorder.lines(of: thresholds), build: "1.0 (61)",
                                            now: t0.addingTimeInterval(2))
        XCTAssertEqual(moved.first?.lines?["headDrop"], 0.02)

        let nextDay = recorder.settingsEvents(PostureLogRecorder.lines(of: thresholds), build: "1.0 (61)",
                                              now: t0.addingTimeInterval(86_400))
        XCTAssertEqual(nextDay.map(\.kind), ["settings"], "each day's file reads on its own")
    }

    /// Every line the posture and nudge engines decide by.
    func test_theLinesInForce_nameEveryLineTheEnginesUse() {
        let lines = PostureLogRecorder.lines(of: PostureThresholds())
        for key in ["headDrop", "headDropMinForwardCreep", "forwardCreep", "sideLean", "twist",
                    "shoulderRounding", "shoulderSink", "reclinedSink", "reclineMaxForwardCreep",
                    "slouchSeconds", "driftGrace", "nudgeCooldown", "maxNudgesPerHour"] {
            XCTAssertNotNil(lines[key], key)
        }
        XCTAssertEqual(lines["slouchSeconds"], 60)
    }

    // MARK: - Calibration

    /// The baseline each calibration took, once, and again at the start of each day: two
    /// readings an 0.001 apart could be the body or the calibration pose, and nothing said which.
    func test_aCalibration_isALine_withItsBaseline_once() throws {
        var recorder = PostureLogRecorder()
        XCTAssertEqual(recorder.calibrationEvents(nil, now: t0), [], "none taken yet")

        let taken = baseline(at: t0.addingTimeInterval(-5))
        let lines = recorder.calibrationEvents(taken, now: t0)
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.kind, "calibration")
        XCTAssertEqual(line.baselineAge, 5)
        let numbers = try XCTUnwrap(line.baseline)
        XCTAssertEqual(try XCTUnwrap(numbers["shoulderWidth"]), 0.3, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(numbers["neckHeight"]), -0.21, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(numbers["headYaw"]), -4, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(numbers["shoulderY"]), 0.6, accuracy: 1e-6)

        XCTAssertEqual(recorder.calibrationEvents(taken, now: t0.addingTimeInterval(1)), [])
        XCTAssertEqual(recorder.calibrationEvents(baseline(at: t0.addingTimeInterval(30)),
                                                  now: t0.addingTimeInterval(30)).count, 1, "a new one")
        XCTAssertEqual(recorder.calibrationEvents(baseline(at: t0.addingTimeInterval(30)),
                                                  now: t0.addingTimeInterval(86_400)).count, 1, "a new day")
    }

    // MARK: - From the app

    private func todaysLines(_ kind: String) -> [PostureLogEvent] {
        PostureLogStore.events(dayKey: PostureLogStore.dayKey(for: Date())).filter { $0.kind == kind }
    }

    /// Calibrating is logged as calibrating, not as sitting well: with no baseline every number
    /// is 0, and the TODAY card drew calibration as good.
    func test_whileCalibrating_theStateLogged_isCalibrating() throws {
        let model = AppModel()
        model.needsCalibration = true
        model.logFrame(decision: .none)
        XCTAssertEqual(todaysLines("state").last?.value, "calibrating")
    }

    func test_theApp_logsItsBuild_andTheHeadDropLineInForce() throws {
        let model = AppModel()
        model.logFrame(decision: .none)
        let line = try XCTUnwrap(todaysLines("settings").last)
        XCTAssertFalse(line.value.isEmpty)
        XCTAssertEqual(line.lines?["headDrop"], model.headDropThreshold)
    }
}
