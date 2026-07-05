//
//  VisionGateConfiguration.swift
//  Perch
//
//  The vision gate decides, per voice/typed query, whether Perch needs to look
//  at the user's screen. When it doesn't, the answer is served imageless over the
//  same /chat → OpenRouter path (no screenshot) — saving a screen capture and a
//  vision round-trip on questions that don't need it.
//
//  This enum only reads the MODE toggle. The actual classifier lives in ClaudeAPI
//  (classifyNeedsScreen); the routing branch lives in CompanionManager.
//

import Foundation

enum VisionGateConfiguration {

    /// How the voice/typed answer lane decides whether to capture the screen.
    enum Mode {
        /// Default: ask the classifier per query whether the screen is needed.
        /// If the classifier errors, the caller falls back to capturing the
        /// screen — reliability over savings.
        case auto
        /// Bypass the gate entirely — always capture the screen and use the
        /// multimodal path. Byte-for-byte the pre-gate behavior.
        case always
    }

    /// Reads `PERCH_VISION_GATE` — process environment first (so a terminal
    /// launch can override), then the repo `.env`. Unknown / unset → `.auto`.
    static var mode: Mode {
        let rawValue = ProcessInfo.processInfo.environment["PERCH_VISION_GATE"]
            ?? DotEnvConfiguration.value(forKey: "PERCH_VISION_GATE")
            ?? "auto"
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "always" ? .always : .auto
    }
}
