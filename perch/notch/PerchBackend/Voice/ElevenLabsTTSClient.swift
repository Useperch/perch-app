//
//  ElevenLabsTTSClient.swift
//  Perch
//
//  Streams text-to-speech audio from ElevenLabs and plays it back
//  through the system audio output. Uses the streaming endpoint so
//  playback begins before the full audio has been generated.
//

import AVFoundation
import Foundation

@MainActor
final class ElevenLabsTTSClient {
    private let proxyURL: URL
    private let session: URLSession

    /// The audio player for the current TTS playback. Kept alive so the
    /// audio finishes playing even if the caller doesn't hold a reference.
    private var audioPlayer: AVAudioPlayer?

    init(proxyURL: String) {
        self.proxyURL = URL(string: proxyURL)!

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Sends `text` to ElevenLabs TTS and plays the resulting audio.
    /// Throws on network or decoding errors. Cancellation-safe.
    func speakText(_ text: String) async throws {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        // Identify this install to the Worker gateway (per-install auth + rate limiting).
        if let installToken = PerchInstallIdentity.currentInstallToken() {
            request.setValue(installToken, forHTTPHeaderField: "X-Perch-Install-Token")
        }

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsTTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "TTS API error (\(httpResponse.statusCode)): \(errorBody)"])
        }

        try Task.checkCancellation()

        let player = try AVAudioPlayer(data: data)
        // Enable output metering so callers can read the live playback amplitude
        // (used to make the voice orb pulse to Perch's actual spoken words).
        player.isMeteringEnabled = true
        self.audioPlayer = player
        player.play()
        print("🔊 ElevenLabs TTS: playing \(data.count / 1024)KB audio")
    }

    /// Whether TTS audio is currently playing back.
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    /// The current playback output power, normalized to 0…1.
    ///
    /// Reads `AVAudioPlayer`'s built-in average-power meter (a dB value in the
    /// range −160…0) and maps a useful speech window (−50 dB → 0 dB) onto 0…1.
    /// Returns 0 when nothing is playing. Poll this (~30 Hz) while TTS is
    /// speaking to drive an audio-reactive animation.
    func currentOutputPowerLevel() -> CGFloat {
        guard let player = audioPlayer, player.isPlaying else { return 0 }
        player.updateMeters()
        let decibels = player.averagePower(forChannel: 0)
        let floorDecibels: Float = -50
        guard decibels > floorDecibels else { return 0 }
        let normalized = (decibels - floorDecibels) / (0 - floorDecibels)
        return CGFloat(max(0, min(1, normalized)))
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
