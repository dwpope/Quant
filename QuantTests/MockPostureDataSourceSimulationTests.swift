import XCTest
@testable import Quant
import PostureLogic

@MainActor
final class MockPostureDataSourceSimulationTests: XCTestCase {

    /// Fast-forward 90 simulated seconds at 100x speed and verify
    /// at least one full Good → Drifting → Bad → Good cycle occurred.
    func test_fullCycle_goodDriftingBadGood() {
        let source = MockPostureDataSource()
        source.stopSimulation() // stop timer for manual stepping
        source.simulationSpeedMultiplier = 100.0

        var sawGood = false
        var sawDrifting = false
        var sawBad = false
        var sawGoodAfterBad = false

        // At 100x speed, each tick = (1/30)*100 ≈ 3.33 sim seconds
        // 90 sim seconds → ceil(90 / 3.33) = 27 ticks
        let tickDt = (1.0 / 30.0) * 100.0
        let tickCount = Int(ceil(90.0 / tickDt))

        for _ in 0..<tickCount {
            source.simulationTick()
            let state = source.currentData.postureState

            switch state {
            case .good:
                if sawBad { sawGoodAfterBad = true }
                else { sawGood = true }
            case .drifting:
                sawDrifting = true
            case .bad:
                sawBad = true
            default:
                break
            }
        }

        XCTAssertTrue(sawGood, "Should observe .good state")
        XCTAssertTrue(sawDrifting, "Should observe .drifting state")
        XCTAssertTrue(sawBad, "Should observe .bad state")
        XCTAssertTrue(sawGoodAfterBad,
                      "Should observe .good state again after .bad (full cycle)")
    }

    /// During the drifting phase, nudgeCountdownSeconds should be non-nil
    /// (populated from NudgeDecision.pending timeRemaining).
    func test_nudgeCountdownDuringDrifting() {
        let source = MockPostureDataSource()
        source.stopSimulation()
        source.simulationSpeedMultiplier = 100.0

        var foundNudgeCountdown = false

        let tickDt = (1.0 / 30.0) * 100.0
        let tickCount = Int(ceil(90.0 / tickDt))

        for _ in 0..<tickCount {
            source.simulationTick()
            let data = source.currentData
            if case .drifting = data.postureState, data.nudgeCountdownSeconds != nil {
                foundNudgeCountdown = true
                break
            }
        }

        XCTAssertTrue(foundNudgeCountdown,
                      "nudgeCountdownSeconds should be non-nil during drifting phase")
    }

    /// During the bad phase, nudgeDecision should equal .fire for at least
    /// one emission (fires at phase start, returns to .none after 2s).
    func test_fireEmissionDuringBadPhase() {
        let source = MockPostureDataSource()
        source.stopSimulation()
        source.simulationSpeedMultiplier = 100.0

        var sawFire = false

        let tickDt = (1.0 / 30.0) * 100.0
        let tickCount = Int(ceil(90.0 / tickDt))

        for _ in 0..<tickCount {
            source.simulationTick()
            if case .fire = source.currentData.nudgeDecision {
                sawFire = true
                break
            }
        }

        XCTAssertTrue(sawFire,
                      "Should observe .fire nudge decision during bad phase")
    }
}
