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

    var body: some Scene {
        WindowGroup {
            ContentView(sessionDelegate: sessionDelegate)
                .onAppear {
                    sessionDelegate.requestNotificationPermission()
                }
        }
        // A nudge queued while the app was closed wakes it: the nudge is posted as a
        // notification, the buzz and the message (2026-10-08). Without this the queued nudge
        // waited until the app was next opened.
        .backgroundTask(.watchConnectivity) {
            await WatchSessionDelegate.shared.finishBackgroundDelivery()
        }
    }
}
