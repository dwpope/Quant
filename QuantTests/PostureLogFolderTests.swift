import XCTest
import UIKit
import PostureLogic
@testable import Quant

/// The posture log copied into a folder Dave chooses, as it's written (2026-11-17).
///
/// He sent each day's log by hand (export, share, upload), so a session only saw it when he
/// remembered. With a folder chosen in iCloud Drive, each day's file reaches his Mac on its own.
/// His Mac's Documents are in iCloud Drive, so it can be the folder the earlier logs are kept in.
@MainActor
final class PostureLogFolderTests: XCTestCase {

    private var documents: URL { PostureLogStore.documents }
    private var folder: URL!
    private var defaults: UserDefaults!
    private let suite = "PostureLogFolderTests"

    private func clean() {
        PostureLogStore.flushPendingWrites()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        where name.hasPrefix("posture-log-") {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }

    override func setUpWithError() throws {
        clean()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("chosen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        clean()
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    private var today: String { PostureLogStore.dayKey(for: Date()) }

    private func copied(_ day: String) -> String? {
        try? String(contentsOf: folder.appendingPathComponent("posture-log-\(day).jsonl"), encoding: .utf8)
    }

    private func local(_ day: String) -> String? {
        PostureLogStore.flushPendingWrites()
        return try? String(contentsOf: documents.appendingPathComponent("posture-log-\(day).jsonl"), encoding: .utf8)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: - Copying the days

    func test_eachDaysLog_isCopiedToTheFolder() async throws {
        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 1, kind: "state", value: "good")])
        try Data("{\"t\":0,\"kind\":\"state\",\"value\":\"bad\"}\n".utf8)
            .write(to: documents.appendingPathComponent("posture-log-2026-11-10.jsonl"))

        let names = try await store.copy(to: folder)

        XCTAssertEqual(Set(names), ["posture-log-\(today).jsonl", "posture-log-2026-11-10.jsonl"])
        XCTAssertEqual(copied(today), local(today))
        XCTAssertEqual(copied("2026-11-10"), local("2026-11-10"))
    }

    /// Lines are only added, so a day the same size as its copy hasn't changed.
    func test_onlyADayThatChanged_isCopiedAgain() async throws {
        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 1, kind: "state", value: "good")])
        try Data("{\"t\":0,\"kind\":\"state\",\"value\":\"bad\"}\n".utf8)
            .write(to: documents.appendingPathComponent("posture-log-2026-11-10.jsonl"))
        _ = try await store.copy(to: folder)

        store.append([PostureLogEvent(t: 2, kind: "state", value: "drifting")])
        let names = try await store.copy(to: folder)

        XCTAssertEqual(names, ["posture-log-\(today).jsonl"])
        XCTAssertEqual(copied(today), local(today))
    }

    /// The folder can be the one the earlier logs and exports are kept in.
    func test_otherFilesInTheFolder_areLeftAlone() async throws {
        let notes = folder.appendingPathComponent("notes.md")
        let export = folder.appendingPathComponent("posture-log-to-2026-11-16.jsonl")
        try Data("mine".utf8).write(to: notes)
        try Data("an export".utf8).write(to: export)
        let store = PostureLogStore()
        store.append([PostureLogEvent(t: 1, kind: "state", value: "good")])

        _ = try await store.copy(to: folder)

        XCTAssertEqual(try String(contentsOf: notes, encoding: .utf8), "mine")
        XCTAssertEqual(try String(contentsOf: export, encoding: .utf8), "an export")
    }

    // MARK: - The chosen folder

    func test_choosingAFolder_copiesStraightAway() async throws {
        PostureLogStore().append([PostureLogEvent(t: 1, kind: "state", value: "good")])
        let chosen = PostureLogFolder(store: PostureLogStore(), defaults: defaults)

        await chosen.choose(folder)

        XCTAssertEqual(chosen.name, folder.lastPathComponent)
        XCTAssertNotNil(chosen.lastSaved)
        XCTAssertNil(chosen.problem)
        XCTAssertEqual(copied(today), local(today))
    }

    /// iOS only lets the app into the folder Dave picked; a bookmark keeps it across launches.
    func test_theFolder_isRememberedAcrossLaunches() async throws {
        await PostureLogFolder(store: PostureLogStore(), defaults: defaults).choose(folder)
        PostureLogStore().append([PostureLogEvent(t: 2, kind: "state", value: "bad")])

        let relaunched = PostureLogFolder(store: PostureLogStore(), defaults: defaults)
        XCTAssertEqual(relaunched.name, folder.lastPathComponent)
        await relaunched.save()
        XCTAssertEqual(copied(today), local(today))
    }

    func test_stoppingSaving_forgetsTheFolder() async throws {
        let chosen = PostureLogFolder(store: PostureLogStore(), defaults: defaults)
        await chosen.choose(folder)

        chosen.stop()

        XCTAssertNil(chosen.name)
        XCTAssertNil(PostureLogFolder(store: PostureLogStore(), defaults: defaults).name)
    }

    /// Moved or deleted, the folder can't be written to, and the settings say so. It stays chosen:
    /// iCloud Drive can be out of reach for a while.
    func test_aFolderThatCantBeReached_saysSo() async throws {
        let chosen = PostureLogFolder(store: PostureLogStore(), defaults: defaults)
        await chosen.choose(folder)
        try FileManager.default.removeItem(at: folder)
        PostureLogStore().append([PostureLogEvent(t: 2, kind: "state", value: "bad")])

        await chosen.save()

        XCTAssertNotNil(chosen.problem)
        XCTAssertEqual(chosen.name, folder.lastPathComponent)
    }

    // MARK: - When it copies

    /// While frames come in, at most every 5 minutes: each frame asks.
    func test_whileFramesComeIn_aCopyIsDueEvery5Minutes() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(PostureLogFolder.isDue(lastAttempt: nil, now: t0))
        XCTAssertFalse(PostureLogFolder.isDue(lastAttempt: t0, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(PostureLogFolder.isDue(lastAttempt: t0, now: t0.addingTimeInterval(300)))
    }

    /// The app's frames ask for a copy once one is due.
    func test_aFrame_copiesOnceACopyIsDue() async throws {
        let model = AppModel()
        defer { model.postureLogFolder.stop() }
        await model.postureLogFolder.choose(folder)
        model.postureLogStore.append([PostureLogEvent(t: 2, kind: "state", value: "bad")])

        model.logFrame(decision: .none, now: Date().addingTimeInterval(PostureLogFolder.saveEvery))

        try await waitFor { self.copied(self.today) == self.local(self.today) }
        XCTAssertEqual(copied(today), local(today))
    }

    /// Going to the background copies too, so the day so far is there as Dave leaves his desk.
    func test_goingToTheBackground_copies() async throws {
        let model = AppModel()
        defer { model.postureLogFolder.stop() }
        await model.postureLogFolder.choose(folder)
        model.postureLogStore.append([PostureLogEvent(t: 2, kind: "state", value: "bad")])

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        try await waitFor { self.copied(self.today) == self.local(self.today) }
        XCTAssertEqual(copied(today), local(today))
    }
}
