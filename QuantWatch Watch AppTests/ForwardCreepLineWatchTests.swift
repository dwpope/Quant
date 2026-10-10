import Testing
@testable import QuantWatch_Watch_App

/// The Watch's copy of the forward-lean line matches the phone's: 6% since 2026-10-10.
struct ForwardCreepLineWatchTests {

    @MainActor @Test func theWatchDefault_isSixPercent() {
        #expect(WatchSessionDelegate(activatesSession: false).forwardCreepThreshold == 0.06)
    }
}
