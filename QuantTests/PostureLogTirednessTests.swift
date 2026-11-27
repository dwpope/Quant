import XCTest
import PostureLogic
@testable import Quant

/// The posture log for the Front Face tiredness session (2026-11-27): the face's readings on the
/// metrics line, the movement median and time since a break in every mode, the camera mode on
/// the settings line, and the once-per-session mirror check.
@MainActor
final class PostureLogTirednessTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func metrics(movement: Float = 0) -> RawMetrics {
        RawMetrics(timestamp: 0, forwardCreep: 0, headDrop: 0, shoulderRounding: 0, lateralLean: 0,
                   twist: 0, movementLevel: movement, headMovementPattern: .still)
    }

    private func feed(_ recorder: inout PostureLogRecorder, state: PostureState = .good,
                      movement: Float = 0, at seconds: Double,
                      face: @escaping (TimeInterval, TimeInterval) -> FaceSignalSummary? = { _, _ in nil })
        -> [PostureLogEvent] {
        recorder.metricsEvents(state: state, metrics: metrics(movement: movement), face: face,
                               baselineTakenAt: t0.addingTimeInterval(-600),
                               headDropLine: 0.01875, forwardCreepLine: 0.06,
                               now: t0.addingTimeInterval(seconds))
    }

    private func summary(tracked: Float = 0.9) -> FaceSignalSummary {
        FaceSignalSummary(trackedShare: tracked, eyesClosedShare: 0.25, longBlinks: 2,
                          longestClosureMs: 450, yawns: 1, distanceLow: 0.4, distanceMedian: 0.5,
                          distanceHigh: 0.6)
    }

    func test_frontFaceWindow_carriesFaceFields() throws {
        var recorder = PostureLogRecorder()
        var out: [PostureLogEvent] = []
        for s in 0...10 { out += feed(&recorder, at: Double(s), face: { _, _ in self.summary() }) }
        let line = try XCTUnwrap(out.first { $0.kind == "metrics" })
        XCTAssertEqual(line.eyesClosedShare, 0.25)
        XCTAssertEqual(line.longBlinks, 2)
        XCTAssertEqual(line.longestClosureMs, 450)
        XCTAssertEqual(line.yawns, 1)
        XCTAssertEqual(line.faceTrackedShare, 0.9)
        XCTAssertEqual(line.faceDistanceLow, 0.4)
        XCTAssertEqual(line.faceDistanceMedian, 0.5)
        XCTAssertEqual(line.faceDistanceHigh, 0.6)
    }

    func test_front2DWindow_hasNoFaceFields() throws {
        var recorder = PostureLogRecorder()
        var out: [PostureLogEvent] = []
        for s in 0...10 { out += feed(&recorder, at: Double(s)) }
        let line = try XCTUnwrap(out.first { $0.kind == "metrics" })
        let json = String(decoding: try JSONEncoder().encode(line), as: UTF8.self)
        XCTAssertFalse(json.contains("eyesClosed"))
        XCTAssertFalse(json.contains("yawns"))
        XCTAssertFalse(json.contains("faceDistance"))
        XCTAssertFalse(json.contains("longBlinks"))
        XCTAssertFalse(json.contains("faceTracked"))
        XCTAssertTrue(json.contains("movementMedian"))
        XCTAssertTrue(json.contains("sinceBreakMinutes"))
    }

    func test_faceClosure_isCalledOnlyWhenALineIsBuilt_andWindowsTile() throws {
        var recorder = PostureLogRecorder()
        var calls: [(TimeInterval, TimeInterval)] = []
        let face: (TimeInterval, TimeInterval) -> FaceSignalSummary? = { calls.append(($0, $1)); return nil }
        var lines = 0
        for s in stride(from: 0.0, through: 31, by: 1) {
            lines += feed(&recorder, at: s, face: face).filter { $0.kind == "metrics" }.count
        }
        XCTAssertEqual(lines, calls.count)
        XCTAssertEqual(calls.count, 3)
        let base = t0.timeIntervalSince1970
        // The first window starts at its first frame; each next starts where the last ended.
        XCTAssertEqual(calls[0].0, base, accuracy: 1e-6)
        XCTAssertEqual(calls[0].1, base + 10, accuracy: 1e-6)
        for i in 1..<calls.count { XCTAssertEqual(calls[i].0, calls[i - 1].1, accuracy: 1e-9) }
        XCTAssertEqual(calls[2].1, base + 30, accuracy: 1e-6)
    }

    func test_movementMedian() throws {
        var recorder = PostureLogRecorder()
        var out: [PostureLogEvent] = []
        for (i, m) in [Float(0.1), 0.5, 0.3].enumerated() {
            out += feed(&recorder, movement: m, at: Double(i))
        }
        out += feed(&recorder, at: 10)
        let line = try XCTUnwrap(out.first { $0.kind == "metrics" })
        XCTAssertEqual(try XCTUnwrap(line.movementMedian), 0.3, accuracy: 1e-6)
    }

    private func sinceBreak(present: ClosedRange<Int>, absent: ClosedRange<Int>? = nil,
                            thenPresent: ClosedRange<Int>? = nil, readAt: Int) throws -> Float {
        var recorder = PostureLogRecorder()
        for s in stride(from: present.lowerBound, through: present.upperBound, by: 5) {
            _ = feed(&recorder, at: Double(s))
        }
        if let absent {
            for s in stride(from: absent.lowerBound, through: absent.upperBound, by: 5) {
                _ = feed(&recorder, state: .absent, at: Double(s))
            }
        }
        if let thenPresent {
            for s in stride(from: thenPresent.lowerBound, through: thenPresent.upperBound, by: 5) {
                _ = feed(&recorder, at: Double(s))
            }
        }
        // The window in progress is closed by a frame past 10 s from its start.
        let first = feed(&recorder, at: Double(readAt))
        let out = first + feed(&recorder, at: Double(readAt) + 11)
        return try XCTUnwrap(out.first { $0.kind == "metrics" }?.sinceBreakMinutes)
    }

    func test_sinceBreak_countsFromFirstJudgedFrame() throws {
        let minutes = try sinceBreak(present: 0...600, readAt: 600)
        XCTAssertEqual(minutes, 611.0 / 60, accuracy: 0.1)
    }

    func test_sinceBreak_notResetByThirtySecondsAway() throws {
        let minutes = try sinceBreak(present: 0...600, absent: 605...665, thenPresent: 670...700, readAt: 700)
        // The line is built by the frame 11 s after the read.
        XCTAssertEqual(minutes, 711.0 / 60, accuracy: 0.1)
    }

    func test_sinceBreak_resetsAfterTwoMinutesAway() throws {
        // Away 605...735 (130 s), back at 740.
        let minutes = try sinceBreak(present: 0...600, absent: 605...735, thenPresent: 740...800, readAt: 800)
        // Back at 740; the line is built at 811.
        XCTAssertEqual(minutes, 71.0 / 60, accuracy: 0.1)
    }

    /// Present frames every 5 s over `present`, absent ones over `absent`, then present ones from
    /// `back`; nothing in the gaps between. The minutes read on the line a frame after `back`.
    private func sinceBreakAfterGap(present: ClosedRange<Int>, absent: ClosedRange<Int>? = nil,
                                    back: Int) throws -> Float {
        var recorder = PostureLogRecorder()
        for s in stride(from: present.lowerBound, through: present.upperBound, by: 5) {
            _ = feed(&recorder, at: Double(s))
        }
        if let absent {
            for s in stride(from: absent.lowerBound, through: absent.upperBound, by: 5) {
                _ = feed(&recorder, state: .absent, at: Double(s))
            }
        }
        var out: [PostureLogEvent] = []
        for s in stride(from: back, through: back + 30, by: 5) { out += feed(&recorder, at: Double(s)) }
        return try XCTUnwrap(out.first { $0.kind == "metrics" }?.sinceBreakMinutes)
    }

    func test_sinceBreak_framelessGapOfTwoMinutesOrMore_isABreak() throws {
        // Stopped or locked: present to 600, next frame at 900, nothing between.
        let minutes = try sinceBreakAfterGap(present: 0...600, back: 900)
        XCTAssertLessThan(minutes, 1)
    }

    func test_sinceBreak_framelessGapUnderTwoMinutes_isNotABreak() throws {
        let minutes = try sinceBreakAfterGap(present: 0...600, back: 700)
        XCTAssertGreaterThan(minutes, 10)
    }

    func test_sinceBreak_gapPartlyAbsentPartlyFrameless_countsTogether() throws {
        // Absent 605...640 (35 s), no frames to 700, back at 700: 100 s since the last present
        // frame is under 2 minutes, so no break...
        let short = try sinceBreakAfterGap(present: 0...600, absent: 605...640, back: 700)
        XCTAssertGreaterThan(short, 10)
        // ... but absent 605...640 then nothing until 750: the frameless part is 110 s, under 2
        // minutes on its own, yet 150 s from the last present frame in all: a break.
        let long = try sinceBreakAfterGap(present: 0...600, absent: 605...640, back: 750)
        XCTAssertLessThan(long, 1)
    }

    func test_sinceBreak_framelessGapBeforeAbsentFrames_countsTowardsTheAbsence() throws {
        // Present to 600, nothing until 660, then absent 660...700 (100 s since 600 so far),
        // back at 725: 125 s since the last present frame.
        let minutes = try sinceBreakAfterGap(present: 0...600, absent: 660...700, back: 725)
        XCTAssertLessThan(minutes, 1)
    }

    func test_presenceNoted_withoutMetrics_alsoCountsAbsence() throws {
        var recorder = PostureLogRecorder()
        for s in stride(from: 0, through: 600, by: 5) { recorder.notePresence(.good, now: t0.addingTimeInterval(Double(s))) }
        for s in stride(from: 605, through: 735, by: 5) { recorder.notePresence(.absent, now: t0.addingTimeInterval(Double(s))) }
        _ = feed(&recorder, at: 740)
        let out = feed(&recorder, at: 751)
        XCTAssertEqual(try XCTUnwrap(out.first { $0.kind == "metrics" }?.sinceBreakMinutes), 0.2, accuracy: 0.2)
    }

    func test_settingsLine_carriesCamera_andChangesWithIt() throws {
        var recorder = PostureLogRecorder()
        let lines: [String: Float] = ["headDrop": 0.01875]
        let a = recorder.settingsEvents(lines, build: "1.0 (1)", camera: "front2D", now: t0)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a.first?.camera, "front2D")
        XCTAssertTrue(recorder.settingsEvents(lines, build: "1.0 (1)", camera: "front2D", now: t0.addingTimeInterval(1)).isEmpty)
        let b = recorder.settingsEvents(lines, build: "1.0 (1)", camera: "frontFace", now: t0.addingTimeInterval(2))
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.first?.camera, "frontFace")
    }

    // MARK: The mirror check, once per Front Face session

    private func nose(_ x: CGFloat, _ confidence: Float = 0.9) -> [Keypoint] {
        [Keypoint(joint: .nose, position: CGPoint(x: x, y: 0.4), confidence: confidence)]
    }

    func test_mirrorCheck_writesOneLineOnce() throws {
        var check = MirrorCheckSession()
        let line = try XCTUnwrap(check.consider(keypoints: nose(0.3), projected: (t: 100, x: 0.31),
                                                frameTime: 100.1, orientation: "landscape", now: t0))
        XCTAssertEqual(line.kind, "camera")
        XCTAssertEqual(line.value, "landscape")
        XCTAssertEqual(line.mirrorCheck, "matches")
        XCTAssertNil(check.consider(keypoints: nose(0.3), projected: (t: 100, x: 0.31),
                                    frameTime: 100.1, orientation: "landscape", now: t0))
    }

    func test_mirrorCheck_saysMirrored() throws {
        var check = MirrorCheckSession()
        let line = try XCTUnwrap(check.consider(keypoints: nose(0.3), projected: (t: 5, x: 0.7),
                                                frameTime: 5, orientation: "portrait", now: t0))
        XCTAssertEqual(line.mirrorCheck, "mirrored")
    }

    func test_mirrorCheck_waitsForANoseAndAFreshFace() {
        var check = MirrorCheckSession()
        XCTAssertNil(check.consider(keypoints: nose(0.3, 0.4), projected: (t: 5, x: 0.3), frameTime: 5, orientation: "portrait", now: t0))
        XCTAssertNil(check.consider(keypoints: [], projected: (t: 5, x: 0.3), frameTime: 5, orientation: "portrait", now: t0))
        XCTAssertNil(check.consider(keypoints: nose(0.3), projected: nil, frameTime: 5, orientation: "portrait", now: t0))
        XCTAssertNil(check.consider(keypoints: nose(0.3), projected: (t: 4.7, x: 0.3), frameTime: 5, orientation: "portrait", now: t0))
        XCTAssertNotNil(check.consider(keypoints: nose(0.3), projected: (t: 4.8, x: 0.3), frameTime: 5, orientation: "portrait", now: t0))
    }

    func test_mirrorCheck_centredReadingsForFiveMinutes_writeNothing() {
        var check = MirrorCheckSession()
        for s in stride(from: 0.0, through: 300, by: 0.1) {
            XCTAssertNil(check.consider(keypoints: nose(0.5), projected: (t: s, x: 0.5), frameTime: s,
                                        orientation: "portrait", now: t0.addingTimeInterval(s)))
        }
    }

    func test_mirrorCheck_offCentreAfterFiveMinutes_writesMatchesWithRawValues() throws {
        var check = MirrorCheckSession()
        for s in stride(from: 0.0, through: 300, by: 0.1) {
            _ = check.consider(keypoints: nose(0.5), projected: (t: s, x: 0.5), frameTime: s,
                               orientation: "portrait", now: t0.addingTimeInterval(s))
        }
        let line = try XCTUnwrap(check.consider(keypoints: nose(0.3), projected: (t: 301, x: 0.32), frameTime: 301,
                                                orientation: "portrait", now: t0.addingTimeInterval(301)))
        XCTAssertEqual(line.mirrorCheck, "matches")
        XCTAssertEqual(try XCTUnwrap(line.noseX), 0.3, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.noseY), 0.4, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(line.faceX), 0.32, accuracy: 1e-6)
    }

    func test_mirrorCheck_sixHundredSecondsOfCentred_writesUnclearOnceWithLastValues() throws {
        var check = MirrorCheckSession()
        var lines: [PostureLogEvent] = []
        for s in stride(from: 0.0, through: 700, by: 0.1) {
            let x = s >= 600 ? 0.52 : 0.5
            if let l = check.consider(keypoints: nose(CGFloat(x)), projected: (t: s, x: CGFloat(x)), frameTime: s,
                                      orientation: "portrait", now: t0.addingTimeInterval(s)) { lines.append(l) }
        }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.mirrorCheck, "unclear")
        XCTAssertEqual(try XCTUnwrap(lines.first?.noseX), 0.52, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(lines.first?.faceX), 0.52, accuracy: 1e-6)
        XCTAssertEqual(lines.first?.t, t0.addingTimeInterval(600).timeIntervalSince1970)
    }

    func test_mirrorCheck_unclearThenClear_writesTheClearOne() throws {
        var check = MirrorCheckSession()
        XCTAssertNil(check.consider(keypoints: nose(0.5), projected: (t: 5, x: 0.5), frameTime: 5, orientation: "portrait", now: t0))
        let line = try XCTUnwrap(check.consider(keypoints: nose(0.2), projected: (t: 5, x: 0.2), frameTime: 5, orientation: "portrait", now: t0))
        XCTAssertEqual(line.mirrorCheck, "matches")
    }

    func test_mirrorCheck_resetAllowsAnotherLine() {
        var check = MirrorCheckSession()
        _ = check.consider(keypoints: nose(0.3), projected: (t: 5, x: 0.3), frameTime: 5, orientation: "portrait", now: t0)
        check.reset()
        XCTAssertNil(check.consider(keypoints: nose(0.5), projected: (t: 5, x: 0.5), frameTime: 5, orientation: "portrait", now: t0.addingTimeInterval(2000)))
        XCTAssertNotNil(check.consider(keypoints: nose(0.3), projected: (t: 5, x: 0.3), frameTime: 5, orientation: "portrait", now: t0))
    }
}
