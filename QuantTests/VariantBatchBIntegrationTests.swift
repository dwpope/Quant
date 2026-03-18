import XCTest
@testable import Quant

final class VariantBatchBIntegrationTests: XCTestCase {

    private var dashboardVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (7...12).contains($0.id) }
    }

    // MARK: - Count

    func test_batchB_has6Variants() {
        XCTAssertEqual(dashboardVariants.count, 6)
    }

    // MARK: - IDs and Names

    func test_variant7_isFiveBarEqualizer() {
        let v = dashboardVariants.first { $0.id == 7 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Five-Bar Equalizer")
    }

    func test_variant8_isDonutBreakdown() {
        let v = dashboardVariants.first { $0.id == 8 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Donut Breakdown")
    }

    func test_variant9_isHorizontalRails() {
        let v = dashboardVariants.first { $0.id == 9 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Horizontal Rails")
    }

    func test_variant10_isRadialDialArray() {
        let v = dashboardVariants.first { $0.id == 10 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Radial Dial Array")
    }

    func test_variant11_isDigitalCockpit() {
        let v = dashboardVariants.first { $0.id == 11 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Digital Cockpit")
    }

    func test_variant12_isSplitFlapDisplay() {
        let v = dashboardVariants.first { $0.id == 12 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Split Flap Display")
    }

    // MARK: - Category

    func test_allBatchB_areDataVisualization() {
        for variant in dashboardVariants {
            XCTAssertEqual(
                variant.category, .dataVisualization,
                "Variant \(variant.id) (\(variant.name)) should be dataVisualization"
            )
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchB_makeViewReturnsNonNil() {
        for variant in dashboardVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }
}
