import XCTest
@testable import Quant

final class VariantBatchCIntegrationTests: XCTestCase {

    private var typographicVariants: [VariantDescriptor] {
        VariantRegistry.allVariants.filter { (13...20).contains($0.id) }
    }

    // MARK: - Count

    func test_batchC_has8Variants() {
        XCTAssertEqual(typographicVariants.count, 8)
    }

    // MARK: - IDs and Names

    func test_variant13_isSingleWord() {
        let v = typographicVariants.first { $0.id == 13 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Single Word")
    }

    func test_variant14_isBreathingDot() {
        let v = typographicVariants.first { $0.id == 14 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Breathing Dot")
    }

    func test_variant15_isThinLine() {
        let v = typographicVariants.first { $0.id == 15 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Thin Line")
    }

    func test_variant16_isGradientWash() {
        let v = typographicVariants.first { $0.id == 16 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Gradient Wash")
    }

    func test_variant17_isClockFace() {
        let v = typographicVariants.first { $0.id == 17 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Clock Face")
    }

    func test_variant18_isEmojiMood() {
        let v = typographicVariants.first { $0.id == 18 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Emoji Mood")
    }

    func test_variant19_isConcentricRipples() {
        let v = typographicVariants.first { $0.id == 19 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Concentric Ripples")
    }

    func test_variant20_isKanjiSymbol() {
        let v = typographicVariants.first { $0.id == 20 }
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.name, "Kanji / Symbol")
    }

    // MARK: - Category

    func test_allBatchC_areTypographic() {
        for variant in typographicVariants {
            XCTAssertEqual(
                variant.category, .typographic,
                "Variant \(variant.id) (\(variant.name)) should be typographic"
            )
        }
    }

    // MARK: - makeView

    @MainActor
    func test_allBatchC_makeViewReturnsNonNil() {
        for variant in typographicVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) (\(variant.name)) makeView() returned nil")
        }
    }
}
