import XCTest
@testable import Quant

final class MetricKeyTests: XCTestCase {

    func test_allCases_hasFiveMetrics() {
        XCTAssertEqual(MetricKey.allCases.count, 5)
    }

    func test_eachCase_hasNonEmptyDisplayName() {
        for key in MetricKey.allCases {
            XCTAssertFalse(key.displayName.isEmpty, "\(key) has empty displayName")
        }
    }

    func test_eachCase_hasNonEmptySymbolName() {
        for key in MetricKey.allCases {
            XCTAssertFalse(key.symbolName.isEmpty, "\(key) has empty symbolName")
        }
    }

    func test_identifiable_idMatchesRawValue() {
        for key in MetricKey.allCases {
            XCTAssertEqual(key.id, key.rawValue)
        }
    }
}
