//
//  NudgeRepeats.swift
//  QuantWatch Watch App
//
//  A nudge shows once.
//

import Foundation

/// The nudges already shown, by when the phone sent them (2026-11-17).
///
/// The phone sends a nudge straight to the open app and, if that send reports an error, queues
/// it as well. On 11-17 a send reported an error after it had arrived, and the Watch buzzed and
/// posted the nudge twice. Both copies carry the same `sentAt`, so the second is a repeat.
struct NudgeRepeats {

    /// How many are kept. A repeat comes within a second of its first copy.
    static let kept = 20

    private var shown: [Date] = []

    /// True the first time a nudge comes, and records it; false when it comes again. A nudge
    /// without a `sentAt` (an older phone build) always shows, as before.
    mutating func isNew(sentAt: Date?) -> Bool {
        guard let sentAt else { return true }
        guard !shown.contains(sentAt) else { return false }
        shown.append(sentAt)
        if shown.count > Self.kept { shown.removeFirst() }
        return true
    }
}
