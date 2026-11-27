//
//  SessionMark.swift
//  QuantWatch Watch App
//
//  Marking moments of a session from the wrist.
//

import Foundation

/// A moment Dave marks during a session (2026-11-27), so the posture log says when he looked
/// down, craned, moved his seat, yawned, felt sluggish or sat well, instead of his remembering.
/// The phone's `WatchConnectivityService.sessionMark(from:)` reads the message; a mark is a note
/// only, never a recalibration or an answer.
enum SessionMark: String, CaseIterable, Identifiable {
    case lookingDown, craning, movedSeat, yawning, sluggish, sittingWell

    var id: String { rawValue }

    /// One word, to fit a tile.
    var title: String {
        switch self {
        case .lookingDown: return "Down"
        case .craning: return "Crane"
        case .movedSeat: return "Seat"
        case .yawning: return "Yawn"
        case .sluggish: return "Tired"
        case .sittingWell: return "Good"
        }
    }

    var symbol: String {
        switch self {
        case .lookingDown: return "arrow.down.circle"
        case .craning: return "arrow.forward.circle"
        case .movedSeat: return "chair"
        case .yawning: return "mouth"
        case .sluggish: return "tortoise"
        case .sittingWell: return "checkmark.circle"
        }
    }

    /// The mark for the phone, dated at the tap: a queued one can arrive minutes later.
    static func message(_ mark: SessionMark, at: Date) -> [String: Any] {
        ["type": "mark", "what": mark.rawValue, "at": at.timeIntervalSince1970]
    }
}
