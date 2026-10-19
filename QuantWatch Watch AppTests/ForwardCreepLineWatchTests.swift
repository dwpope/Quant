import Testing
@testable import QuantWatch_Watch_App

/// The Watch's copy of the forward-lean line matches the phone's: 6% since 2026-10-10.
struct ForwardCreepLineWatchTests {

    @MainActor @Test func theWatchDefault_isSixPercent() {
        #expect(WatchSessionDelegate(activatesSession: false).forwardCreepThreshold == 0.06)
    }
}

/// The Watch's sliders have the phone's ranges and steps (2026-10-16 audit), a golden copy of
/// `PostureSettingLimits` and its tests. They had the Calibration screen's, which differed from
/// Posture Thresholds'.
struct WatchSettingLimitsTests {

    @Test func eachSetting_hasThePhonesRangeAndStep() {
        #expect(WatchSettingLimits.forwardCreep == 0.01...0.30)
        #expect(WatchSettingLimits.forwardCreepStep == 0.005)
        #expect(WatchSettingLimits.twist == 5...45)
        #expect(WatchSettingLimits.twistStep == 1)
        #expect(WatchSettingLimits.sideLean == 0.02...0.25)
        #expect(WatchSettingLimits.sideLeanStep == 0.01)
    }

    @MainActor @Test func eachDefault_isInRange() {
        let delegate = WatchSessionDelegate(activatesSession: false)
        #expect(WatchSettingLimits.forwardCreep.contains(delegate.forwardCreepThreshold))
        #expect(WatchSettingLimits.twist.contains(delegate.twistThreshold))
        #expect(WatchSettingLimits.sideLean.contains(delegate.sideLeanThreshold))
    }
}
