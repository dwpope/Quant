import PostureLogic

/// Rules for the main screen's diagnostics panel, kept out of the view so they can be tested.
///
/// The panel is the only on-screen place Recalibrate lives, so it must never be pushed off the
/// screen or hide the calibration screen underneath it. Both happened on an iPhone 15 Pro on
/// 2026-09-26, and a tester could not recalibrate at all.
enum DiagnosticsPanel {

    /// How far the head may be turned from the phone while calibrating before the panel asks you
    /// to move the phone. Earlier sessions calibrated at 0 to 5°; session 6 at about 50°.
    static let phoneOffCentreLimit: Float = 20

    /// A warning when you calibrated looking well to one side of the phone, or nil.
    ///
    /// Every posture rule assumes the phone is in front of you. From 50° off, turning the chair
    /// towards it reads as a slouch (session 6, 2026-10-05). Head turns are measured from the
    /// calibrated angle, but the shoulders can't be.
    static func phoneOffCentreLine(baselineHeadYaw: Float?) -> String? {
        guard let yaw = baselineHeadYaw, abs(yaw) > phoneOffCentreLimit else { return nil }
        return "The phone is about \(Int(abs(yaw).rounded()))° to one side of where you look. "
            + "Put it in front of you, below your screen, then recalibrate."
    }

    /// `UserDefaults` key for whether the panel is expanded. Read by the panel, and by the main
    /// screen to decide whether the cards should start below the panel.
    static let expandedKey = "diagnosticsPanel.expanded"

    /// Whether the detail rows below the panel's top line are shown.
    ///
    /// Hidden while calibrating, whatever the tester chose: the calibration screen is drawn
    /// beneath this panel, and the expanded panel covered it completely.
    static func showsDetails(isExpanded: Bool, needsCalibration: Bool) -> Bool {
        isExpanded && !needsCalibration
    }

    /// The panel's top line while calibration is pending.
    ///
    /// Complements the calibration screen rather than repeating it. That screen does not say
    /// that capture waits for good tracking, so while waiting this line names the tracking
    /// quality that is holding it up.
    ///
    /// Kept to 40 characters, which fits one monospaced caption line on an iPhone SE. Anything
    /// longer goes in ``calibrationHint(status:tracking:)`` on the line below.
    static func calibrationLine(status: CalibrationStatus, tracking: TrackingQuality) -> String {
        switch status {
        case .waiting:
            return tracking == .good
                ? "Calibrating · starting"
                : "Calibrating · tracking \(tracking.rawValue)"
        case .countdown(let seconds):
            return "Calibrating · starts in \(seconds)"
        case .sampling:
            return "Calibrating · hold still"
        case .validating:
            return "Calibrating · checking"
        case .success:
            return "Calibrated"
        case .failed:
            return "Calibration failed · tap Try Again"
        }
    }

    /// A second line, shown only while calibration is waiting on tracking.
    ///
    /// "Degraded" reads as good enough, and it is not: the countdown starts only once tracking
    /// is good. Nil in every other state, because the calibration screen already says what to do.
    static func calibrationHint(status: CalibrationStatus, tracking: TrackingQuality) -> String? {
        guard case .waiting = status, tracking != .good else { return nil }
        return "starts once tracking is good"
    }
}
