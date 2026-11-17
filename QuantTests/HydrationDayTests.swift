import XCTest
@testable import Quant

/// Every number and line the hydration card, the drinks list and the calm row show, from the
/// day's drinks in Apple Health (hydration design §7.4–§7.7).
@MainActor
final class HydrationDayTests: XCTestCase, HydrationFixtures {

    func test_total_andHeadline() {
        XCTAssertEqual(mockDay.totalMillilitres, 980)
        XCTAssertEqual(mockDay.headline, "980 mL of 2 L")
        XCTAssertEqual(mockDay.lastDrink?.at, at(14, 18))
    }

    func test_headline_pastTheGoal() {
        let day = HydrationDay(drinks: [drink(10, 0, 1700), drink(13, 0, 1500)], day: at(14), calendar: cal)
        XCTAssertEqual(day.headline, "3.2 L of 2 L")
        XCTAssertEqual(day.yMax, 3200)
        XCTAssertEqual(mockDay.yMax, 2000)
    }

    func test_volumeLabel() {
        XCTAssertEqual(HydrationDay.volumeLabel(0), "0 mL")
        XCTAssertEqual(HydrationDay.volumeLabel(999), "999 mL")
        XCTAssertEqual(HydrationDay.volumeLabel(1000), "1 L")
        XCTAssertEqual(HydrationDay.volumeLabel(1234), "1.2 L")
        XCTAssertEqual(HydrationDay.volumeLabel(1960), "2 L")
    }

    func test_onlyTheDaysRealDrinksCount() {
        let day = HydrationDay(drinks: [drink(23, 50, 200, day: 15), drink(10, 0, 0), drink(12, 0, 300),
                                        drink(0, 10, 100, day: 17)], day: at(14), calendar: cal)
        XCTAssertEqual(day.drinks.map(\.millilitres), [300])
    }

    func test_detailLine() {
        XCTAssertEqual(mockDay.detailLine(now: at(14, 30)), "Last drink 12 min ago · 6 drinks")
        let one = HydrationDay(drinks: [drink(14, 29, 100)], day: at(14, 30), calendar: cal)
        XCTAssertEqual(one.detailLine(now: at(14, 29).addingTimeInterval(30)), "Last drink just now · 1 drink")
        XCTAssertEqual(one.detailLine(now: at(15, 54)), "Last drink 1 h 25 min ago · 1 drink")
        XCTAssertEqual(one.detailLine(now: at(16, 29)), "Last drink 2 h ago · 1 drink")
        XCTAssertEqual(HydrationDay.empty(day: at(9), calendar: cal).detailLine(now: at(9)), "No drinks yet today")
    }

    func test_calmLine() {
        XCTAssertEqual(mockDay.calmLine(now: at(14, 30)), "980 mL · last drink 12 min ago")
        XCTAssertEqual(HydrationDay.empty(day: at(9), calendar: cal).calmLine(now: at(9)), "No drinks yet today")
    }

    func test_pace() {
        XCTAssertEqual(mockDay.paceMillilitres(at: at(8)), 0)
        XCTAssertEqual(mockDay.paceMillilitres(at: at(9)), 0)
        XCTAssertEqual(mockDay.paceMillilitres(at: at(13)), 750)
        XCTAssertEqual(mockDay.paceMillilitres(at: at(17)), 1500)
        XCTAssertEqual(mockDay.paceMillilitres(at: at(20)), 1500)
    }

    func test_pacePoints_bendOnlyInsideTheSpan() {
        XCTAssertEqual(mockDay.pacePoints(in: at(8)...at(14, 30)),
                       [.init(at: at(8), millilitres: 0), .init(at: at(9), millilitres: 0),
                        .init(at: at(14, 30), millilitres: 1031.25)])
        XCTAssertEqual(mockDay.pacePoints(in: at(9, 30)...at(18)),
                       [.init(at: at(9, 30), millilitres: 93.75), .init(at: at(17), millilitres: 1500),
                        .init(at: at(18), millilitres: 1500)])
    }

    func test_runningTotal_stepsAtEachDrink() {
        XCTAssertEqual(mockDay.runningTotal(from: at(9), to: at(14, 30)).map(\.millilitres),
                       [0, 250, 290, 470, 530, 860, 980, 980])
        XCTAssertEqual(mockDay.runningTotal(from: at(10), to: at(14, 30)).first?.millilitres, 250)
    }

    func test_chartSpan_followsThePostureBand() {
        XCTAssertEqual(mockDay.chartSpan(postureSpan: at(9, 10)...at(14, 30), now: at(14, 30)), at(9, 10)...at(14, 30))
    }

    func test_chartSpan_stretchesToAnEarlyDrink() {
        let day = HydrationDay(drinks: [drink(8, 15, 200)], day: at(14), calendar: cal)
        XCTAssertEqual(day.chartSpan(postureSpan: at(9, 30)...at(14, 30), now: at(14, 30)), at(8, 15)...at(14, 30))
    }

    func test_chartSpan_withoutPosture_runsFromNineToNow() {
        XCTAssertEqual(mockDay.chartSpan(postureSpan: nil, now: at(14, 30)), at(9)...at(14, 30))
        XCTAssertEqual(HydrationDay.empty(day: at(7, 30), calendar: cal).chartSpan(postureSpan: nil, now: at(7, 30)),
                       at(6, 30)...at(7, 30))
    }

    func test_awayStretches() {
        let segments: [PostureTimeline.Segment] = [
            .init(start: at(9), end: at(10), band: .good), .init(start: at(10), end: at(10, 30), band: .away),
            .init(start: at(10, 30), end: at(11), band: .bad), .init(start: at(12, 20), end: at(12, 50), band: .away)]
        XCTAssertEqual(HydrationDay.awayStretches(segments), [at(10)...at(10, 30), at(12, 20)...at(12, 50)])
    }

    func test_drinkSource() {
        let aware = "net.davepope.Quant"
        XCTAssertEqual(DrinkSource.from(bundleIdentifier: "com.apple.shortcuts", sourceName: "Shortcuts",
                                        wasUserEntered: true, awareBundleIdentifier: aware), .shortcut)
        XCTAssertEqual(DrinkSource.from(bundleIdentifier: aware, sourceName: "Aware",
                                        wasUserEntered: true, awareBundleIdentifier: aware), .addedInAware)
        XCTAssertEqual(DrinkSource.from(bundleIdentifier: aware, sourceName: "Aware",
                                        wasUserEntered: false, awareBundleIdentifier: aware), .coaster)
        XCTAssertEqual(DrinkSource.from(bundleIdentifier: "com.apple.Health", sourceName: "Health",
                                        wasUserEntered: true, awareBundleIdentifier: aware), .otherApp("Health"))
        XCTAssertEqual([DrinkSource.coaster, .addedInAware, .shortcut, .otherApp("Health")].map(\.label),
                       ["Coaster", "Added in Aware", "Shortcut", "Health"])
        XCTAssertEqual([DrinkSource.coaster, .addedInAware, .shortcut, .otherApp("Health")].map(\.isEditableInAware),
                       [true, true, false, false])
    }

    func test_accessNote() {
        XCTAssertEqual(HydrationDay.accessNote(.unavailable), "Apple Health isn't available on this device")
        XCTAssertEqual(HydrationDay.accessNote(.denied),
                       "Apple Health is off for Aware. Turn it on in Settings › Health › Data Access & Devices.")
        XCTAssertNil(HydrationDay.accessNote(.granted))
        XCTAssertNil(HydrationDay.accessNote(.notAsked))
    }

    func test_calmRow() {
        XCTAssertNil(HydrationDay.calmRow(day: mockDay, access: .unavailable, now: at(14, 30)))
        XCTAssertEqual(HydrationDay.calmRow(day: mockDay, access: .denied, now: at(14, 30)), "Apple Health is off")
        XCTAssertEqual(HydrationDay.calmRow(day: mockDay, access: .granted, now: at(14, 30)), "980 mL · last drink 12 min ago")
        XCTAssertEqual(HydrationDay.calmRow(day: mockDay, access: .notAsked, now: at(14, 30)), "980 mL · last drink 12 min ago")
    }

    func test_drinksList_footnote_onlyWhenSomeAreReadOnly() {
        XCTAssertEqual(DrinksListView.footnote(for: mockDay.drinks), "Drinks from Shortcuts and other apps are changed in the Health app.")
        let mine = Drink(id: UUID(), at: at(11), millilitres: 250, source: .addedInAware, syncIdentifier: "aware-manual-Z", syncVersion: 1)
        XCTAssertNil(DrinksListView.footnote(for: [mine]))
        XCTAssertNil(DrinksListView.footnote(for: []))
    }
}
