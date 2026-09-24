import Combine
import Foundation
import PostureLogic
import SwiftUI

// This ships. A Release build DOES contain this store, the call site and the Jev UI — the
// `#if DEBUG` gate was removed on 2026-09-24 so the experiment can be run from TestFlight.
//
// Consequence worth knowing before reading further: on any device where a tester enables the
// classifier, this writes camera-derived posture records — the exact payload sent, plus the
// calibration baseline — to the app's Documents directory as `jev-comparisons-YYYY-MM-DD.json`.
// That container is sandbox-private and has no file-sharing key, but it is included in device
// backups, and nothing prunes old files.

/// One moment where Jev and the threshold engine both had an opinion, plus what Dave said.
///
/// This is step 3c's dataset, and it is deliberately self-contained: it must answer "was Jev
/// better than the thresholds here?" **without re-running anything**. Hence two things that look
/// redundant and are not:
///
/// - `features` is the exact payload that was sent, not the raw sample. What Jev saw is what
///   matters, including the normalisation applied to it.
/// - `baseline` is kept alongside, because every metric in `features` is a delta from it. The
///   live baseline is cleared on recalibration and treated as stale after an hour, so a record
///   without it becomes uninterpretable within the hour. Same reasoning as `SessionMetadata
///   .baseline` in step 3a.
///
/// Note what is deliberately NOT claimed: `thresholdState` is a temporal state
/// (good/drifting/bad) while `jev.posture` is a morphological class (slouch/lean/chair_swivel).
/// They are not the same kind of thing, so the record stores both verbatim and lets the human
/// adjudicate rather than pretending to a like-for-like comparison.
// Not `Equatable`: `Baseline` is not, and nothing here needs record equality. Widening a
// core PostureLogic model to satisfy a convenience would be the wrong trade.
struct JevComparisonRecord: Codable, Identifiable {

    /// Who was right, in Dave's judgement. The only ground truth available here — he is present
    /// and in the chair, which no stored signal can substitute for.
    enum UserVerdict: String, Codable, CaseIterable {
        case jevWasRight
        case thresholdsWereRight
        case bothWrong
    }

    let id: UUID
    let capturedAt: Date
    /// Exactly what was sent to the proxy.
    let features: JevFeatures
    /// What those deltas were relative to. Unrecoverable later; see the type doc.
    let baseline: Baseline
    /// The threshold engine's state at the same moment.
    let thresholdState: PostureState
    /// The verdict, or `nil` when the call failed — which is itself evidence that Jev was
    /// unavailable at a moment the thresholds had an opinion.
    let jev: JevVerdict?
    let jevError: String?
    var userVerdict: UserVerdict?
    /// What the posture actually was, when both sides got it wrong.
    var trueClass: TagLabel?

    init(
        id: UUID,
        capturedAt: Date,
        features: JevFeatures,
        baseline: Baseline,
        thresholdState: PostureState,
        jev: JevVerdict?,
        jevError: String?,
        userVerdict: UserVerdict? = nil,
        trueClass: TagLabel? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.features = features
        self.baseline = baseline
        self.thresholdState = thresholdState
        self.jev = jev
        self.jevError = jevError
        self.userVerdict = userVerdict
        self.trueClass = trueClass
    }
}

/// Persists and exposes today's Jev-vs-thresholds comparisons.
///
/// Stored per-day in Documents as `jev-comparisons-YYYY-MM-DD.json`, following `SipStore`
/// exactly — same per-day key, same best-effort load, same static serial write queue, same
/// `flushPendingWrites` test hook. Deliberately not a new pattern.
@MainActor
final class JevComparisonStore: ObservableObject {

    // Teardown only releases stored properties; it touches no main-actor state.
    // Marking it `nonisolated` keeps Swift's MainActor isolated-deinit back-deploy shim out of
    // XCTest's NSInvocation-driven dealloc path, which otherwise corrupts the heap and aborts
    // under Xcode 26 / iOS 26.
    nonisolated deinit {}

    /// Today's comparisons, oldest first.
    @Published private(set) var comparisons: [JevComparisonRecord] = []

    /// How many comparisons Dave has adjudicated today — the number that actually matters for 3c.
    var adjudicatedCount: Int { comparisons.filter { $0.userVerdict != nil }.count }

    private let calendar = Calendar.current
    private var todayKey: String { dateKey(for: Date()) }

    init() {
        load()
    }

    func add(_ record: JevComparisonRecord) {
        comparisons.append(record)
        comparisons.sort { $0.capturedAt < $1.capturedAt }
        persist()
    }

    /// Records who was right. No-op for an unknown id, so a stale tap cannot corrupt the set.
    func setUserVerdict(id: UUID, verdict: JevComparisonRecord.UserVerdict, trueClass: TagLabel?) {
        guard let idx = comparisons.firstIndex(where: { $0.id == id }) else { return }
        comparisons[idx].userVerdict = verdict
        comparisons[idx].trueClass = trueClass
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL(for: todayKey)),
              let decoded = try? JSONDecoder().decode([JevComparisonRecord].self, from: data)
        else { return }
        comparisons = decoded.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Serial utility queue for disk writes. Static so every instance writing the same per-day
    /// file shares one ordered queue — the file on disk is always the latest snapshot.
    private static let persistQueue = DispatchQueue(label: "com.quant.jevComparisonStore.persist",
                                                    qos: .utility)

    private func persist() {
        let snapshot = comparisons
        let url = fileURL(for: todayKey)
        Self.persistQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Blocks until queued writes complete. Test hook only.
    static func flushPendingWrites() {
        persistQueue.sync {}
    }

    private func fileURL(for key: String) -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jev-comparisons-\(key).json")
    }

    private func dateKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
