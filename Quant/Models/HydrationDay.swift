import Foundation

/// Whether Aware may read and write water in Apple Health.
nonisolated enum HealthAccess: Equatable, Sendable {
    /// No Health on this device (an iPad without it, say).
    case unavailable
    /// Aware hasn't asked yet.
    case notAsked
    /// Asked, and writing water was turned off. Health hides whether reading was allowed.
    case denied
    case granted
}

/// Where a drink in Apple Health came from.
nonisolated enum DrinkSource: Hashable, Sendable {
    /// Weighed by the coaster and saved by Aware.
    case coaster
    /// Added by hand in Aware's drinks list.
    case addedInAware
    /// The Home Screen shortcut.
    case shortcut
    /// Any other app, by its name in Health.
    case otherApp(String)

    static let shortcutsBundleIdentifier = "com.apple.shortcuts"

    var label: String {
        switch self {
        case .coaster: return "Coaster"
        case .addedInAware: return "Added in Aware"
        case .shortcut: return "Shortcut"
        case .otherApp(let name): return name
        }
    }

    /// Health lets an app change or delete only the samples it saved itself.
    var isEditableInAware: Bool {
        switch self {
        case .coaster, .addedInAware: return true
        case .shortcut, .otherApp: return false
        }
    }

    /// Aware saves both its own kinds: a drink added by hand is marked as entered by the user,
    /// and a coaster's isn't.
    static func from(bundleIdentifier: String, sourceName: String, wasUserEntered: Bool,
                     awareBundleIdentifier: String) -> DrinkSource {
        if bundleIdentifier == awareBundleIdentifier { return wasUserEntered ? .addedInAware : .coaster }
        if bundleIdentifier == shortcutsBundleIdentifier { return .shortcut }
        return .otherApp(sourceName)
    }
}

/// One drink of water, as Apple Health has it.
nonisolated struct Drink: Identifiable, Equatable, Sendable {
    /// The Health sample's id.
    let id: UUID
    let at: Date
    let millilitres: Double
    let source: DrinkSource
    /// Set on the drinks Aware saved, so an edit can replace the sample rather than add one.
    let syncIdentifier: String?
    let syncVersion: Int?
}

/// One day's drinking, and every number and line the hydration card, the drinks list and the
/// calm view's row show (hydration design §7.4–§7.7). Pure, so all of it is tested.
///
/// The goal and the pace are fixed: 2 L a day, and a pace line from 0 at 09:00 rising straight
/// to 1.5 L at 17:00, then flat. There's no setting for either, and no reminder.
nonisolated struct HydrationDay: Equatable, Sendable {
    static let goalMillilitres = 2000.0
    static let paceStartHour = 9
    static let paceEndHour = 17
    static let paceTargetMillilitres = 1500.0

    /// A point on the chart: a time and a running amount.
    struct Step: Equatable, Sendable {
        let at: Date
        let millilitres: Double
    }

    /// The day's drinks with some water in them, oldest first.
    let drinks: [Drink]
    /// Midnight at the day's start.
    let start: Date
    private let calendar: Calendar

    /// Keeps only `day`'s drinks with more than 0 mL, oldest first.
    init(drinks: [Drink], day: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        start = calendar.startOfDay(for: day)
        self.drinks = drinks
            .filter { $0.millilitres > 0 && calendar.isDate($0.at, inSameDayAs: day) }
            .sorted { $0.at < $1.at }
    }

    static func empty(day: Date, calendar: Calendar = .current) -> HydrationDay {
        HydrationDay(drinks: [], day: day, calendar: calendar)
    }

    var totalMillilitres: Double { drinks.reduce(0) { $0 + $1.millilitres } }

    var lastDrink: Drink? { drinks.last }

    /// The chart's top: the goal, or the total once it's past the goal, so nothing is clipped.
    var yMax: Double { max(Self.goalMillilitres, totalMillilitres) }

    /// "980 mL of 2 L".
    var headline: String {
        "\(Self.volumeLabel(totalMillilitres)) of \(Self.volumeLabel(Self.goalMillilitres))"
    }

    /// "Last drink 12 min ago · 6 drinks".
    func detailLine(now: Date) -> String {
        guard let last = lastDrink else { return "No drinks yet today" }
        let count = drinks.count == 1 ? "1 drink" : "\(drinks.count) drinks"
        return "Last drink \(Self.agoLabel(from: last.at, now: now)) · \(count)"
    }

    /// "980 mL · last drink 12 min ago", for the calm view.
    func calmLine(now: Date) -> String {
        guard let last = lastDrink else { return "No drinks yet today" }
        return "\(Self.volumeLabel(totalMillilitres)) · last drink \(Self.agoLabel(from: last.at, now: now))"
    }

    // MARK: - The chart

    /// Where the pace line is at `time`: 0 until 09:00, a straight rise to 1.5 L at 17:00, then flat.
    func paceMillilitres(at time: Date) -> Double {
        let from = clock(Self.paceStartHour), to = clock(Self.paceEndHour)
        if time <= from { return 0 }
        if time >= to { return Self.paceTargetMillilitres }
        return Self.paceTargetMillilitres * time.timeIntervalSince(from) / to.timeIntervalSince(from)
    }

    /// The pace line across `span`: its two ends, and 09:00 and 17:00 where they fall inside it.
    func pacePoints(in span: ClosedRange<Date>) -> [Step] {
        let bends = [Self.paceStartHour, Self.paceEndHour].map(clock)
            .filter { span.lowerBound < $0 && $0 < span.upperBound }
        return ([span.lowerBound] + bends + [span.upperBound])
            .sorted()
            .map { Step(at: $0, millilitres: paceMillilitres(at: $0)) }
    }

    /// The rising total from `from` to `to`: what was drunk by `from`, a step at each drink
    /// after it, and the total at `to`.
    func runningTotal(from: Date, to: Date) -> [Step] {
        var total = drinks.filter { $0.at <= from }.reduce(0) { $0 + $1.millilitres }
        var steps = [Step(at: from, millilitres: total)]
        for drink in drinks where drink.at > from && drink.at <= to {
            total += drink.millilitres
            steps.append(Step(at: drink.at, millilitres: total))
        }
        steps.append(Step(at: to, millilitres: total))
        return steps
    }

    /// The chart's time span. It follows the posture band's, stretched to take in any drink
    /// outside it. With no posture today it runs from 09:00 (or the first drink, or an hour ago,
    /// if earlier) to now.
    func chartSpan(postureSpan: ClosedRange<Date>?, now: Date) -> ClosedRange<Date> {
        let first = drinks.first?.at, last = drinks.last?.at
        if let posture = postureSpan {
            return min(posture.lowerBound, first ?? posture.lowerBound)
                ... max(posture.upperBound, last ?? posture.upperBound)
        }
        let lower = [clock(Self.paceStartHour), first ?? .distantFuture, now.addingTimeInterval(-3600)].min()!
        return lower...max(now, last ?? now)
    }

    /// The day's away stretches in the posture band, for the chart's grey shading.
    static func awayStretches(_ segments: [PostureTimeline.Segment]) -> [ClosedRange<Date>] {
        segments.filter { $0.band == .away && $0.start <= $0.end }.map { $0.start...$0.end }
    }

    /// `hour`:00 on this day, by the clock on the wall.
    private func clock(_ hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(hour) * 3600)
    }

    // MARK: - Words

    /// "980 mL" under a litre, then "1.2 L", or "2 L" when the tenth is 0.
    static func volumeLabel(_ millilitres: Double) -> String {
        let rounded = millilitres.rounded()
        if rounded < 1000 { return "\(Int(rounded)) mL" }
        let litres = (rounded / 100).rounded() / 10
        return litres == litres.rounded() ? "\(Int(litres)) L" : String(format: "%.1f L", litres)
    }

    /// "just now", "12 min ago", "2 h ago", "1 h 25 min ago".
    static func agoLabel(from: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(from))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h ago" : "\(hours) h \(rest) min ago"
    }

    /// What the card says about Health access, when there's something to say.
    static func accessNote(_ access: HealthAccess) -> String? {
        switch access {
        case .unavailable: return "Apple Health isn't available on this device"
        case .denied: return "Apple Health is off for Aware. Turn it on in Settings › Health › Data Access & Devices."
        case .notAsked, .granted: return nil
        }
    }

    /// The calm view's row: none without Health, a short note when it's off, else the day.
    static func calmRow(day: HydrationDay, access: HealthAccess, now: Date) -> String? {
        switch access {
        case .unavailable: return nil
        case .denied: return "Apple Health is off"
        case .notAsked, .granted: return day.calmLine(now: now)
        }
    }
}
