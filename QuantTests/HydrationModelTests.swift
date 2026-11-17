import XCTest
@testable import Quant

/// Health without HealthKit: records what the model asks of it, and returns `stored`.
@MainActor
final class FakeWaterStore: WaterHealthStore {
    var currentAccess: HealthAccess = .notAsked
    var accessAfterRequest: HealthAccess = .granted
    var stored: [Drink] = []
    private(set) var requestCount = 0
    private(set) var readRanges: [(Date, Date)] = []
    private(set) var saved: [(millilitres: Double, at: Date, syncIdentifier: String, syncVersion: Int, userEntered: Bool)] = []
    private(set) var deleted: [UUID] = []
    private(set) var observeCount = 0
    private(set) var onChange: (@Sendable () -> Void)?

    func access() -> HealthAccess { currentAccess }

    func requestAccess() async throws {
        requestCount += 1
        currentAccess = accessAfterRequest
    }

    func drinks(from start: Date, to end: Date) async throws -> [Drink] {
        readRanges.append((start, end))
        return stored
    }

    func saveDrink(millilitres: Double, at: Date, syncIdentifier: String, syncVersion: Int,
                   userEntered: Bool) async throws {
        saved.append((millilitres, at, syncIdentifier, syncVersion, userEntered))
    }

    func deleteDrink(id: UUID) async throws { deleted.append(id) }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        observeCount += 1
        self.onChange = onChange
    }

    func stopObserving() { onChange = nil }
}

/// Today's drinks from Apple Health: asking once, reading the day, keeping up with changes made
/// elsewhere, and adding, changing and deleting Aware's own drinks (hydration design §7.4, §7.6).
@MainActor
final class HydrationModelTests: XCTestCase, HydrationFixtures {

    private var fake: FakeWaterStore!
    private var clock: Date!
    private var model: HydrationModel!

    override func setUp() async throws {
        fake = FakeWaterStore()
        clock = at(14, 30)
        model = HydrationModel(store: fake, calendar: cal, now: { [unowned self] in self.clock })
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                              _ expected: HydrationError,
                                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await expression()
            XCTFail("expected \(expected), nothing thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? HydrationError, expected, file: file, line: line)
        }
    }

    func test_start_asksOnce_thenLoadsToday() async {
        await model.start(); await model.start()
        XCTAssertEqual(fake.requestCount, 1)
        XCTAssertEqual(model.access, .granted)
        XCTAssertEqual(fake.observeCount, 1)
        XCTAssertEqual(fake.readRanges.last?.0, at(0)); XCTAssertEqual(fake.readRanges.last?.1, at(0, day: 17))
    }

    func test_start_whenDenied_doesNotAskAgain() async {
        fake.currentAccess = .denied
        await model.start()
        XCTAssertEqual(fake.requestCount, 0); XCTAssertEqual(model.access, .denied)
    }

    func test_start_whenUnavailable_neitherAsksNorReads() async {
        fake.currentAccess = .unavailable
        await model.start()
        XCTAssertEqual(fake.requestCount, 0); XCTAssertTrue(fake.readRanges.isEmpty); XCTAssertEqual(model.access, .unavailable)
    }

    func test_refresh_afterMidnight_readsTheNewDay() async {
        fake.stored = [drink(14, 0, 300)]
        await model.start()
        XCTAssertEqual(model.day.totalMillilitres, 300)
        clock = at(0, 1, day: 17)
        await model.refresh()
        XCTAssertEqual(fake.readRanges.last?.0, at(0, day: 17))
        XCTAssertEqual(model.day.totalMillilitres, 0)
    }

    func test_aHealthChange_reloadsTheDay() async {
        await model.start()
        fake.stored = [drink(14, 0, 250)]
        fake.onChange?()
        await waitUntil { model.day.drinks.count == 1 }
        XCTAssertEqual(model.day.totalMillilitres, 250)
    }

    func test_addDrink_savesUserEnteredWithAnAwareSyncIdentifier() async throws {
        try await model.addDrink(millilitres: 250, at: at(14, 0))
        let s = try XCTUnwrap(fake.saved.first)
        XCTAssertEqual(s.millilitres, 250); XCTAssertEqual(s.at, at(14, 0))
        XCTAssertTrue(s.syncIdentifier.hasPrefix("aware-manual-")); XCTAssertEqual(s.syncVersion, 1); XCTAssertTrue(s.userEntered)
    }

    func test_addDrink_outsideTheRange_throws() async {
        await XCTAssertThrowsErrorAsync(try await model.addDrink(millilitres: 0, at: at(14)), .amountOutOfRange)
        XCTAssertTrue(fake.saved.isEmpty)
    }

    func test_changeAmount_replacesWithTheNextSyncVersion() async throws {
        let mine = Drink(id: UUID(), at: at(11), millilitres: 250, source: .addedInAware, syncIdentifier: "aware-manual-X", syncVersion: 1)
        try await model.changeAmount(of: mine, to: 300)
        XCTAssertEqual(fake.saved.first?.syncIdentifier, "aware-manual-X"); XCTAssertEqual(fake.saved.first?.syncVersion, 2)
        XCTAssertEqual(fake.saved.first?.at, at(11)); XCTAssertEqual(fake.saved.first?.userEntered, true)
        let coaster = Drink(id: UUID(), at: at(12), millilitres: 80, source: .coaster, syncIdentifier: "coaster-a-1-7", syncVersion: 1)
        try await model.changeAmount(of: coaster, to: 60)
        XCTAssertEqual(fake.saved.last?.userEntered, false)
    }

    func test_shortcutDrinks_cannotBeChangedOrDeleted() async {
        let theirs = drink(10, 0, 250) // .shortcut
        await XCTAssertThrowsErrorAsync(try await model.delete(theirs), .notEditable)
        await XCTAssertThrowsErrorAsync(try await model.changeAmount(of: theirs, to: 100), .notEditable)
        XCTAssertTrue(fake.deleted.isEmpty); XCTAssertTrue(fake.saved.isEmpty)
    }

    func test_delete_ownDrink_deletesByID() async throws {
        let mine = Drink(id: UUID(), at: at(11), millilitres: 250, source: .addedInAware, syncIdentifier: "aware-manual-Y", syncVersion: 1)
        try await model.delete(mine)
        XCTAssertEqual(fake.deleted, [mine.id])
    }
}
