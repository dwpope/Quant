import XCTest
@testable import Quant

final class VariantBatchHIntegrationTests: XCTestCase {

    // Batch H covers Gamified (55-58) + Architectural (59-60)
    private var batchHVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (55...60).contains($0.id) }
    }

    // MARK: - Count

    func test_batchH_has6Variants() {
        XCTAssertEqual(batchHVariants.count, 6)
    }

    func test_fullRegistry_has60Variants() {
        XCTAssertEqual(VariantRegistry.allVariants.count, 60)
    }

    // MARK: - IDs and Names

    func test_variant55_isXPHealthBar() {
        let v = batchHVariants.first { $0.id == 55 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "XP Health Bar")
    }

    func test_variant56_isStreakCounter() {
        let v = batchHVariants.first { $0.id == 56 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Streak Counter")
    }

    func test_variant57_isAchievementRings() {
        let v = batchHVariants.first { $0.id == 57 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Achievement Rings")
    }

    func test_variant58_isBossBattle() {
        let v = batchHVariants.first { $0.id == 58 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Boss Battle")
    }

    func test_variant59_isToriiGate() {
        let v = batchHVariants.first { $0.id == 59 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Torii Gate")
    }

    func test_variant60_isSuspensionBridge() {
        let v = batchHVariants.first { $0.id == 60 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Suspension Bridge")
    }

    // MARK: - Categories

    func test_variants55to58_areGamified() {
        for v in batchHVariants where (55...58).contains(v.id) {
            XCTAssertEqual(v.category, .gamified,
                           "Variant \(v.id) (\(v.name)) should be gamified")
        }
    }

    func test_variants59to60_areExperimental() {
        for v in batchHVariants where (59...60).contains(v.id) {
            XCTAssertEqual(v.category, .experimental,
                           "Variant \(v.id) (\(v.name)) should be experimental")
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchH_makeViewReturnsNonNil() {
        for variant in batchHVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }

    // MARK: - All Variant IDs Unique and Span 1-60

    func test_allVariantIDs_areUniqueAndSpan1to60() {
        let ids = VariantRegistry.allVariants.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(uniqueIDs.count, 60, "All 60 variant IDs should be unique")
        XCTAssertEqual(uniqueIDs, Set(1...60), "Variant IDs should span 1-60")
    }

    // MARK: - All Categories Represented

    func test_allCategories_haveAtLeastOneVariant() {
        for category in VariantCategory.allCases {
            let count = VariantRegistry.allVariants.filter { $0.category == category }.count
            XCTAssertGreaterThan(count, 0,
                                 "Category \(category.rawValue) should have at least one variant")
        }
    }
}
