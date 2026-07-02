//
//  BuddyTranscriptionProvider.swift
//  Perch
//
//  Shared protocol surface for voice transcription backends.
//

import AVFoundation
import Foundation

protocol BuddyStreamingTranscriptionSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol BuddyTranscriptionProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    var isConfigured: Bool { get }
    var unavailableExplanation: String? { get }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession
}

enum BuddyTranscriptionProviderFactory {
    private enum PreferredProvider: String {
        case assemblyAI = "assemblyai"
        case appleSpeech = "apple"
        case whisper = "whisper"
    }

    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let provider = resolveProvider()
        print("🎙️ Transcription: using \(provider.displayName)")
        return provider
    }

    private static func resolveProvider() -> any BuddyTranscriptionProvider {
        let preferredProviderRawValue = AppBundleConfiguration
            .stringValue(forKey: "VoiceTranscriptionProvider")?
            .lowercased()
        let preferredProvider = preferredProviderRawValue.flatMap(PreferredProvider.init(rawValue:))

        let assemblyAIProvider = AssemblyAIStreamingTranscriptionProvider()

        if preferredProvider == .appleSpeech {
            return AppleSpeechTranscriptionProvider()
        }

        // Force fully-offline Whisper even when a cloud provider is configured.
        // (Whisper is also the automatic fallback below when no cloud provider is.)
        if preferredProvider == .whisper {
            return WhisperTranscriptionProvider()
        }

        // AssemblyAI (the default) reaches the Worker's `/transcribe-token` route —
        // the only cloud transcription path, since the app ships no provider keys.
        // When it isn't configured, fall back to fully-offline Whisper.
        if assemblyAIProvider.isConfigured {
            return assemblyAIProvider
        }

        if preferredProvider == .assemblyAI {
            print("⚠️ Transcription: AssemblyAI preferred but not configured, using Whisper (offline)")
        }

        // No cloud provider configured → fall back to fully-offline Whisper.
        // (Apple Speech remains available as an explicit `apple` opt-in.)
        return WhisperTranscriptionProvider()
    }
}
