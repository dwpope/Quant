import XCTest
@testable import Quant

final class VariantRegistryTests: XCTestCase {

    func test_allVariants_has60() {
        XCTAssertEqual(VariantRegistry.allVariants.count, 60)
    }

    func test_allVariantIDs_areUnique() {
        let ids = VariantRegistry.allVariants.map(\.id)
        XCTAssertEqual(Set(ids).count, 60, "Variant IDs must be unique")
    }

    func test_allVariantIDs_span1To60() {
        let ids = Set(VariantRegistry.allVariants.map(\.id))
        for i in 1...60 {
            XCTAssertTrue(ids.contains(i), "Missing variant ID \(i)")
        }
    }

    func test_allCategories_haveAtLeastOneVariant() {
        let usedCategories = Set(VariantRegistry.allVariants.map(\.category))
        for category in VariantCategory.allCases {
            XCTAssertTrue(
                usedCategories.contains(category),
                "\(category.rawValue) has no variants"
            )
        }
    }

    @MainActor
    func test_allMakeViewClosures_canBeCalledWithoutCrashing() {
        for variant in VariantRegistry.allVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) makeView returned nil")
        }
    }

    func test_allVariants_haveNonEmptyNames() {
        for variant in VariantRegistry.allVariants {
            XCTAssertFalse(variant.name.isEmpty, "Variant \(variant.id) has empty name")
        }
    }
}
