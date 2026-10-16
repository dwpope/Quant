import Foundation
import Testing
@testable import QuantWatch_Watch_App

/// The Watch app's privacy manifest (2026-10-16 audit): it keeps two settings with `@AppStorage`,
/// which is UserDefaults, a "required reason" API. The App Store rejects an app that uses one
/// without saying why.
struct PrivacyManifestTests {

    @Test func saysWhyUserDefaultsIsUsed_andCollectsNothing() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let manifest = try #require(plist as? [String: Any])
        let types = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        #expect(types.count == 1)
        #expect(types.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(types.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }
}
