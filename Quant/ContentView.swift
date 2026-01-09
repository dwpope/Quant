//
//  ContentView.swift
//  Quant
//
//  Created by Learning on 27/12/2025.
//

import SwiftUI
import PostureLogic

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        ZStack {
            VStack {
                Image(systemName: "person.fill.viewfinder")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Quant: Posture Detection")
                    .font(.title2)
                    .padding(.top, 8)

                Text("Monitoring Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Spacer().frame(height: 32)

                // Recording controls
                recordingControls
            }

            // Debug overlay positioned in top-leading corner
            VStack {
                HStack {
                    DebugOverlayView(appModel: appModel)
                        .padding()
                    Spacer()
                }
                Spacer()
            }

            // Tagging controls at bottom
            VStack {
                Spacer()
                TaggingControlsView(appModel: appModel)
                    .padding()
            }
        }
        .padding()
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        VStack(spacing: 12) {
            if appModel.isRecording {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                    Text("Recording: \(formattedDuration)")
                        .font(.headline)
                }

                HStack {
                    Text("Tags: \(appModel.tagCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Stop Recording") {
                    let session = appModel.stopRecording()
                    print("Recorded \(session.samples.count) samples")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Start Recording") {
                    appModel.startRecording()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var formattedDuration: String {
        let minutes = Int(appModel.recordingDuration) / 60
        let seconds = Int(appModel.recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
