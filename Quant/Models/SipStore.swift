import Combine
import Foundation
import PostureLogic
import SwiftUI

/// Persists and exposes today's sip events.
///
/// Sips are stored per-day in the app's Documents directory as a JSON file
/// named `sips-YYYY-MM-DD.json`. Only today's file is loaded at startup;
/// old files are not automatically pruned (they're small).
///
/// All mutations happen on the MainActor so `sips` can be observed directly
/// by SwiftUI views.
@MainActor
final class SipStore: ObservableObject {

    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit
    // back-deploy shim out of XCTest's NSInvocation-driven dealloc path, which
    // otherwise corrupts the heap and aborts under Xcode 26 / iOS 26.
    nonisolated deinit {}

    // MARK: - Published State

    /// Today's sip events, sorted chronologically.
    @Published private(set) var sips: [SipEvent] = []

    // MARK: - Computed

    /// Number of sips recorded today.
    var sipCount: Int { sips.count }

    /// Timestamp of the most recent sip, or `nil` if none today.
    var lastSipTimestamp: TimeInterval? { sips.last?.timestamp }

    // MARK: - Private

    private let calendar = Calendar.current
    private var todayKey: String { dateKey(for: Date()) }

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Public Methods

    /// Records a confirmed sip. Appends to `sips` and persists immediately.
    func add(_ event: SipEvent) {
        sips.append(event)
        sips.sort { $0.timestamp < $1.timestamp }
        persist()
    }

    /// Removes the sip with the given ID. Used by the swipe-to-delete UI.
    func remove(id: UUID) {
        sips.removeAll { $0.id == id }
        persist()
    }

    /// Removes sips at the given index set (for `List` `onDelete`).
    func remove(at offsets: IndexSet) {
        sips.remove(atOffsets: offsets)
        persist()
    }

    /// Applies a training-mode label to the sip with the given ID. No-op if
    /// the ID isn't in today's store. Passing `nil` clears any existing
    /// label. Used by both the confirmation popup and the explicit "Label…"
    /// action in `SipTimelineView`.
    func setLabel(id: UUID, label: SipEvent.Label?) {
        guard let idx = sips.firstIndex(where: { $0.id == id }) else { return }
        sips[idx] = sips[idx].withLabel(label)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL(for: todayKey)),
              let decoded = try? JSONDecoder().decode([SipEvent].self, from: data)
        else { return }
        sips = decoded.sorted { $0.timestamp < $1.timestamp }
    }

    /// Serial utility queue for disk writes: sips are confirmed on the
    /// MainActor mid-session, and encoding + an atomic file write there blocks
    /// the UI. Static so every instance writing the same per-day file shares
    /// one ordered queue — the file on disk is always the latest snapshot.
    private static let persistQueue = DispatchQueue(label: "com.quant.sipStore.persist", qos: .utility)

    private func persist() {
        let snapshot = sips
        let url = fileURL(for: todayKey)
        Self.persistQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Blocks until all queued disk writes have completed. Test hook — lets
    /// persistence round-trip tests reload (and tear down) deterministically;
    /// production code never needs to wait on the queue.
    static func flushPendingWrites() {
        persistQueue.sync {}
    }

    private func fileURL(for key: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sips-\(key).json")
    }

    private func dateKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
