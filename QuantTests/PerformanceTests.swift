import XCTest
import SwiftUI
import PostureLogic
@testable import Quant

/// Performance benchmarks for the heaviest posture variants.
/// Benchmarks PostureDisplayData creation and observer update throughput.
@MainActor
final class PerformanceTests: XCTestCase {

    private let thresholds = PostureThresholds()

    /// Generates varying PostureDisplayData to simulate rapid updates.
    private func makeData(phase: Float, alertMode: Bool) -> PostureDisplayData {
        let raw = RawMetrics(
            timestamp: TimeInterval(phase),
            forwardCreep: phase * 10,
            headDrop: (1 - phase) * 8,
            shoulderRounding: phase * 6,
            lateralLean: (1 - phase) * 5,
            twist: phase * 4,
            movementLevel: 0,
            headMovementPattern: .still
        )
        let state: PostureState = alertMode
            ? .drifting(since: 100)
            : .good
        let nudge: NudgeDecision = alertMode
            ? .pending(reason: .sustainedSlouch, timeRemaining: 15)
            : .none
        return PostureDisplayData.make(
            from: raw,
            postureState: state,
            nudgeDecision: nudge,
            trackingQuality: .good,
            thresholds: thresholds
        )
    }

    // MARK: - Data Layer Performance

    func test_postureDisplayData_make_performance() {
        measure {
            for i in 0..<100 {
                let phase = Float(i) / 100.0
                let _ = self.makeData(phase: phase, alertMode: i % 3 == 2)
            }
        }
    }

    // MARK: - Variant View Instantiation Performance
    // Benchmarks creating 100 variant view structs to verify no excessive
    // allocation overhead in the heaviest variants.

    func test_variant7_viewInstantiationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = Variant7View()
            }
        }
    }

    func test_variant12_viewInstantiationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = Variant12View()
            }
        }
    }

    func test_variant23_viewInstantiationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = Variant23View()
            }
        }
    }

    func test_variant24_viewInstantiationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = Variant24View()
            }
        }
    }

    func test_variant42_viewInstantiationPerformance() {
        measure {
            for _ in 0..<100 {
                let _ = Variant42View()
            }
        }
    }
}
