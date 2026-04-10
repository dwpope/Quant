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

    private func persist() {
        guard let data = try? JSONEncoder().encode(sips) else { return }
        try? data.write(to: fileURL(for: todayKey), options: .atomic)
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
