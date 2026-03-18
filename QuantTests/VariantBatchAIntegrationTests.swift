import XCTest
@testable import Quant

final class VariantBatchAIntegrationTests: XCTestCase {

    private var scoreCentricVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (1...6).contains($0.id) }
    }

    // MARK: - Count

    func test_batchA_has6Variants() {
        XCTAssertEqual(scoreCentricVariants.count, 6)
    }

    // MARK: - IDs and Names

    func test_variant1_isPrecisionGauge() {
        let v = scoreCentricVariants.first { $0.id == 1 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Precision Gauge")
    }

    func test_variant2_isTriadicRings() {
        let v = scoreCentricVariants.first { $0.id == 2 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Triadic Rings")
    }

    func test_variant3_isBatteryDrain() {
        let v = scoreCentricVariants.first { $0.id == 3 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Battery Drain")
    }

    func test_variant4_isArcMeter() {
        let v = scoreCentricVariants.first { $0.id == 4 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Arc Meter")
    }

    func test_variant5_isNumericCountdown() {
        let v = scoreCentricVariants.first { $0.id == 5 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Numeric Countdown")
    }

    func test_variant6_isTrafficLight() {
        let v = scoreCentricVariants.first { $0.id == 6 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Traffic Light")
    }

    // MARK: - Category

    func test_allBatchA_areScoreCentric() {
        for variant in scoreCentricVariants {
            XCTAssertEqual(
                variant.category, .scoreCentric,
                "Variant \(variant.id) (\(variant.name)) should be scoreCentric"
            )
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchA_makeViewReturnsNonNil() {
        for variant in scoreCentricVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }
}
