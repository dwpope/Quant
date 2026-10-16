import XCTest
@testable import Quant

/// What the App Store needs before Aware can be submitted (2026-10-16 audit).
///
/// An app that calls a "required reason" API without saying why in its privacy manifest is
/// rejected. Aware calls three kinds: UserDefaults for its settings, file dates for Stored Data,
/// and the uptime clock behind `FrameClock`. Nothing it records leaves the phone unless the Jev
/// classifier is switched on, and that ships off, so it declares no data collected and no
/// tracking.
final class PrivacyManifestTests: XCTestCase {

    private func manifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "the app has a privacy manifest")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func reasons(_ manifest: [String: Any]) -> [String: [String]] {
        let types = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        return Dictionary(uniqueKeysWithValues: types.compactMap { entry in
            (entry["NSPrivacyAccessedAPIType"] as? String).map {
                ($0, entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
            }
        })
    }

    func test_theManifest_saysWhyEachRequiredReasonAPIIsUsed() throws {
        let reasons = reasons(try manifest())
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"],
                       "settings, read and written by the app itself")
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"],
                       "Stored Data reads the dates of files in the app's own container")
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategorySystemBootTime"], ["8FFB.1"],
                       "FrameClock turns the camera's uptime frame times into calendar times")
    }

    func test_theManifest_declaresNoTrackingAndNothingCollected() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }

    /// The camera prompt names the app you see (2026-10-16): it said "Quant", the project's name.
    func test_theCameraPrompt_namesAware() throws {
        let prompt = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String)
        XCTAssertTrue(prompt.hasPrefix("Aware "), prompt)
        XCTAssertFalse(prompt.contains("Quant"), prompt)
    }
}
