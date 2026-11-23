import XCTest
import PostureLogic
@testable import PostureLogic   // for Pipeline.ingest, to hand the app's pipeline frames
@testable import Quant

/// The seat-change question on the Watch, answered with Recalibrate or Dismiss (2026-11-23). The
/// dictionaries are the golden copies the Watch's `SeatQuestionWatchTests` assert.
@MainActor
final class SeatChangeWatchTests: XCTestCase {

    private let key = "com.quant.seatChangeMode"
    private let start: TimeInterval = 1_791_640_000

    override func setUpWithError() throws { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDownWithError() throws { UserDefaults.standard.removeObject(forKey: key) }

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

    /// What the phone told the Watch, in order.
    private final class Told { var questions: [(open: Bool, id: TimeInterval)] = [] }

    private func askingModel(_ told: Told) -> AppModel {
        let model = AppModel()
        model.sendsSeatQuestion = { _, open, id in told.questions.append((open, id)); return .message }
        model.seatChangeMode = .ask
        return model
    }

    // MARK: - The messages

    func test_seatQuestionMessage_shape() {
        XCTAssertEqual(WatchConnectivityService.seatQuestionMessage(open: true, id: 1_791_640_030.5) as NSDictionary,
                       ["type": "seatQuestion", "open": true, "id": 1_791_640_030.5] as NSDictionary)
        XCTAssertEqual(WatchConnectivityService.seatQuestionMessage(open: false, id: 7) as NSDictionary,
                       ["type": "seatQuestion", "open": false, "id": 7.0] as NSDictionary)
    }

    func test_readsTheWatchsAnswer() {
        let a = WatchConnectivityService.seatAnswer(from: ["type": "seatAnswer", "answer": "recalibrate", "id": 12.5])
        XCTAssertEqual(a?.answer, .recalibrate)
        XCTAssertEqual(a?.id, 12.5)
        XCTAssertEqual(WatchConnectivityService.seatAnswer(
            from: ["type": "seatAnswer", "answer": "dismiss", "id": 3.0])?.answer, .dismiss)
    }

    func test_ignoresAMalformedAnswer() {
        XCTAssertNil(WatchConnectivityService.seatAnswer(from: ["type": "seatAnswer", "answer": "timeout", "id": 1.0]))
        XCTAssertNil(WatchConnectivityService.seatAnswer(from: ["type": "seatAnswer", "answer": "dismiss"]))
        XCTAssertNil(WatchConnectivityService.seatAnswer(from: ["type": "calibrate", "answer": "dismiss", "id": 1.0]))
    }

    func test_handlingTheMessage_passesTheAnswerOn() {
        let service = WatchConnectivityService()
        var got: [(SeatChangeOutcome, TimeInterval)] = []
        service.onSeatAnswer = { got.append(($0, $1)) }
        service.handleReceivedMessage(["type": "seatAnswer", "answer": "dismiss", "id": 9.0])
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.0, .dismiss)
        XCTAssertEqual(got.first?.1, 9.0)
    }

    // MARK: - Telling the Watch

    func test_askMode_tellsTheWatchOpenThenClosed() {
        let told = Told()
        let model = askingModel(told)
        driveNearMisses(model)
        let id = model.seatChangeQuestion?.suggestion.at
        XCTAssertNotNil(id)
        XCTAssertEqual(told.questions.count, 1)
        XCTAssertEqual(told.questions.first?.open, true)
        XCTAssertEqual(told.questions.first?.id, id)
        model.answerSeatChange(.dismiss)
        XCTAssertEqual(told.questions.count, 2)
        XCTAssertEqual(told.questions.last?.open, false)
        XCTAssertEqual(told.questions.last?.id, id)
    }

    func test_logOnly_tellsTheWatchNothing() {
        let told = Told()
        let model = AppModel()
        model.sendsSeatQuestion = { _, open, id in told.questions.append((open, id)); return .message }
        XCTAssertEqual(model.seatChangeMode, .logOnly)
        driveNearMisses(model)
        XCTAssertTrue(told.questions.isEmpty)
    }

    // MARK: - The Watch's answer

    func test_watchAnswer_matchingId_dismisses() {
        let model = askingModel(Told())
        driveNearMisses(model)
        let id = try! XCTUnwrap(model.seatChangeQuestion?.suggestion.at)
        model.receiveWatchSeatAnswer(.dismiss, id: id)
        XCTAssertEqual(model.pipeline.seatChangeClosed, .dismiss)
        XCTAssertNil(model.seatChangeQuestion)
    }

    func test_watchAnswer_matchingId_recalibrates() {
        let model = askingModel(Told())
        driveNearMisses(model)
        let id = try! XCTUnwrap(model.seatChangeQuestion?.suggestion.at)
        model.receiveWatchSeatAnswer(.recalibrate, id: id)
        XCTAssertTrue(model.needsCalibration)
        XCTAssertEqual(model.pipeline.seatChangeClosed, .recalibrate)
    }

    func test_lateWatchAnswer_isIgnored() {
        let model = askingModel(Told())
        // No question open. (A fresh model has no calibration, so compare, don't assume false.)
        let before = model.needsCalibration
        model.receiveWatchSeatAnswer(.recalibrate, id: 123)
        XCTAssertEqual(model.needsCalibration, before)
        XCTAssertNil(model.pipeline.seatChangeClosed)
        // A question open, an answer for another one.
        driveNearMisses(model)
        let id = try! XCTUnwrap(model.seatChangeQuestion?.suggestion.at)
        let beforeOpen = model.needsCalibration
        model.receiveWatchSeatAnswer(.recalibrate, id: id - 50)
        XCTAssertEqual(model.needsCalibration, beforeOpen)
        XCTAssertNil(model.pipeline.seatChangeClosed)
        XCTAssertNotNil(model.seatChangeQuestion)
    }

    // MARK: - Fix wave

    func test_seatQuestionRoute_mapsReachability() {
        typealias S = WatchConnectivityService
        XCTAssertEqual(S.seatQuestionRoute(isSupported: true, isPaired: true, isReachable: true), .message)
        XCTAssertEqual(S.seatQuestionRoute(isSupported: true, isPaired: true, isReachable: false), .queued)
        XCTAssertEqual(S.seatQuestionRoute(isSupported: true, isPaired: false, isReachable: false), .notPaired)
        XCTAssertEqual(S.seatQuestionRoute(isSupported: false, isPaired: true, isReachable: true), .notPaired)
        XCTAssertEqual(SeatQuestionDelivery.queued.rawValue, "queued")
        XCTAssertEqual(SeatQuestionDelivery.notPaired.rawValue, "notPaired")
    }

    func test_askedLine_carriesHowTheWatchWasTold() {
        let model = AppModel()
        model.sendsSeatQuestion = { _, _, _ in .queued }
        model.seatChangeMode = .ask
        driveNearMisses(model)
        XCTAssertEqual(model.lastSeatLine?.value, "asked")
        XCTAssertEqual(model.lastSeatLine?.via, "queued")
    }

    func test_replayInAsk_showsNoQuestion_andTellsWatchNothing() throws {
        let told = Told()
        let model = askingModel(told)
        model.startRecording()
        let url = try XCTUnwrap(model.stopRecording())
        defer { try? FileManager.default.removeItem(at: url) }
        try model.loadSession(url)

        model.startReplay()
        XCTAssertTrue(model.isReplaying)
        driveNearMisses(model)
        XCTAssertNil(model.seatChangeQuestion, "a recording's frames raise no question")
        XCTAssertTrue(told.questions.isEmpty)
        XCTAssertEqual(model.pipeline.seatChangeMode, .logOnly, "the pipeline only logs during a replay")
        XCTAssertEqual(model.seatChangeMode, .ask, "the setting itself is untouched")

        model.stopReplay()
        XCTAssertEqual(model.pipeline.seatChangeMode, .ask, "restored when the replay stops")
    }

    func test_recalibrateAnswer_withNoQuestion_doesNothing() {
        let model = AppModel()
        model.pipeline.baseline = Baseline(
            timestamp: Date(), shoulderMidpoint: SIMD3<Float>(0, 0, 0), headPosition: SIMD3<Float>(0, 1.0, 0),
            torsoAngle: 5, shoulderTwist: 2, shoulderWidth: 0.2, depthAvailable: false)
        model.needsCalibration = false
        XCTAssertNil(model.seatChangeQuestion)
        model.answerSeatChange(.recalibrate)
        XCTAssertNotNil(model.pipeline.baseline)
        XCTAssertFalse(model.needsCalibration)
    }
}
