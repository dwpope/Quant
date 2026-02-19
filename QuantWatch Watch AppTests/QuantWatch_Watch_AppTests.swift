//
//  QuantWatch_Watch_AppTests.swift
//  QuantWatch Watch AppTests
//
//  Created by Dave Pope on 13/02/2026.
//

import Testing
import WatchConnectivity
@testable import QuantWatch_Watch_App

struct QuantWatch_Watch_AppTests {

    @MainActor
    @Test func nudgeMessageUpdatesLastNudgeTime() async throws {
        let delegate = WatchSessionDelegate()
        #expect(delegate.lastNudgeTime == nil)

        delegate.session(WCSession.default, didReceiveMessage: ["type": "nudge"])
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(delegate.lastNudgeTime != nil)
    }

    @MainActor
    @Test func nonNudgeMessageDoesNotUpdateLastNudgeTime() async throws {
        let delegate = WatchSessionDelegate()
        #expect(delegate.lastNudgeTime == nil)

        delegate.session(WCSession.default, didReceiveMessage: ["type": "heartbeat"])
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(delegate.lastNudgeTime == nil)
    }

    @MainActor
    @Test func activationCallbackUpdatesConnectionState() async throws {
        let delegate = WatchSessionDelegate()

        delegate.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(delegate.isConnected)

        delegate.session(WCSession.default, activationDidCompleteWith: .notActivated, error: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(!delegate.isConnected)
    }

}
