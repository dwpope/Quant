import XCTest
import PostureLogic
@testable import Quant

/// Where the phone sits, and the head-turn timer on the Watch (2026-10-05).
///
/// Every posture rule assumes the phone is in front of you. In session 6 it sat about 50° to one
/// side: sitting normally read as a head turn, and turning the chair towards the phone read as a
/// slouch. The panel now says so after calibrating, and the Watch shows the phone's head-turn
/// timer, so a head turn can be seen registering.
@MainActor
final class PhonePositionTests: XCTestCase {

    func test_aPhoneInFront_saysNothing() {
        XCTAssertNil(DiagnosticsPanel.phoneOffCentreLine(baselineHeadYaw: nil))
        XCTAssertNil(DiagnosticsPanel.phoneOffCentreLine(baselineHeadYaw: 0))
        XCTAssertNil(DiagnosticsPanel.phoneOffCentreLine(baselineHeadYaw: 15))
        XCTAssertNil(DiagnosticsPanel.phoneOffCentreLine(baselineHeadYaw: -20))
    }

    func test_aPhoneWellToOneSide_saysMoveIt() throws {
        let line = try XCTUnwrap(DiagnosticsPanel.phoneOffCentreLine(baselineHeadYaw: 50))
        XCTAssertTrue(line.contains("50°"), line)
        XCTAssertTrue(line.contains("in front of you"), line)
        XCTAssertTrue(try XCTUnwrap(DiagnosticsPanel.phoneOffCentreLine(baselineHeadYaw: -35)).contains("35°"))
    }

    // MARK: - The head-turn timer on the Watch (golden copy; the Watch's tests read the same)

    private func status(headTurnedSince: TimeInterval?) -> JevRemote.Status {
        JevRemote.Status(
            enabled: true, calibrated: true, tracking: "good", thresholdState: "good",
            thresholdSince: nil, notice: nil, lastRecord: nil, judgedCount: 0, total: 0,
            trueClassOptions: [], attempts: 0, captureDelay: 3, headTurnedSince: headTurnedSince)
    }

    func test_theStatus_saysWhenTheHeadTurnBegan() {
        XCTAssertEqual(status(headTurnedSince: 1_800_000_000).message["headTurned"] as? Double, 1_800_000_000)
    }

    func test_theStatus_leavesItOut_whenTheHeadIsNotTurned() {
        XCTAssertNil(status(headTurnedSince: nil).message["headTurned"])
    }

    /// The pipeline's start is a frame time; the Watch counts up from a calendar time.
    func test_aFrameTimeBecomesACalendarTime_measuredFrameToFrame() {
        let wallNow = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(DriftClock.wallClock(of: 670_600, frameNow: 670_630, wallNow: wallNow),
                       wallNow.addingTimeInterval(-30))
        XCTAssertNil(DriftClock.wallClock(of: 670_600, frameNow: nil, wallNow: wallNow))
    }
}
