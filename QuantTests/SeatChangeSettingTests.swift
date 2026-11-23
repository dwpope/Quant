import XCTest
import PostureLogic
@testable import PostureLogic   // for Pipeline.ingest, to hand the app's pipeline frames
@testable import Quant

/// The seat-change setting (log only by default), the phone's question, and its two answers
/// (2026-11-23).
@MainActor
final class SeatChangeSettingTests: XCTestCase {

    private let key = "com.quant.seatChangeMode"
    private let start: TimeInterval = 1_791_640_000

    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    private func clean() {
        PostureLogStore.flushPendingWrites()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        where name.hasPrefix("posture-log-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: key)
        clean()
    }
    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: key)
        clean()
    }

    // MARK: - Driving the app's pipeline (the package's PipelineSeatChangeTests approach)

    private func sample(at t: TimeInterval, neck: Float = 0) -> PoseSample {
        PoseSample(
            timestamp: t, depthMode: .twoDOnly,
            headPosition: SIMD3<Float>(0, 1.0, 0), shoulderMidpoint: SIMD3<Float>(0, 0, 0),
            leftShoulder: SIMD3<Float>(-0.5, 0, 0), rightShoulder: SIMD3<Float>(0.5, 0, 0),
            torsoAngle: 5, headForwardOffset: 0.01, shoulderTwist: 2,
            shoulderWidthRaw: 0.2, trackingQuality: .good, headYaw: 0, neckHeight: neck)
    }

    private func run(_ pipeline: Pipeline, from: TimeInterval, for seconds: TimeInterval,
                     neck: Float = 0) -> TimeInterval {
        let frames = Int((seconds * 10).rounded())
        for i in 0..<frames {
            let t = from + Double(i) / 10
            pipeline.ingest(sample(at: t, neck: neck), quality: .good, at: t)
        }
        return from + Double(frames) / 10
    }

    /// Calibrated on the "good" sample, then five brief head-drop near-misses.
    private func driveNearMisses(_ model: AppModel) {
        let pipeline = model.pipeline
        pipeline.baseline = Baseline(
            timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0, 0, 0), headPosition: SIMD3<Float>(0, 1.0, 0),
            torsoAngle: 5, shoulderTwist: 2, shoulderWidth: 0.2, depthAvailable: false)
        var t = run(pipeline, from: start, for: 3)
        for _ in 0..<5 {
            t = run(pipeline, from: t, for: 4, neck: 0.024)
            t = run(pipeline, from: t, for: 6)
        }
    }

    // MARK: - The setting

    func test_defaultMode_isLogOnly() {
        let model = AppModel()
        XCTAssertEqual(model.seatChangeMode, .logOnly)
        XCTAssertEqual(model.pipeline.seatChangeMode, .logOnly)
    }

    func test_mode_persists_andReachesPipeline() {
        let model = AppModel()
        model.seatChangeMode = .ask
        XCTAssertEqual(model.pipeline.seatChangeMode, .ask)
        let fresh = AppModel()
        XCTAssertEqual(fresh.seatChangeMode, .ask)
        XCTAssertEqual(fresh.pipeline.seatChangeMode, .ask)
    }

    // MARK: - The question and its answers

    func test_question_reachesTheAppModel_inAsk() {
        let model = AppModel()
        model.seatChangeMode = .ask
        driveNearMisses(model)
        XCTAssertNotNil(model.seatChangeQuestion)
    }

    func test_dismiss_closesPipelineQuestion() {
        let model = AppModel()
        model.seatChangeMode = .ask
        driveNearMisses(model)
        XCTAssertNotNil(model.seatChangeQuestion)
        model.answerSeatChange(.dismiss)
        XCTAssertEqual(model.pipeline.seatChangeClosed, .dismiss)
        XCTAssertNil(model.seatChangeQuestion)
    }

    func test_recalibrate_startsCalibration() {
        let model = AppModel()
        model.seatChangeMode = .ask
        driveNearMisses(model)
        XCTAssertNotNil(model.seatChangeQuestion)
        model.answerSeatChange(.recalibrate)
        XCTAssertTrue(model.needsCalibration)
        XCTAssertEqual(model.pipeline.seatChangeClosed, .recalibrate)
        XCTAssertNil(model.seatChangeQuestion)
    }

    func test_answerWithNoQuestion_doesNothing() {
        let model = AppModel()
        model.answerSeatChange(.dismiss)
        XCTAssertNil(model.pipeline.seatChangeClosed)
    }

    // MARK: - Log only

    func test_logOnlySuggestion_reachesPostureLog() throws {
        let model = AppModel()
        XCTAssertEqual(model.seatChangeMode, .logOnly)
        driveNearMisses(model)
        XCTAssertNil(model.seatChangeQuestion)
        PostureLogStore.flushPendingWrites()
        let lines = try (FileManager.default.contentsOfDirectory(atPath: documents.path))
            .filter { $0.hasPrefix("posture-log-") }
            .flatMap { name -> [String] in
                let text = try String(contentsOf: documents.appendingPathComponent(name), encoding: .utf8)
                return text.split(separator: "\n").map(String.init)
            }
        XCTAssertTrue(lines.contains { $0.contains("\"kind\":\"seat\"") && $0.contains("\"value\":\"would-ask\"") },
                      "no would-ask seat line in \(lines.count) lines")
    }
}
