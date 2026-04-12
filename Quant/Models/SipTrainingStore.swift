import Combine
import Foundation
import PostureLogic
import SwiftUI

/// Sidecar persistence for `SipTrainingRecord`s captured alongside
/// `SipEvent`s during training mode.
///
/// Structure intentionally mirrors `SipStore`:
/// - Stores today's records only (keyed by `SipEvent.id`).
/// - Persists per-day as `Documents/sip-training-YYYY-MM-DD.json`.
/// - `@MainActor` so SwiftUI views (e.g. the debug overlay) can observe
///   `records` directly.
///
/// Records are stored in a dictionary (not an array) because the join
/// key from `SipStore` is the `SipEvent.id`, and dict lookup is the hot
/// path for `record(for:)`. Persisted as a sorted array of values on
/// disk for stable diffs.
///
/// This entire file, along with the exported JSONL output, can be
/// deleted when training mode is retired.
@MainActor
final class SipTrainingStore: ObservableObject {

    // MARK: - Published State

    /// Today's training records, keyed by `SipEvent.id`.
    @Published private(set) var records: [UUID: SipTrainingRecord] = [:]

    // MARK: - Private

    private let calendar = Calendar.current
    private var todayKey: String { dateKey(for: Date()) }

    // MARK: - Initialization

    init() {
        load()
    }

    // MARK: - Public Methods

    /// Persists a training record. Overwrites any existing record with
    /// the same id (should only happen if a sip is re-labeled after
    /// detection, which shouldn't mutate the features).
    func save(_ record: SipTrainingRecord) {
        records[record.id] = record
        persist()
    }

    /// Retrieves a record by id, or `nil` if no record was captured for
    /// that event (e.g. detected outside training mode).
    func record(for id: UUID) -> SipTrainingRecord? {
        records[id]
    }

    /// Removes a record by id. Intended for pairing with
    /// `SipStore.remove(id:)` when the user deletes a sip.
    func remove(id: UUID) {
        guard records[id] != nil else { return }
        records.removeValue(forKey: id)
        persist()
    }

    /// Builds a labeled training dataset as JSONL for export.
    ///
    /// One JSON object per line, containing `{sip: ..., features: ...}`.
    /// Skips any `SipEvent` that lacks a captured training record (older
    /// events predating training mode) or whose label is `.unconfirmed`
    /// (no human review → don't pollute training data).
    ///
    /// Returns the URL of a temp file inside `Caches`. Ideal for handing
    /// to a `ShareLink`.
    func exportJSONL(for sips: [SipEvent]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var lines: [Data] = []
        for sip in labeledRows(from: sips) {
            lines.append(try encoder.encode(sip))
        }

        let joined = lines
            .map { String(data: $0, encoding: .utf8) ?? "" }
            .joined(separator: "\n")
        let data = Data(joined.utf8)

        let url = cachesFile(name: "sip-training-\(todayKey).jsonl")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Builds a labeled training dataset as a pretty-printed JSON array for
    /// export. Unlike JSONL, nested signal scores and keypoint data are
    /// preserved in their full hierarchical form inside a single document.
    ///
    /// Skips `.unconfirmed` events — same filter as `exportJSONL`.
    ///
    /// Returns the URL of a temp file inside `Caches`. Ideal for handing
    /// to a `ShareLink`.
    func exportJSON(for sips: [SipEvent]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let rows = labeledRows(from: sips)
        let data = try encoder.encode(rows)

        let url = cachesFile(name: "sip-training-\(todayKey).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Shared helpers

    /// Returns ExportRows for all reviewed (non-unconfirmed) sips that have
    /// a captured training record. Both JSONL and JSON export use this filter.
    private func labeledRows(from sips: [SipEvent]) -> [ExportRow] {
        sips.compactMap { sip in
            guard sip.label != .unconfirmed, let record = records[sip.id] else { return nil }
            return ExportRow(sip: sip, features: record)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL(for: todayKey)),
              let decoded = try? JSONDecoder().decode([SipTrainingRecord].self, from: data)
        else { return }
        records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persist() {
        // Sort by capturedAt so the on-disk file has stable ordering.
        let sorted = records.values.sorted { $0.capturedAt < $1.capturedAt }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: fileURL(for: todayKey), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sip-training-\(key).json")
    }

    private func cachesFile(name: String) -> URL {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(name)
    }

    private func dateKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Export row

/// One line of the exported JSONL file. Kept private to the store —
/// consumers only need the URL returned by `exportJSONL`.
private struct ExportRow: Encodable {
    let sip: SipEvent
    let features: SipTrainingRecord
}
