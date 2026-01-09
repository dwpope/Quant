//
//  VoiceTagService.swift
//  Quant
//
//  Created for Ticket 2.4 - Tagging During Record
//

import Foundation
import Speech
import AVFoundation
import Combine
import UIKit
import PostureLogic

/// Service for voice-activated tagging during recording sessions
@MainActor
final class VoiceTagService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var isEnabled = false  // OFF by default
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var lastRecognizedText: String = ""
    @Published var error: String?

    // MARK: - Private Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Callback when a tag is recognized
    private var onTagRecognized: ((TagLabel) -> Void)?

    // Supported voice commands
    private let commands: [String: TagLabel] = [
        "mark good": .goodPosture,
        "mark good posture": .goodPosture,
        "mark slouch": .slouching,
        "mark slouching": .slouching,
        "mark reading": .reading,
        "mark typing": .typing,
        "mark stretch": .stretching,
        "mark stretching": .stretching,
        "mark absent": .absent
    ]

    override init() {
        super.init()
        checkAuthorization()
    }

    // MARK: - Authorization

    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
    }

    // MARK: - Listening Control

    func startListening(onTag: @escaping (TagLabel) -> Void) {
        guard isEnabled else {
            error = "Voice recognition is disabled"
            return
        }

        guard authorizationStatus == .authorized else {
            error = "Speech recognition not authorized"
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        self.onTagRecognized = onTag

        do {
            try startRecognition()
            isListening = true
            error = nil
        } catch {
            self.error = "Failed to start: \(error.localizedDescription)"
            isListening = false
        }
    }

    func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Private Methods

    private func startRecognition() throws {
        // Cancel previous task if any
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "VoiceTagService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }

        recognitionRequest.shouldReportPartialResults = true

        // Get audio input
        let inputNode = audioEngine.inputNode

        // Create recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()

                Task { @MainActor in
                    self.lastRecognizedText = transcript
                    self.processTranscript(transcript)
                }
            }

            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                Task { @MainActor in
                    self.isListening = false
                }
            }
        }

        // Configure audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func processTranscript(_ transcript: String) {
        // Check if transcript contains any recognized command
        for (command, label) in commands {
            if transcript.contains(command) {
                onTagRecognized?(label)

                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                // Optional: Stop listening after successful tag
                // stopListening()

                break
            }
        }
    }

    // MARK: - Helper

    var canStartListening: Bool {
        return isEnabled && authorizationStatus == .authorized && !isListening
    }
}
