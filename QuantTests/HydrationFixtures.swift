import Foundation
@testable import Quant

/// Times and drinks for the hydration tests, on 16 November 2026 in London.
protocol HydrationFixtures {}

extension HydrationFixtures {
    var cal: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// `h:m` on 2026-11-`day`.
    func at(_ h: Int, _ m: Int = 0, day: Int = 16) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    /// A drink with a fresh id and no sync data.
    func drink(_ h: Int, _ m: Int, _ ml: Double, source: DrinkSource = .shortcut, day: Int = 16) -> Drink {
        Drink(id: UUID(), at: at(h, m, day: day), millilitres: ml, source: source,
              syncIdentifier: nil, syncVersion: nil)
    }

    /// The mockup's day: six drinks by 14:30, 980 mL in all.
    var mockDay: HydrationDay {
        HydrationDay(drinks: [drink(9, 20, 250), drink(10, 5, 40), drink(10, 40, 180),
                              drink(11, 30, 60), drink(12, 15, 330), drink(14, 18, 120)],
                     day: at(14, 30), calendar: cal)
    }
}
