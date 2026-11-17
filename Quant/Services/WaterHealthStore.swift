import Foundation
import HealthKit

/// Water in Apple Health: what the hydration model reads, saves and deletes. A protocol so the
/// model can be tested without HealthKit.
protocol WaterHealthStore: AnyObject {
    func access() -> HealthAccess
    /// Shows Health's permission sheet, the first time only.
    func requestAccess() async throws
    /// Every source's drinks from `start` up to `end`, oldest first.
    func drinks(from start: Date, to end: Date) async throws -> [Drink]
    /// Saves a drink. One with the same sync identifier and a higher version replaces it.
    func saveDrink(millilitres: Double, at: Date, syncIdentifier: String, syncVersion: Int,
                   userEntered: Bool) async throws
    /// Deletes one of Aware's own drinks.
    func deleteDrink(id: UUID) async throws
    /// Calls `onChange`, on any thread, whenever water in Health changes.
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

/// `WaterHealthStore` on HealthKit: `dietaryWater` in millilitres.
final class HealthKitWaterStore: WaterHealthStore {
    // Teardown only releases stored properties. `nonisolated`, as on every main-actor class
    // AppModel owns: the isolated-deinit shim corrupts the heap in XCTest's dealloc path.
    nonisolated deinit {}

    private let store: HKHealthStore
    private let awareBundleIdentifier: String
    private let water = HKQuantityType(.dietaryWater)
    private let millilitre = HKUnit.literUnit(with: .milli)
    private var observer: HKObserverQuery?

    init(store: HKHealthStore = HKHealthStore(),
         awareBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "net.davepope.Quant") {
        self.store = store
        self.awareBundleIdentifier = awareBundleIdentifier
    }

    /// Health reports only whether Aware may write: whether it may read is kept from apps. So
    /// writing turned off is what reads as "off".
    nonisolated static func access(available: Bool, status: HKAuthorizationStatus) -> HealthAccess {
        guard available else { return .unavailable }
        switch status {
        case .notDetermined: return .notAsked
        case .sharingDenied: return .denied
        case .sharingAuthorized: return .granted
        @unknown default: return .denied
        }
    }

    /// Marks a saved drink: its sync identifier and version, so a later version replaces it,
    /// and whether it was entered by hand.
    nonisolated static func metadata(syncIdentifier: String, syncVersion: Int, userEntered: Bool) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: syncIdentifier,
         HKMetadataKeySyncVersion: NSNumber(value: syncVersion),
         HKMetadataKeyWasUserEntered: NSNumber(value: userEntered)]
    }

    func access() -> HealthAccess {
        Self.access(available: HKHealthStore.isHealthDataAvailable(), status: store.authorizationStatus(for: water))
    }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [water], read: [water])
    }

    func drinks(from start: Date, to end: Date) async throws -> [Drink] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: water, predicate: predicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await query.result(for: store)
        return samples.map { sample in
            let metadata = sample.metadata ?? [:]
            let source = sample.sourceRevision.source
            return Drink(
                id: sample.uuid,
                at: sample.startDate,
                millilitres: sample.quantity.doubleValue(for: millilitre),
                source: DrinkSource.from(bundleIdentifier: source.bundleIdentifier, sourceName: source.name,
                                         wasUserEntered: (metadata[HKMetadataKeyWasUserEntered] as? Bool) ?? true,
                                         awareBundleIdentifier: awareBundleIdentifier),
                syncIdentifier: metadata[HKMetadataKeySyncIdentifier] as? String,
                syncVersion: (metadata[HKMetadataKeySyncVersion] as? NSNumber)?.intValue)
        }
    }

    func saveDrink(millilitres: Double, at: Date, syncIdentifier: String, syncVersion: Int,
                   userEntered: Bool) async throws {
        let sample = HKQuantitySample(
            type: water, quantity: HKQuantity(unit: millilitre, doubleValue: millilitres), start: at, end: at,
            metadata: Self.metadata(syncIdentifier: syncIdentifier, syncVersion: syncVersion, userEntered: userEntered))
        try await store.save(sample)
    }

    func deleteDrink(id: UUID) async throws {
        _ = try await store.deleteObjects(of: water, predicate: HKQuery.predicateForObject(with: id))
    }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        let query = Self.observerQuery(water, onChange: onChange)
        observer = query
        store.execute(query)
    }

    func stopObserving() {
        if let observer { store.stop(observer) }
        observer = nil
    }

    /// Built outside the main actor: HealthKit calls the handler on a queue of its own.
    nonisolated private static func observerQuery(_ type: HKQuantityType,
                                                  onChange: @escaping @Sendable () -> Void) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
            onChange()
            completionHandler()
        }
    }
}
