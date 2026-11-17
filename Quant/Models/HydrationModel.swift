import Combine
import Foundation

/// Why a drink couldn't be added, changed or deleted.
nonisolated enum HydrationError: Error, Equatable {
    /// Health lets Aware change only the drinks it saved itself.
    case notEditable
    /// One of Aware's drinks saved without a sync identifier can't be replaced.
    case noSyncIdentifier
    /// Outside `HydrationModel.amountRange`.
    case amountOutOfRange
}

/// Today's drinks from Apple Health, for the hydration card, the drinks list and the calm row
/// (hydration design §7.4–§7.7).
///
/// It asks for Health access the first time a hydration view appears, reads today's water
/// from every source, and reads it again when Health says water changed (the shortcut, the
/// Health app, another app), every minute, and after each add, change or delete. Only Aware's
/// own drinks can be changed or deleted. It never reminds anyone to drink.
@MainActor
final class HydrationModel: ObservableObject {
    @Published private(set) var day: HydrationDay
    @Published private(set) var access: HealthAccess

    /// What a drink added or changed by hand can hold.
    static let amountRange: ClosedRange<Double> = 10...2000

    private let store: WaterHealthStore
    private let calendar: Calendar
    private let now: () -> Date
    private var hasAsked = false
    private var isObserving = false
    /// Counts reads, so one that finishes after a newer one doesn't overwrite it.
    private var reads = 0

    init(store: WaterHealthStore, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.calendar = calendar
        self.now = now
        day = .empty(day: now(), calendar: calendar)
        access = store.access()
    }

    /// Asks for access if it hasn't been asked, then reads today and keeps up with Health's
    /// changes. Safe to call each time a hydration view appears.
    func start() async {
        access = store.access()
        guard access != .unavailable else { return }
        if access == .notAsked, !hasAsked {
            hasAsked = true
            try? await store.requestAccess()
            access = store.access()
        }
        await refresh()
        if !isObserving {
            isObserving = true
            store.startObserving { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
        }
    }

    /// Reads today's drinks, from midnight to midnight, as the clock has it now: past midnight
    /// that's the new day.
    func refresh() async {
        access = store.access()
        guard access != .unavailable else { return }
        let today = now()
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        reads += 1
        let read = reads
        let drinks = try? await store.drinks(from: start, to: end)
        guard read == reads else { return }
        if let drinks {
            day = HydrationDay(drinks: drinks, day: today, calendar: calendar)
        } else if !calendar.isDate(day.start, inSameDayAs: today) {
            day = .empty(day: today, calendar: calendar)
        }
    }

    /// Reads today again every `interval`, so "12 min ago" and the day itself keep up, until
    /// the task is cancelled.
    func keepRefreshing(every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Saves a drink added by hand, marked as entered by the user.
    func addDrink(millilitres: Double, at time: Date) async throws {
        guard Self.amountRange.contains(millilitres) else { throw HydrationError.amountOutOfRange }
        try await store.saveDrink(millilitres: millilitres, at: time,
                                  syncIdentifier: "aware-manual-\(UUID().uuidString)", syncVersion: 1,
                                  userEntered: true)
        await refresh()
    }

    /// Replaces one of Aware's drinks with the same one holding `millilitres`: the same sync
    /// identifier at the next version, which Health keeps in place of the old.
    func changeAmount(of drink: Drink, to millilitres: Double) async throws {
        guard drink.source.isEditableInAware else { throw HydrationError.notEditable }
        guard let syncIdentifier = drink.syncIdentifier else { throw HydrationError.noSyncIdentifier }
        guard Self.amountRange.contains(millilitres) else { throw HydrationError.amountOutOfRange }
        try await store.saveDrink(millilitres: millilitres, at: drink.at, syncIdentifier: syncIdentifier,
                                  syncVersion: (drink.syncVersion ?? 0) + 1,
                                  userEntered: drink.source != .coaster)
        await refresh()
    }

    func delete(_ drink: Drink) async throws {
        guard drink.source.isEditableInAware else { throw HydrationError.notEditable }
        try await store.deleteDrink(id: drink.id)
        await refresh()
    }
}
