import XCTest
import PostureLogic
@testable import Quant

/// Tests for `SipInsights` — pure computation over sip event arrays.
///
/// All timestamps use `Date.timeIntervalSinceReferenceDate` because that's
/// what `SipEvent.timestamp` stores. Tests pin a known reference date
/// (2026-05-13 at 08:00 UTC) so morning/afternoon splits are deterministic.
final class SipInsightsTests: XCTestCase {

    // MARK: - Helpers

    /// A calendar fixed to UTC so tests don't depend on the runner's timezone.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// 2026-05-13 08:00:00 UTC
    private var referenceDate: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 13
        comps.hour = 8; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: comps)!
    }

    /// Creates a SipEvent at the given hour and minute on the reference day.
    private func sip(hour: Int, minute: Int = 0) -> SipEvent {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 13
        comps.hour = hour; comps.minute = minute; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        let date = utcCalendar.date(from: comps)!
        return SipEvent(
            timestamp: date.timeIntervalSinceReferenceDate,
            duration: 2.0
        )
    }

    // MARK: - Empty

    func test_empty_totalCountIsZero() {
        let insights = SipInsights(sips: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertEqual(insights.totalCount, 0)
    }

    func test_empty_allOptionalsNil() {
        let insights = SipInsights(sips: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertNil(insights.averageInterval)
        XCTAssertNil(insights.shortestGap)
        XCTAssertNil(insights.longestGap)
        XCTAssertNil(insights.medianGap)
        XCTAssertNil(insights.activeDuration)
        XCTAssertNil(insights.firstSipTimestamp)
        XCTAssertNil(insights.lastSipTimestamp)
        XCTAssertNil(insights.peakHour)
    }

    func test_empty_morningAfternoonBothZero() {
        let insights = SipInsights(sips: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertEqual(insights.morningCount, 0)
        XCTAssertEqual(insights.afternoonCount, 0)
    }

    func test_empty_hourlyDistributionAllZeros() {
        let insights = SipInsights(sips: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertEqual(insights.hourlyDistribution.count, 24)
        XCTAssertTrue(insights.hourlyDistribution.allSatisfy { $0 == 0 })
    }

    // MARK: - Single Sip

    func test_singleSip_totalCountIsOne() {
        let insights = SipInsights(
            sips: [sip(hour: 9)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.totalCount, 1)
    }

    func test_singleSip_gapsAreNil() {
        let insights = SipInsights(
            sips: [sip(hour: 9)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertNil(insights.averageInterval)
        XCTAssertNil(insights.shortestGap)
        XCTAssertNil(insights.longestGap)
        XCTAssertNil(insights.medianGap)
        XCTAssertNil(insights.activeDuration)
    }

    func test_singleSip_timestampsPresent() {
        let s = sip(hour: 10)
        let insights = SipInsights(
            sips: [s],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.firstSipTimestamp, s.timestamp)
        XCTAssertEqual(insights.lastSipTimestamp, s.timestamp)
    }

    func test_singleSip_morningCountIsOne() {
        let insights = SipInsights(
            sips: [sip(hour: 9)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.morningCount, 1)
        XCTAssertEqual(insights.afternoonCount, 0)
    }

    func test_singleSip_afternoonCountIsOne() {
        let insights = SipInsights(
            sips: [sip(hour: 14)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.morningCount, 0)
        XCTAssertEqual(insights.afternoonCount, 1)
    }

    func test_singleSip_peakHourCorrect() {
        let insights = SipInsights(
            sips: [sip(hour: 15)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.peakHour, 15)
    }

    // MARK: - Two Sips

    func test_twoSips_gapCalculation() {
        // 09:00 and 10:00 — gap of 3600 seconds
        let insights = SipInsights(
            sips: [sip(hour: 9), sip(hour: 10)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.totalCount, 2)
        XCTAssertEqual(insights.averageInterval!, 3600, accuracy: 0.1)
        XCTAssertEqual(insights.shortestGap!, 3600, accuracy: 0.1)
        XCTAssertEqual(insights.longestGap!, 3600, accuracy: 0.1)
        XCTAssertEqual(insights.medianGap!, 3600, accuracy: 0.1)
        XCTAssertEqual(insights.activeDuration!, 3600, accuracy: 0.1)
    }

    // MARK: - Multiple Sips — Gap Stats

    func test_multipleSips_averageInterval() {
        // 08:00, 09:00, 09:30 — gaps: 3600, 1800 — average: 2700
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 9), sip(hour: 9, minute: 30)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.averageInterval!, 2700, accuracy: 0.1)
    }

    func test_multipleSips_shortestAndLongestGap() {
        // 08:00, 09:00, 09:30 — gaps: 3600, 1800
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 9), sip(hour: 9, minute: 30)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.shortestGap!, 1800, accuracy: 0.1)
        XCTAssertEqual(insights.longestGap!, 3600, accuracy: 0.1)
    }

    func test_multipleSips_medianGapOddCount() {
        // 08:00, 09:00, 09:30, 11:30 — gaps: 3600, 1800, 7200
        // Sorted gaps: 1800, 3600, 7200 — median is 3600
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 9), sip(hour: 9, minute: 30), sip(hour: 11, minute: 30)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.medianGap!, 3600, accuracy: 0.1)
    }

    func test_multipleSips_medianGapEvenCount() {
        // 08:00, 09:00, 09:30 — gaps: 3600, 1800
        // Sorted gaps: 1800, 3600 — median is (1800+3600)/2 = 2700
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 9), sip(hour: 9, minute: 30)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.medianGap!, 2700, accuracy: 0.1)
    }

    func test_multipleSips_activeDuration() {
        // 08:00 to 14:00 — 6 hours = 21600 seconds
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 10), sip(hour: 14)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.activeDuration!, 21600, accuracy: 0.1)
    }

    // MARK: - Morning / Afternoon Split

    func test_morningAfternoon_splitAtNoon() {
        // 08:00, 11:00 (morning) and 12:00, 15:00 (afternoon)
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 11), sip(hour: 12), sip(hour: 15)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.morningCount, 2)
        XCTAssertEqual(insights.afternoonCount, 2)
    }

    func test_morningAfternoon_noonCountsAsAfternoon() {
        // Exactly noon should be afternoon
        let insights = SipInsights(
            sips: [sip(hour: 12)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.morningCount, 0)
        XCTAssertEqual(insights.afternoonCount, 1)
    }

    func test_morningAfternoon_allMorning() {
        let insights = SipInsights(
            sips: [sip(hour: 7), sip(hour: 8), sip(hour: 9), sip(hour: 11)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.morningCount, 4)
        XCTAssertEqual(insights.afternoonCount, 0)
    }

    func test_morningAfternoon_allAfternoon() {
        let insights = SipInsights(
            sips: [sip(hour: 13), sip(hour: 14), sip(hour: 17)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.morningCount, 0)
        XCTAssertEqual(insights.afternoonCount, 3)
    }

    // MARK: - Hourly Distribution

    func test_hourlyDistribution_correctBuckets() {
        // 2 sips at 9:00, 1 at 9:30, 1 at 14:00
        let insights = SipInsights(
            sips: [sip(hour: 9), sip(hour: 9, minute: 15), sip(hour: 9, minute: 30), sip(hour: 14)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.hourlyDistribution[9], 3)
        XCTAssertEqual(insights.hourlyDistribution[14], 1)
        XCTAssertEqual(insights.hourlyDistribution[10], 0)
    }

    func test_peakHour_correctWithMultipleHours() {
        // 3 sips in hour 9, 1 in hour 14 — peak is 9
        let insights = SipInsights(
            sips: [sip(hour: 9), sip(hour: 9, minute: 15), sip(hour: 9, minute: 30), sip(hour: 14)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.peakHour, 9)
    }

    // MARK: - Unsorted Input

    func test_unsortedInput_producesCorrectResults() {
        // Pass sips out of order — insights should sort internally
        let insights = SipInsights(
            sips: [sip(hour: 14), sip(hour: 8), sip(hour: 11)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.firstSipTimestamp, sip(hour: 8).timestamp)
        XCTAssertEqual(insights.lastSipTimestamp, sip(hour: 14).timestamp)
        XCTAssertEqual(insights.totalCount, 3)
    }

    // MARK: - Description Helpers

    func test_averageIntervalDescription_minutes() {
        // 08:00 and 08:32 — gap of 1920s = 32 min
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 8, minute: 32)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.averageIntervalDescription, "32 min")
    }

    func test_averageIntervalDescription_hoursAndMinutes() {
        // 08:00 and 09:15 — gap of 4500s = 1 hr 15 min
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 9, minute: 15)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.averageIntervalDescription, "1 hr 15 min")
    }

    func test_averageIntervalDescription_exactHour() {
        // 08:00 and 10:00 — gap of 7200s = 2 hr
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 10)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.averageIntervalDescription, "2 hr")
    }

    func test_averageIntervalDescription_nilWhenEmpty() {
        let insights = SipInsights(sips: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertNil(insights.averageIntervalDescription)
    }

    func test_longestGapDescription_nilWhenEmpty() {
        let insights = SipInsights(sips: [], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertNil(insights.longestGapDescription)
    }

    func test_longestGapDescription_value() {
        // 08:00, 09:00, 11:30 — gaps: 3600, 9000 — longest = 9000s = 2 hr 30 min
        let insights = SipInsights(
            sips: [sip(hour: 8), sip(hour: 9), sip(hour: 11, minute: 30)],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.longestGapDescription, "2 hr 30 min")
    }

    // MARK: - Equatable

    func test_equatable_sameInputsAreEqual() {
        let sips = [sip(hour: 9), sip(hour: 10)]
        let a = SipInsights(sips: sips, referenceDate: referenceDate, calendar: utcCalendar)
        let b = SipInsights(sips: sips, referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentInputsAreNotEqual() {
        let a = SipInsights(sips: [sip(hour: 9)], referenceDate: referenceDate, calendar: utcCalendar)
        let b = SipInsights(sips: [sip(hour: 10)], referenceDate: referenceDate, calendar: utcCalendar)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Interval Description Edge Case

    func test_averageIntervalDescription_lessThanOneMinute() {
        // Two sips 30 seconds apart
        let base = sip(hour: 9)
        let close = SipEvent(
            timestamp: base.timestamp + 30,
            duration: 2.0
        )
        let insights = SipInsights(
            sips: [base, close],
            referenceDate: referenceDate,
            calendar: utcCalendar
        )
        XCTAssertEqual(insights.averageIntervalDescription, "<1 min")
    }
}
