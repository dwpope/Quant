//
//  QuantWatchApp.swift
//  QuantWatch Watch App
//
//  Created by Dave Pope on 13/02/2026.
//

import SwiftUI

@main
struct QuantWatch_Watch_AppApp: App {
    /// Created with the app, so the session is activated even on a background launch.
    private let sessionDelegate = WatchSessionDelegate.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(sessionDelegate: sessionDelegate)
                .onAppear {
                    sessionDelegate.requestNotificationPermission()
                }
        }
        // Opening the app keeps it running for the next hour, so nudges arrive on time
        // (2026-10-10). watchOS only starts that for an app that's open.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { WristNudgeSession.shared.appBecameActive() }
        }
        // A nudge queued while the app was closed wakes it: the nudge is posted as a
        // notification, the buzz and the message (2026-10-08). Without this the queued nudge
        // waited until the app was next opened.
        .backgroundTask(.watchConnectivity) {
            await WatchSessionDelegate.shared.finishBackgroundDelivery()
        }
    }
}
