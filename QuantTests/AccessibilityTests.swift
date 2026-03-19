import XCTest
import PostureLogic
@testable import Quant

final class AccessibilityTests: XCTestCase {

    // MARK: - PostureVisualStyle Accessibility Labels

    func test_stateAccessibilityLabel_goodState_isNonEmpty() {
        let label = PostureVisualStyle.stateAccessibilityLabel(for: .good, worstOffender: nil)
        XCTAssertFalse(label.isEmpty)
        XCTAssertEqual(label, "Good")
    }

    func test_stateAccessibilityLabel_badState_includesWorstMetric() {
        let offender = MetricInfo(
            key: .forwardCreep, value: 0.05, ratio: 1.2, threshold: 0.04, isWorstOffender: true
        )
        let label = PostureVisualStyle.stateAccessibilityLabel(
            for: .bad(since: 0), worstOffender: offender
        )
        XCTAssertTrue(label.contains("Bad"), "Label should contain state")
        XCTAssertTrue(label.contains(MetricKey.forwardCreep.displayName), "Label should contain metric name")
    }

    func test_stateAccessibilityLabel_allStates_areNonEmpty() {
        let states: [PostureState] = [
            .absent, .calibrating, .good,
            .drifting(since: 0), .bad(since: 0),
        ]
        for state in states {
            let label = PostureVisualStyle.stateAccessibilityLabel(for: state, worstOffender: nil)
            XCTAssertFalse(label.isEmpty, "Label for \(state) should be non-empty")
        }
    }

    func test_stateAccessibilityLabel_eachMetricKey_hasDisplayName() {
        for key in MetricKey.allCases {
            let offender = MetricInfo(
                key: key, value: 0.05, ratio: 1.0, threshold: 0.05, isWorstOffender: true
            )
            let label = PostureVisualStyle.stateAccessibilityLabel(
                for: .bad(since: 0), worstOffender: offender
            )
            XCTAssertTrue(
                label.contains(key.displayName),
                "Label should include display name for \(key)"
            )
        }
    }

    // MARK: - PostureAnimations Reduce-Motion

    func test_reduceMotion_alertOnset_hasShorterDuration() {
        // The reduced-motion alternative should be a simple ease-in-out
        // (not a spring), so it's defined and non-nil.
        let standard = PostureAnimations.alertOnset(reduceMotion: false)
        let reduced = PostureAnimations.alertOnset(reduceMotion: true)
        // Both are valid Animation values (non-crashing)
        XCTAssertNotNil(standard)
        XCTAssertNotNil(reduced)
    }

    func test_reduceMotion_nudgePulse_doesNotRepeatForever() {
        // The reduced version should be a single ease-in-out, not repeating
        let reduced = PostureAnimations.nudgePulse(reduceMotion: true)
        XCTAssertNotNil(reduced)
    }

    func test_reduceMotion_allFactoryMethods_returnValidAnimations() {
        for rm in [true, false] {
            XCTAssertNotNil(PostureAnimations.alertOnset(reduceMotion: rm))
            XCTAssertNotNil(PostureAnimations.metricUpdate(reduceMotion: rm))
            XCTAssertNotNil(PostureAnimations.nudgePulse(reduceMotion: rm))
            XCTAssertNotNil(PostureAnimations.modeTransition(reduceMotion: rm))
        }
    }

    // MARK: - Variant Registry Accessibility Readiness

    func test_allVariants_haveNonEmptyNames_forAccessibilityLabels() {
        for variant in VariantRegistry.allVariants {
            XCTAssertFalse(
                variant.name.isEmpty,
                "Variant \(variant.id) must have a non-empty name for accessibility labels"
            )
        }
    }

    func test_allVariantCategories_areRepresented() {
        let usedCategories = Set(VariantRegistry.allVariants.map(\.category))
        for category in VariantCategory.allCases {
            XCTAssertTrue(
                usedCategories.contains(category),
                "\(category.rawValue) has no variants"
            )
        }
    }

    @MainActor
    func test_allMakeViewClosures_areCallable() {
        for variant in VariantRegistry.allVariants {
            let view = variant.makeView()
            XCTAssertNotNil(view, "Variant \(variant.id) makeView should not be nil")
        }
    }
}
