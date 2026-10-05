//
//  NudgeMessage.swift
//  QuantWatch Watch App
//
//  What a nudge says on the wrist.
//

import Foundation

/// The line a nudge shows. The phone sends its reason's coaching line, such as "Turn your chair
/// to face that screen" for a head held turned; a phone on an older build sends none, and the
/// Watch says what it always said.
enum NudgeMessage {
    static let fallbackBody = "Straighten up!"

    static func body(from message: [String: Any]) -> String {
        guard let body = message["body"] as? String, !body.isEmpty else { return fallbackBody }
        return body
    }
}
