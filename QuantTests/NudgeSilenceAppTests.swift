import XCTest
import PostureLogic
@testable import Quant

/// Silencing nudges for a while from the phone or the Watch, and no hourly cap (2026-10-05).
///
/// The phone decides every nudge, so it holds the silence: the Watch asks for one, and the phone
/// tells the Watch when it ends. It's kept across launches, on the calendar clock.
@MainActor
final class NudgeSilenceAppTests: XCTestCase {

    override func tearDown() async throws {
        AppModel().resumeNudges()
    }

    // MARK: - The Watch's messages (golden copies; the Watch's tests assert the same)

    func test_readsTheWatchsRequest() {
        XCTAssertEqual(WatchConnectivityService.silenceMinutes(from: ["type": "silenceNudges", "minutes": 30]), 30)
        XCTAssertEqual(WatchConnectivityService.silenceMinutes(from: ["type": "silenceNudges", "minutes": 0]), 0,
                       "0 resumes")
    }

    func test_ignoresAMalformedRequest() {
        XCTAssertNil(WatchConnectivityService.silenceMinutes(from: ["type": "silenceNudges"]))
        XCTAssertNil(WatchConnectivityService.silenceMinutes(from: ["type": "silenceNudges", "minutes": -5]))
        XCTAssertNil(WatchConnectivityService.silenceMinutes(from: ["type": "calibrate", "minutes": 30]))
    }

    func test_tellsTheWatchWhenTheSilenceEnds() {
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(WatchConnectivityService.nudgeSilenceMessage(until: until) as NSDictionary,
                       ["type": "nudgeSilence", "until": 1_800_000_000.0] as NSDictionary)
        XCTAssertEqual(WatchConnectivityService.nudgeSilenceMessage(until: nil) as NSDictionary,
                       ["type": "nudgeSilence", "until": 0.0] as NSDictionary, "not silenced")
    }

    // MARK: - On the phone

    func test_silencing_setsWhenItEnds_andReachesThePipeline() {
        let model = AppModel()
        let now = Date()
        model.silenceNudges(forMinutes: 30, now: now)
        XCTAssertEqual(model.nudgesSilencedUntil, now.addingTimeInterval(1800))
        XCTAssertEqual(model.pipelineNudgesSilencedUntil, now.addingTimeInterval(1800))
    }

    func test_resuming_endsTheSilence() {
        let model = AppModel()
        model.silenceNudges(forMinutes: 60)
        model.resumeNudges()
        XCTAssertNil(model.nudgesSilencedUntil)
        XCTAssertNil(model.pipelineNudgesSilencedUntil)
    }

    func test_aSilence_survivesARelaunch() {
        let model = AppModel()
        let now = Date()
        model.silenceNudges(forMinutes: 60, now: now)
        let relaunched = AppModel()
        XCTAssertEqual(relaunched.nudgesSilencedUntil?.timeIntervalSince1970 ?? 0,
                       now.addingTimeInterval(3600).timeIntervalSince1970, accuracy: 0.001)
    }

    func test_anEndedSilence_isForgottenAtLaunch() {
        let model = AppModel()
        model.silenceNudges(forMinutes: 30, now: Date().addingTimeInterval(-3600))
        XCTAssertNil(AppModel().nudgesSilencedUntil)
    }

    func test_theWatchsRequest_silencesOrResumes() {
        let model = AppModel()
        model.handleSilenceRequest(minutes: 120)
        XCTAssertNotNil(model.nudgesSilencedUntil)
        model.handleSilenceRequest(minutes: 0)
        XCTAssertNil(model.nudgesSilencedUntil)
    }

    func test_theOptions_are30MinutesTo2Hours() {
        XCTAssertEqual(AppModel.silenceOptionsMinutes, [30, 60, 120])
    }

    // MARK: - No hourly cap

    func test_byDefault_thereIsNoHourlyCap() {
        XCTAssertEqual(AppModel.defaultMaxNudgesPerHour, 0)
    }
}
