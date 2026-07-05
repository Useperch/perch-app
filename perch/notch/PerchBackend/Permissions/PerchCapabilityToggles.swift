//
//  PerchCapabilityToggles.swift
//  notch
//
//  User-facing on/off switches for Perch's three core abilities, exposed from the
//  menu-bar dropdown:
//
//    • Eyes  — whether Perch may capture the screen (the screenshot sent when you
//              hold ⌃⌥ to ask about what you're looking at).
//    • Ears  — whether Perch may use the microphone for push-to-talk voice.
//    • Hands — whether Perch may actuate the desktop (move the cursor, click, type)
//              on your behalf.
//
//  These are *preferences*, deliberately independent of the macOS TCC grant: a user
//  can turn Eyes off even though Screen Recording is still granted by the system.
//  Every ability defaults ON so a fresh install works out of the box; the choice is
//  persisted to UserDefaults so it survives restarts.
//
//  This is the single source of truth. The menu binds to the published properties
//  (which persist on change); the capability gates read the same keys via the
//  `nonisolated` `...EnabledNow()` accessors, so a gate that runs off the main actor
//  never has to hop just to check a flag.
//

import Combine
import Foundation

@MainActor
final class PerchCapabilityToggles: ObservableObject {
    static let shared = PerchCapabilityToggles()

    /// UserDefaults keys. Namespaced so they never collide with other settings.
    private enum StorageKey {
        static let eyes = "perch.permission.eyes.enabled"
        static let ears = "perch.permission.ears.enabled"
        static let hands = "perch.permission.hands.enabled"
        static let screenshotAlwaysAllow = "perch.permission.screenshotAlwaysAllow"
    }

    @Published var isEyesEnabled: Bool {
        didSet { UserDefaults.standard.set(isEyesEnabled, forKey: StorageKey.eyes) }
    }

    @Published var isEarsEnabled: Bool {
        didSet { UserDefaults.standard.set(isEarsEnabled, forKey: StorageKey.ears) }
    }

    @Published var isHandsEnabled: Bool {
        didSet { UserDefaults.standard.set(isHandsEnabled, forKey: StorageKey.hands) }
    }

    private init() {
        isEyesEnabled = Self.storedFlagDefaultingOn(StorageKey.eyes)
        isEarsEnabled = Self.storedFlagDefaultingOn(StorageKey.ears)
        isHandsEnabled = Self.storedFlagDefaultingOn(StorageKey.hands)
    }

    // MARK: Gate accessors (safe to read from any actor — UserDefaults is thread-safe)

    nonisolated static func isEyesEnabledNow() -> Bool { storedFlagDefaultingOn(StorageKey.eyes) }
    nonisolated static func isEarsEnabledNow() -> Bool { storedFlagDefaultingOn(StorageKey.ears) }
    nonisolated static func isHandsEnabledNow() -> Bool { storedFlagDefaultingOn(StorageKey.hands) }

    // MARK: Screenshot "Always Allow"

    /// Whether the user chose "Always Allow" on the just-in-time screenshot
    /// consent prompt. Unlike the ability toggles this defaults **off** — Perch
    /// must ask before the first screenshot (Screen Recording is no longer
    /// requested up-front in onboarding).
    nonisolated static func isScreenshotAlwaysAllowedNow() -> Bool {
        UserDefaults.standard.bool(forKey: StorageKey.screenshotAlwaysAllow)
    }

    nonisolated static func setScreenshotAlwaysAllowed(_ allowed: Bool) {
        UserDefaults.standard.set(allowed, forKey: StorageKey.screenshotAlwaysAllow)
    }

    /// Reads a persisted flag, treating "never set" as ON — so a fresh install has
    /// every ability enabled until the user turns one off.
    nonisolated private static func storedFlagDefaultingOn(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
    }
}
