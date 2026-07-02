//
//  PerchFreshInstallDetector.swift
//  Perch
//
//  Replacing Perch.app (DMG download, drag-to-Applications, Sparkle update) does
//  not clear ~/Library/Preferences/<bundle-id>.plist. Beta testers expect a true
//  first-launch experience each time they install a new copy. This compares a
//  fingerprint of the on-disk app bundle against a tiny sidecar plist that
//  survives preference wipes; when the binary changes, we drop the entire
//  UserDefaults domain (equivalent to deleting app.perch.notch.plist).
//

import Foundation

enum PerchFreshInstallDetector {
    private static let fingerprintKey = "lastInstallFingerprint"
    private static let installStatePlistName = "app.perch.notch.install-state"

    private static var installStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(installStatePlistName).plist")
    }

    /// Wipes all UserDefaults for this bundle when the installed app binary is new
    /// or replaced. Safe on every launch; no-op when the fingerprint is unchanged.
    static func resetPreferencesIfFreshInstall(defaults: UserDefaults = .standard) {
        let currentFingerprint = makeInstallFingerprint()
        let storedFingerprint = readStoredFingerprint()

        defer { writeStoredFingerprint(currentFingerprint) }

        guard let storedFingerprint, storedFingerprint != currentFingerprint else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        defaults.removePersistentDomain(forName: bundleIdentifier)
        defaults.synchronize()
        print("📦 Fresh Perch install detected — cleared saved preferences for \(bundleIdentifier)")
    }

    private static func makeInstallFingerprint() -> String {
        let bundle = Bundle.main
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let bundlePath = bundle.bundlePath

        var executableModificationTime: TimeInterval = 0
        if let executableURL = bundle.executableURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            executableModificationTime = modificationDate.timeIntervalSince1970
        }

        return "\(shortVersion)(\(buildNumber))|\(bundlePath)|\(executableModificationTime)"
    }

    private static func readStoredFingerprint() -> String? {
        guard let state = NSDictionary(contentsOf: installStateURL) as? [String: Any] else { return nil }
        return state[fingerprintKey] as? String
    }

    private static func writeStoredFingerprint(_ fingerprint: String) {
        let state: [String: Any] = [fingerprintKey: fingerprint]
        (state as NSDictionary).write(to: installStateURL, atomically: true)
    }
}