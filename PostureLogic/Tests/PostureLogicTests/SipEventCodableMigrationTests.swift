import XCTest
@testable import PostureLogic

/// Migration safety tests for `SipEvent`.
///
/// `SipEvent.label` was added after the app shipped, which means there are
/// existing `sips-YYYY-MM-DD.json` files in user Documents directories that
/// do not contain a `label` key. These tests lock in that `SipEvent` can
/// still decode those files, and that newly-written files with a label
/// round-trip cleanly.
final class SipEventCodableMigrationTests: XCTestCase {

    // MARK: - Legacy decode

    func testDecodesLegacyJSONWithoutLabelField() throws {
        // Shape written by the pre-label builds: no `label` key at all.
        let legacyJSON = """
        {
            "id": "A7E9B0F1-0000-4000-8000-000000000001",
            "timestamp": 1712345678.5,
            "duration": 2.25,
            "confidence": null
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SipEvent.self, from: legacyJSON)

        XCTAssertEqual(event.id, UUID(uuidString: "A7E9B0F1-0000-4000-8000-000000000001"))
        XCTAssertEqual(event.timestamp, 1712345678.5)
        XCTAssertEqual(event.duration, 2.25)
        XCTAssertNil(event.confidence)
        XCTAssertNil(event.label)
    }

    func testDecodesLegacyJSONWithoutConfidenceOrLabel() throws {
        // Even older shape some builds wrote: no `confidence` key either.
        let veryLegacyJSON = """
        {
            "id": "A7E9B0F1-0000-4000-8000-000000000002",
            "timestamp": 1712345000.0,
            "duration": 1.5
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(SipEvent.self, from: veryLegacyJSON)

        XCTAssertNil(event.confidence)
        XCTAssertNil(event.label)
    }

    func testDecodesLegacyArrayRepresentingWholeDailyFile() throws {
        // The real on-disk format is `[SipEvent]`, not a single event.
        let legacyArrayJSON = """
        [
            {
                "id": "A7E9B0F1-0000-4000-8000-000000000003",
                "timestamp": 1712345000.0,
                "duration": 1.5,
                "confidence": null
            },
            {
                "id": "A7E9B0F1-0000-4000-8000-000000000004",
                "timestamp": 1712345500.0,
                "duration": 2.0,
                "confidence": 0.87
            }
        ]
        """.data(using: .utf8)!

        let events = try JSONDecoder().decode([SipEvent].self, from: legacyArrayJSON)

        XCTAssertEqual(events.count, 2)
        XCTAssertNil(events[0].label)
        XCTAssertNil(events[1].label)
        XCTAssertEqual(events[1].confidence, 0.87)
    }

    // MARK: - Round-trip with label

    func testRoundTripWithLabel() throws {
        let original = SipEvent(
            id: UUID(),
            timestamp: 1712345678.5,
            duration: 2.25,
            confidence: nil,
            label: .chinRest
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SipEvent.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.duration, original.duration)
        XCTAssertEqual(decoded.label, .chinRest)
    }

    func testRoundTripWithNilLabelOmitsKeyCleanly() throws {
        let event = SipEvent(
            timestamp: 1712345678.5,
            duration: 1.0
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SipEvent.self, from: data)
        XCTAssertNil(decoded.label)

        // Also verify an unlabeled event's JSON is compatible with a
        // hypothetical older decoder that doesn't know about `label`:
        // the key must be absent entirely, not present as NSNull.
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertFalse(
            dict.keys.contains("label"),
            "encodeIfPresent should omit the label key when nil"
        )
        // `confidence` is still written as `null` to match the existing
        // on-disk format bit-for-bit, so its key must be present.
        XCTAssertTrue(
            dict.keys.contains("confidence"),
            "confidence key must stay in the JSON for format stability"
        )
    }

    // MARK: - Label semantics

    func testLabelIsFalsePositiveClassification() {
        XCTAssertFalse(SipEvent.Label.confirmed.isFalsePositive)
        XCTAssertFalse(SipEvent.Label.unconfirmed.isFalsePositive)
        XCTAssertFalse(SipEvent.Label.missed.isFalsePositive)

        XCTAssertTrue(SipEvent.Label.chinRest.isFalsePositive)
        XCTAssertTrue(SipEvent.Label.faceTouch.isFalsePositive)
        XCTAssertTrue(SipEvent.Label.adjustingGlasses.isFalsePositive)
        XCTAssertTrue(SipEvent.Label.phoneToFace.isFalsePositive)
        XCTAssertTrue(SipEvent.Label.coughYawn.isFalsePositive)
        XCTAssertTrue(SipEvent.Label.other.isFalsePositive)
    }

    func testWithLabelReturnsCopyWithLabelUpdated() {
        let original = SipEvent(timestamp: 1000, duration: 2.0)
        XCTAssertNil(original.label)

        let labeled = original.withLabel(.confirmed)
        XCTAssertEqual(labeled.id, original.id)
        XCTAssertEqual(labeled.timestamp, original.timestamp)
        XCTAssertEqual(labeled.label, .confirmed)
        XCTAssertNil(original.label, "withLabel must not mutate the original")

        let cleared = labeled.withLabel(nil)
        XCTAssertNil(cleared.label)
    }
}
