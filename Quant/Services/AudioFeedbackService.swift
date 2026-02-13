//
//  AudioFeedbackService.swift
//  Quant
//
//  Created for Ticket 4.2 — Audio Feedback
//
//  This service plays a subtle audio cue when the NudgeEngine fires.
//
//  ## How It Works
//
//  Instead of bundling an audio file, this service generates a short, gentle
//  tone *in memory* using raw audio math — specifically a sine wave at 880 Hz
//  (the musical note A5) with a smooth fade-in and fade-out so it sounds like
//  a soft "ping" rather than a harsh beep.
//
//  The audio session is configured as `.ambient`, which means:
//  - The tone mixes with whatever music/podcast the user is playing.
//  - It respects the system volume — turning volume down makes the tone quieter.
//  - It respects the mute/silent switch — if the phone is muted, no sound plays.
//
//  ## Why Generate the Tone Programmatically?
//
//  1. No external audio files to manage or accidentally delete.
//  2. Easy to tweak the sound (frequency, duration, volume) without a sound editor.
//  3. Keeps the app bundle size smaller.
//
//  ## Safety Guards
//
//  Even though the NudgeEngine has its own cooldown, this service has an
//  additional minimum interval between plays (0.5 seconds) to prevent any
//  possibility of audio spam from rapid state changes.
//

import AVFoundation
import os.log

/// Plays a subtle audio cue when a posture nudge fires.
///
/// Usage:
/// ```swift
/// let audio = AudioFeedbackService()
/// audio.playNudgeCue()  // Plays a soft tone
/// ```
///
/// The service is designed to be created once (in AppModel) and reused.
/// It lazily prepares the audio player on the first call to `playNudgeCue()`.
@MainActor
final class AudioFeedbackService {

    // MARK: - Configuration

    /// How loud the nudge tone plays, relative to the system volume.
    /// 0.0 = silent, 1.0 = full system volume.
    /// A value of 0.3 gives a gentle, non-jarring level.
    var volume: Float = 0.3

    /// Whether audio feedback is enabled at all.
    /// When `false`, `playNudgeCue()` does nothing.
    /// This allows the user (or debug UI) to toggle audio on/off.
    var isEnabled: Bool = true

    // MARK: - Debug State

    /// Timestamp of the last successful audio play, for the debug overlay.
    private(set) var lastPlayedTime: Date?

    /// Total number of times the audio cue has played this session.
    private(set) var totalPlays: Int = 0

    // MARK: - Private Properties

    /// The audio player instance. Created lazily when first needed.
    /// We keep a strong reference so it doesn't get deallocated mid-playback.
    private var player: AVAudioPlayer?

    /// The generated audio data (a short WAV file in memory).
    /// Created once and reused for every play.
    private var toneData: Data?

    /// Minimum interval between plays to prevent audio spam.
    /// This is a safety net on top of the NudgeEngine's cooldown.
    private let minimumPlayInterval: TimeInterval = 0.5

    /// Logger for debugging audio issues.
    private let logger = Logger(subsystem: "com.quant.posture", category: "AudioFeedback")

    // MARK: - Audio Generation Parameters

    /// The frequency of the tone in Hz. 880 Hz = A5 (a pleasant, soft note).
    private let toneFrequency: Double = 880.0

    /// How long the tone lasts in seconds. Short enough to not annoy,
    /// long enough to be noticeable.
    private let toneDuration: Double = 0.35

    /// Sample rate for the generated audio (CD quality).
    private let sampleRate: Double = 44100.0

    // MARK: - Public Methods

    /// Play the nudge audio cue.
    ///
    /// This is the main method called by AppModel when a `NudgeDecision.fire`
    /// is detected. It plays a short, gentle tone that:
    /// - Respects the system volume (quieter phone = quieter tone)
    /// - Respects the mute switch (silent mode = no sound)
    /// - Won't spam even if called rapidly (minimum interval guard)
    ///
    /// Safe to call from any context — if audio can't play for any reason
    /// (muted, audio session error, etc.), it fails silently with a log message.
    func playNudgeCue() {
        // Guard 1: Check if audio feedback is enabled
        guard isEnabled else {
            logger.debug("Audio feedback disabled — skipping")
            return
        }

        // Guard 2: Prevent rapid repeated plays
        if let lastPlayed = lastPlayedTime,
           Date().timeIntervalSince(lastPlayed) < minimumPlayInterval {
            logger.debug("Audio play throttled — too soon since last play")
            return
        }

        // Ensure we have the tone data generated
        if toneData == nil {
            toneData = generateToneData()
        }

        guard let data = toneData else {
            logger.error("Failed to generate tone data")
            return
        }

        do {
            // Configure the audio session each time we play.
            //
            // `.ambient` category means:
            // - Sound mixes with other apps' audio (music keeps playing)
            // - Respects the mute/silent switch
            // - Volume follows the system volume slider
            //
            // This is ideal for a subtle notification tone — it doesn't
            // interrupt what the user is listening to.
            try AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)

            // Create a fresh player each time. AVAudioPlayer is lightweight
            // and this avoids issues with the player being in a bad state
            // after a previous play.
            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.volume = volume
            audioPlayer.prepareToPlay()
            audioPlayer.play()

            // Keep a strong reference so the player isn't deallocated
            // before it finishes playing.
            self.player = audioPlayer

            // Update debug state
            lastPlayedTime = Date()
            totalPlays += 1

            logger.info("🔊 Nudge audio cue played (total: \(self.totalPlays))")
        } catch {
            logger.error("Failed to play nudge audio: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// Generate a short WAV file in memory containing a gentle sine wave tone.
    ///
    /// ## How WAV Files Work (simplified)
    ///
    /// A WAV file has two parts:
    /// 1. **Header** (44 bytes): Tells the audio player "here's a sound file,
    ///    it has X samples, at Y sample rate, with Z bits per sample."
    /// 2. **Data**: The actual audio samples — numbers representing the
    ///    waveform (how the speaker cone should move over time).
    ///
    /// ## How We Generate the Tone
    ///
    /// We calculate a sine wave at `toneFrequency` Hz. A sine wave sounds like
    /// a pure, clean tone (think tuning fork). We then apply an "envelope" —
    /// a smooth fade-in at the start and fade-out at the end — so the tone
    /// doesn't click or pop when it starts/stops.
    ///
    /// The math for each sample:
    /// ```
    /// sample = sin(2π × frequency × time) × envelope
    /// ```
    ///
    /// Where `envelope` ramps from 0→1 at the start and 1→0 at the end.
    private func generateToneData() -> Data? {
        let numSamples = Int(sampleRate * toneDuration)
        let bitsPerSample: Int = 16
        let numChannels: Int = 1  // Mono audio (no need for stereo)
        let bytesPerSample = bitsPerSample / 8
        let dataSize = numSamples * bytesPerSample * numChannels

        // Build the WAV file header (44 bytes, standard PCM format)
        var header = Data()

        // "RIFF" chunk descriptor
        header.append(contentsOf: "RIFF".utf8)                              // ChunkID
        header.append(contentsOf: uint32LEBytes(UInt32(36 + dataSize)))     // ChunkSize
        header.append(contentsOf: "WAVE".utf8)                              // Format

        // "fmt " sub-chunk (describes the audio format)
        header.append(contentsOf: "fmt ".utf8)                              // Subchunk1ID
        header.append(contentsOf: uint32LEBytes(16))                        // Subchunk1Size (16 for PCM)
        header.append(contentsOf: uint16LEBytes(1))                         // AudioFormat (1 = PCM)
        header.append(contentsOf: uint16LEBytes(UInt16(numChannels)))       // NumChannels
        header.append(contentsOf: uint32LEBytes(UInt32(sampleRate)))        // SampleRate
        header.append(contentsOf: uint32LEBytes(UInt32(sampleRate) * UInt32(numChannels) * UInt32(bytesPerSample)))  // ByteRate
        header.append(contentsOf: uint16LEBytes(UInt16(numChannels * bytesPerSample)))  // BlockAlign
        header.append(contentsOf: uint16LEBytes(UInt16(bitsPerSample)))     // BitsPerSample

        // "data" sub-chunk (the actual audio samples)
        header.append(contentsOf: "data".utf8)                              // Subchunk2ID
        header.append(contentsOf: uint32LEBytes(UInt32(dataSize)))          // Subchunk2Size

        // Generate the sine wave samples with a smooth envelope
        var audioData = Data()

        // Fade durations as a fraction of total duration:
        // - Fade in: first 10% of the tone
        // - Fade out: last 30% of the tone (longer fade-out sounds more natural)
        let fadeInSamples = Int(Double(numSamples) * 0.10)
        let fadeOutSamples = Int(Double(numSamples) * 0.30)
        let fadeOutStart = numSamples - fadeOutSamples

        for i in 0..<numSamples {
            // Time position of this sample in seconds
            let t = Double(i) / sampleRate

            // The raw sine wave: oscillates between -1.0 and +1.0
            let sineValue = sin(2.0 * .pi * toneFrequency * t)

            // Calculate the envelope (volume multiplier at this point in time)
            let envelope: Double
            if i < fadeInSamples {
                // Fade in: ramp from 0.0 to 1.0 over the first 10%
                // Using a sine curve for the ramp makes it sound smoother
                // than a linear ramp (less "clicky").
                let progress = Double(i) / Double(fadeInSamples)
                envelope = sin(progress * .pi / 2.0)  // 0 → 1 along a quarter sine
            } else if i >= fadeOutStart {
                // Fade out: ramp from 1.0 to 0.0 over the last 30%
                let progress = Double(i - fadeOutStart) / Double(fadeOutSamples)
                envelope = cos(progress * .pi / 2.0)  // 1 → 0 along a quarter cosine
            } else {
                // Middle section: full volume
                envelope = 1.0
            }

            // Combine sine wave with envelope, and scale to 16-bit range.
            // Int16 can hold values from -32768 to 32767.
            // We multiply by 0.7 to leave some headroom (prevents clipping).
            let sample = sineValue * envelope * 0.7
            let intSample = Int16(clamping: Int(sample * Double(Int16.max)))

            // Write as little-endian bytes (WAV format standard)
            audioData.append(contentsOf: uint16LEBytes(UInt16(bitPattern: intSample)))
        }

        return header + audioData
    }

    // MARK: - Byte Conversion Helpers

    /// Convert a UInt32 to 4 bytes in little-endian order.
    /// WAV files use little-endian byte order throughout.
    private func uint32LEBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }

    /// Convert a UInt16 to 2 bytes in little-endian order.
    private func uint16LEBytes(_ value: UInt16) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
        ]
    }
}
