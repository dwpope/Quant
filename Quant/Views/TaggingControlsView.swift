//
//  TaggingControlsView.swift
//  Quant
//
//  Created for Ticket 2.4 - Tagging During Record
//

import SwiftUI
import PostureLogic
import Speech

struct TaggingControlsView: View {
    @ObservedObject var appModel: AppModel
    @StateObject private var voiceService = VoiceTagService()
    @State private var showingAuthorizationAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Recording Tags")
                    .font(.headline)
                Spacer()
                if appModel.isRecording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !appModel.isRecording {
                Text("Start recording to enable tagging")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Manual tag buttons
                manualTagButtons

                Divider()

                // Voice recognition controls
                voiceRecognitionControls
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .alert("Speech Recognition Authorization Required", isPresented: $showingAuthorizationAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable Speech Recognition in Settings to use voice tagging.")
        }
    }

    // MARK: - Manual Tag Buttons

    private var manualTagButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual Tags")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                tagButton(label: "Good Posture", tag: .goodPosture, color: .green)
                tagButton(label: "Slouching", tag: .slouching, color: .red)
                tagButton(label: "Reading", tag: .reading, color: .blue)
                tagButton(label: "Typing", tag: .typing, color: .purple)
                tagButton(label: "Stretching", tag: .stretching, color: .orange)
                tagButton(label: "Absent", tag: .absent, color: .gray)
            }
        }
    }

    private func tagButton(label: String, tag: TagLabel, color: Color) -> some View {
        Button {
            addTag(tag, source: .manual)
        } label: {
            HStack {
                Image(systemName: iconForTag(tag))
                    .font(.caption)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(8)
        }
    }

    // MARK: - Voice Recognition Controls

    private var voiceRecognitionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voice Recognition")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: $voiceService.isEnabled)
                    .labelsHidden()
                    .onChange(of: voiceService.isEnabled) { _, enabled in
                        handleVoiceToggle(enabled)
                    }
            }

            if voiceService.isEnabled {
                voiceStatusView
            }
        }
    }

    private var voiceStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Authorization status
            if voiceService.authorizationStatus != .authorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Authorization needed")
                        .font(.caption)
                    Button("Request") {
                        Task {
                            await voiceService.requestAuthorization()
                            if voiceService.authorizationStatus != .authorized {
                                showingAuthorizationAlert = true
                            }
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            } else {
                // Listening controls
                HStack {
                    if voiceService.isListening {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("Listening...")
                                .font(.caption)
                        }
                        .foregroundStyle(.red)

                        Spacer()

                        Button("Stop") {
                            voiceService.stopListening()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            startVoiceListening()
                        } label: {
                            HStack {
                                Image(systemName: "mic.fill")
                                Text("Start Listening")
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Last recognized text
                if !voiceService.lastRecognizedText.isEmpty {
                    Text("Heard: \"\(voiceService.lastRecognizedText)\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }

                // Error message
                if let error = voiceService.error {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption2)
                    }
                    .foregroundStyle(.red)
                }

                // Supported commands
                if voiceService.isListening {
                    Text("Say: \"mark good\", \"mark slouch\", \"mark reading\", \"mark typing\", \"mark stretching\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleVoiceToggle(_ enabled: Bool) {
        if enabled {
            // Check authorization when enabling
            Task {
                if voiceService.authorizationStatus == .notDetermined {
                    await voiceService.requestAuthorization()
                }
            }
        } else {
            // Stop listening when disabling
            if voiceService.isListening {
                voiceService.stopListening()
            }
        }
    }

    private func startVoiceListening() {
        voiceService.startListening { tagLabel in
            addTag(tagLabel, source: .voice)
        }
    }

    private func addTag(_ label: TagLabel, source: TagSource) {
        let timestamp = Date().timeIntervalSince1970
        let tag = Tag(timestamp: timestamp, label: label, source: source)

        appModel.addRecordingTag(tag)

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Helpers

    private func iconForTag(_ tag: TagLabel) -> String {
        switch tag {
        case .goodPosture: return "checkmark.circle.fill"
        case .slouching: return "exclamationmark.triangle.fill"
        case .reading: return "book.fill"
        case .typing: return "keyboard.fill"
        case .stretching: return "figure.walk"
        case .absent: return "person.slash.fill"
        }
    }
}

#Preview {
    TaggingControlsView(appModel: AppModel())
        .padding()
}
