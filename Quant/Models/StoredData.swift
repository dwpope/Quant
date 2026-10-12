import Foundation

/// What the app keeps in Documents, day by day, and deleting the older part (2026-10-11).
///
/// Every store writes one file a day, and nothing was ever deleted: Dave asked for a scan at
/// launch and a way to delete older data. Off the main actor: the scan and deletes run in the
/// background. Only the app's own daily data is touched, never the
/// calibration baseline or settings. Today's files are never offered: they're being written.
nonisolated enum StoredData {

    enum Kind: String, CaseIterable {
        case postureLog
        case jevComparisons
        case sips
        case sipTraining
        case recording
        case jevExport

        var label: String {
            switch self {
            case .postureLog: return "Posture logs"
            case .jevComparisons: return "Jev comparisons"
            case .sips: return "Sips"
            case .sipTraining: return "Sip training data"
            case .recording: return "Posture recordings"
            case .jevExport: return "Jev exports"
            }
        }

        /// The file-name prefix each store writes. A dated name ends `-YYYY-MM-DD.json(l)`.
        fileprivate static func of(name: String) -> Kind? {
            if name.hasPrefix("posture-log-") { return .postureLog }
            if name.hasPrefix("jev-comparisons-") { return .jevComparisons }
            if name.hasPrefix("sip-training-") { return .sipTraining }
            if name.hasPrefix("sips-") { return .sips }
            if name.hasPrefix("posture-session-") { return .recording }
            return nil
        }
    }

    struct Item: Equatable {
        let url: URL
        let kind: Kind
        /// The day it holds: from the name when it's dated, else when it was last written.
        let day: Date
        let bytes: Int64
    }

    struct Summary: Equatable {
        struct Line: Equatable {
            let kind: Kind
            let count: Int
            let bytes: Int64
        }

        let byKind: [Line]
        let totalBytes: Int64

        init(items: [Item]) {
            byKind = Kind.allCases.compactMap { kind in
                let mine = items.filter { $0.kind == kind }
                guard !mine.isEmpty else { return nil }
                return Line(kind: kind, count: mine.count, bytes: mine.reduce(0) { $0 + $1.bytes })
            }
            .sorted { $0.bytes > $1.bytes }
            totalBytes = items.reduce(0) { $0 + $1.bytes }
        }
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Every item of the app's daily data in `folder`. Reads sizes and names only, not contents,
    /// so it's quick; still, run it off the main thread.
    static func scan(folder: URL = documents, calendar: Calendar = .current) -> [Item] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        var items: [Item] = []
        for url in entries {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .distantPast
            if values?.isDirectory == true {
                guard name == "jev-archive" else { continue }
                let exports = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
                for export in exports {
                    let date = (try? export.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    items.append(Item(url: export, kind: .jevExport, day: date, bytes: size(of: export)))
                }
                continue
            }
            guard let kind = Kind.of(name: name) else { continue }
            let day = dayInName(name, calendar: calendar) ?? modified
            items.append(Item(url: url, kind: kind, day: day, bytes: Int64(values?.fileSize ?? 0)))
        }
        return items.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// Items from before the last `days` whole days; never today's. "Older than 30 days" on
    /// 11 October keeps 11 September onwards.
    static func olderThan(days: Int, in items: [Item], now: Date = Date(),
                          calendar: Calendar = .current) -> [Item] {
        let today = calendar.startOfDay(for: now)
        let keepFrom = calendar.date(byAdding: .day, value: -max(days, 0), to: today) ?? today
        return items.filter { calendar.startOfDay(for: $0.day) < keepFrom }
    }

    /// Deletes the items. Returns the bytes freed.
    @discardableResult
    static func delete(_ items: [Item]) -> Int64 {
        var freed: Int64 = 0
        for item in items where (try? FileManager.default.removeItem(at: item.url)) != nil {
            freed += item.bytes
        }
        return freed
    }

    // MARK: - Helpers

    /// The `YYYY-MM-DD` in a dated name, as that day's start.
    private static func dayInName(_ name: String, calendar: Calendar) -> Date? {
        guard let range = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        let parts = name[range].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func size(of folder: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = files?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
