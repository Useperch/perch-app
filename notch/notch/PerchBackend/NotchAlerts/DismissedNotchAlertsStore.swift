//
//  DismissedNotchAlertsStore.swift
//  notch
//
//  Persists when the user dismissed a notch alert (by fingerprint), so the
//  evaluator and coordinator suppress it for a cooldown window.
//

import Foundation

final class DismissedNotchAlertsStore {

    /// How long a dismissed fingerprint stays suppressed.
    static let defaultCooldown: TimeInterval = 4 * 60 * 60

    /// Fingerprint → unix time the user last dismissed it.
    private(set) var dismissedAtByFingerprint: [String: TimeInterval]

    private let storageFileURL: URL
    private let cooldown: TimeInterval
    private let now: () -> Date

    init(
        storageFileURL: URL,
        cooldown: TimeInterval = DismissedNotchAlertsStore.defaultCooldown,
        now: @escaping () -> Date = Date.init
    ) {
        self.storageFileURL = storageFileURL
        self.cooldown = cooldown
        self.now = now
        self.dismissedAtByFingerprint = Self.load(from: storageFileURL)
    }

    static func standard() -> DismissedNotchAlertsStore {
        DismissedNotchAlertsStore(
            storageFileURL: PerchSupportPaths.file("dismissed-notch-alerts.json")
        )
    }

    func isDismissed(_ sourceFingerprint: String) -> Bool {
        guard let dismissedAt = dismissedAtByFingerprint[sourceFingerprint] else { return false }
        return now().timeIntervalSince1970 - dismissedAt < cooldown
    }

    func activeDismissedFingerprints() -> [String] {
        let currentTime = now().timeIntervalSince1970
        return dismissedAtByFingerprint.compactMap { fingerprint, dismissedAt in
            currentTime - dismissedAt < cooldown ? fingerprint : nil
        }
    }

    func recordDismissed(_ sourceFingerprint: String) {
        dismissedAtByFingerprint[sourceFingerprint] = now().timeIntervalSince1970
        persist()
    }

    private func persist() {
        let payload = ["dismissedAtByFingerprint": dismissedAtByFingerprint]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: storageFileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [String: TimeInterval] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = json["dismissedAtByFingerprint"] as? [String: TimeInterval]
        else { return [:] }
        return map
    }
}