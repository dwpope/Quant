import HealthKit
import XCTest
@testable import Quant

/// The two pure parts of Aware's Apple Health store: what HealthKit's sharing status means for
/// the card, and how a saved drink is marked so an edit replaces it.
@MainActor
final class WaterHealthStoreTests: XCTestCase {

    func test_access_fromHealthKitStatus() {
        XCTAssertEqual(HealthKitWaterStore.access(available: false, status: .sharingAuthorized), .unavailable)
        XCTAssertEqual(HealthKitWaterStore.access(available: true, status: .notDetermined), .notAsked)
        XCTAssertEqual(HealthKitWaterStore.access(available: true, status: .sharingDenied), .denied)
        XCTAssertEqual(HealthKitWaterStore.access(available: true, status: .sharingAuthorized), .granted)
    }

    func test_metadata_marksEntryAndSync() {
        let m = HealthKitWaterStore.metadata(syncIdentifier: "aware-manual-1", syncVersion: 2, userEntered: true)
        XCTAssertEqual(m[HKMetadataKeySyncIdentifier] as? String, "aware-manual-1")
        XCTAssertEqual((m[HKMetadataKeySyncVersion] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(m[HKMetadataKeyWasUserEntered] as? Bool, true)
    }
}
