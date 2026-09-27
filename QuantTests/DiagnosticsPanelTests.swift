import XCTest
import PostureLogic
@testable import Quant

/// The rules behind the main screen's diagnostics panel.
///
/// Found on an iPhone 15 Pro on 2026-09-26: a tester could not recalibrate. The panel had no way
/// to collapse and no height limit, so with Jev results showing it pushed the bottom row, and the
/// Recalibrate button in it, off the screen. While calibration was pending it also drew over the
/// calibration screen and hid it completely, so the tester never saw the countdown.
final class DiagnosticsPanelTests: XCTestCase {

    // MARK: - Details visibility

    func test_details_showWhenExpandedAndCalibrated() {
        XCTAssertTrue(DiagnosticsPanel.showsDetails(isExpanded: true, needsCalibration: false))
    }

    func test_details_hideWhenCollapsed() {
        XCTAssertFalse(DiagnosticsPanel.showsDetails(isExpanded: false, needsCalibration: false))
    }

    /// The calibration screen sits underneath this panel. Expanded, the panel covered it.
    func test_details_hideWhileCalibrating_evenWhenExpanded() {
        XCTAssertFalse(DiagnosticsPanel.showsDetails(isExpanded: true, needsCalibration: true))
    }

    // MARK: - Calibration line

    /// Calibration only starts once tracking is good, and the calibration screen does not say
    /// so. The panel's top line is the one place a stuck tester can see why nothing is happening.
    func test_waiting_namesTheTrackingThatIsBlockingIt() {
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .waiting, tracking: .lost),
            "Calibrating · tracking lost")
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .waiting, tracking: .degraded),
            "Calibrating · tracking degraded")
    }

    /// "Degraded" sounds good enough. It is not, so the hint says what calibration is waiting for.
    func test_waiting_onTracking_hasAHint() {
        XCTAssertEqual(
            DiagnosticsPanel.calibrationHint(status: .waiting, tracking: .lost),
            "starts once tracking is good")
        XCTAssertEqual(
            DiagnosticsPanel.calibrationHint(status: .waiting, tracking: .degraded),
            "starts once tracking is good")
    }

    func test_waiting_withGoodTracking_isAboutToStart_andNeedsNoHint() {
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .waiting, tracking: .good),
            "Calibrating · starting")
        XCTAssertNil(DiagnosticsPanel.calibrationHint(status: .waiting, tracking: .good))
    }

    func test_noHint_onceCalibrationIsUnderway() {
        let statuses: [CalibrationStatus] = [
            .countdown(3), .sampling, .validating, .success, .failed("x"),
        ]
        for status in statuses {
            XCTAssertNil(DiagnosticsPanel.calibrationHint(status: status, tracking: .lost),
                         "\(status) should not show a hint")
        }
    }

    func test_inProgressStates_sayWhatToDo() {
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .countdown(3), tracking: .good),
            "Calibrating · starts in 3")
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .sampling, tracking: .good),
            "Calibrating · hold still")
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .validating, tracking: .good),
            "Calibrating · checking")
    }

    func test_endStates() {
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .success, tracking: .good),
            "Calibrated")
        XCTAssertEqual(
            DiagnosticsPanel.calibrationLine(status: .failed("moved"), tracking: .good),
            "Calibration failed · tap Try Again")
    }

    /// A monospaced caption line this long still fits beside the panel's edges on an iPhone SE.
    func test_everyCalibrationLine_fitsOnOneLine() {
        let statuses: [CalibrationStatus] = [
            .waiting, .countdown(10), .sampling, .validating, .success, .failed("x"),
        ]
        for status in statuses {
            for tracking in [TrackingQuality.lost, .degraded, .good] {
                let line = DiagnosticsPanel.calibrationLine(status: status, tracking: tracking)
                XCTAssertLessThanOrEqual(line.count, 40, "\"\(line)\" is too long for one line")
                if let hint = DiagnosticsPanel.calibrationHint(status: status, tracking: tracking) {
                    XCTAssertLessThanOrEqual(hint.count, 40, "\"\(hint)\" is too long for one line")
                }
            }
        }
    }
}
