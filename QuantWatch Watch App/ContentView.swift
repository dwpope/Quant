//
//  ContentView.swift
//  QuantWatch Watch App
//
//  Created by Dave Pope on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var sessionDelegate: WatchSessionDelegate

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.stand")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Text("Quant")
                .font(.headline)

            Divider()

            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(sessionDelegate.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(sessionDelegate.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
            }

            // Last nudge received
            if let lastNudge = sessionDelegate.lastNudgeTime {
                Text("Last nudge:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(lastNudge, style: .time)
                    .font(.caption)
            } else {
                Text("No nudges received")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView(sessionDelegate: WatchSessionDelegate())
}
