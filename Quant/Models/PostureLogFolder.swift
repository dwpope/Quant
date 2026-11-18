import Combine
import Foundation

/// A folder the posture log is copied into as it's written, chosen in Files (2026-11-17).
///
/// Dave sent each day's log by hand: export, share, upload. With a folder in iCloud Drive
/// chosen here, each day's file reaches his Mac by itself, where a session can read it. His
/// Mac's Documents are in iCloud Drive, so it can be the folder the earlier logs are kept in.
/// iOS opens only the folder he picks to the app, and a bookmark keeps it open across launches.
/// A copy is made when the folder is chosen, at most every `saveEvery` while frames come in, and
/// when the app goes to the background.
@MainActor
final class PostureLogFolder: ObservableObject {

    nonisolated deinit {}

    /// The chosen folder's name; nil when none is chosen.
    @Published private(set) var name: String?
    /// When the last copy was made, since launch.
    @Published private(set) var lastSaved: Date?
    /// Why the last copy failed; nil once one works.
    @Published private(set) var problem: String?

    static let saveEvery: TimeInterval = 300

    static let bookmarkKey = "com.quant.postureLog.folder.bookmark"
    static let nameKey = "com.quant.postureLog.folder.name"

    private let store: PostureLogStore
    private let defaults: UserDefaults
    private var lastAttempt: Date?

    init(store: PostureLogStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        name = defaults.string(forKey: Self.nameKey)
    }

    /// Whether a frame should start a copy, `saveEvery` after the last one began.
    static func isDue(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= saveEvery
    }

    /// Keeps `url`, as Files hands it over, and copies the log there straight away.
    func choose(_ url: URL) async {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                   includingResourceValuesForKeys: nil, relativeTo: nil)
        else {
            problem = "Couldn't keep that folder. Choose it again."
            return
        }
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: Self.nameKey)
        name = url.lastPathComponent
        lastSaved = nil
        await save()
    }

    func stop() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.nameKey)
        name = nil
        lastSaved = nil
        problem = nil
    }

    /// A copy, if one is due: each frame asks.
    func saveIfDue(now: Date = Date()) {
        guard name != nil, Self.isDue(lastAttempt: lastAttempt, now: now) else { return }
        lastAttempt = now
        Task { await save() }
    }

    func save() async {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        lastAttempt = max(lastAttempt ?? .distantPast, Date())
        let folder: URL
        do {
            var stale = false
            folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
            if stale { renew(bookmark: folder) }
        } catch {
            problem = "Can't find \(name ?? "the folder"). Choose it again."
            return
        }
        do {
            _ = try await store.copy(to: folder)
            lastSaved = Date()
            problem = nil
        } catch {
            problem = "Can't save to \(name ?? folder.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// A bookmark that still finds its folder but says it's out of date, as after the folder
    /// is renamed, is made again while it still works.
    private func renew(bookmark folder: URL) {
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        if let fresh = try? folder.bookmarkData(options: .minimalBookmark,
                                                includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
            defaults.set(folder.lastPathComponent, forKey: Self.nameKey)
            name = folder.lastPathComponent
        }
    }
}
