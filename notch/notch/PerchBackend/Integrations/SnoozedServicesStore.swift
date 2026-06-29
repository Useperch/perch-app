//
//  SnoozedServicesStore.swift
//  leanring-buddy
//
//  Persists when the user last tapped "Not now" on a connect offer, as JSON at
//  <repo>/support/snoozed-services.json (the same small append-mostly pattern as
//  DismissedPatternStore). Unlike a permanent dismissal, a snooze EXPIRES: after
//  the cooldown window the service becomes offerable again, so a useful
//  integration the user wasn't ready for isn't hidden forever.
//
//  Deliberately plain (not @MainActor / ObservableObject) so the pure-logic
//  harness compiles it without a concurrency runtime. The storage file and the
//  clock are injectable so tests can round-trip into a temp dir and fast-forward
//  past the cooldown.
//

import Foundation

final class SnoozedServicesStore {

    /// How long a "Not now" suppresses a service before it can be offered again.
    static let defaultCooldown: TimeInterval = 14 * 24 * 60 * 60  // 14 days

    /// Slug → the time the user last snoozed it (seconds since 1970).
    private(set) var snoozedAtBySlug: [String: TimeInterval]

    private let storageFileURL: URL
    private let cooldown: TimeInterval
    /// Injectable clock so tests can fast-forward past the cooldown.
    private let now: () -> Date

    init(
        storageFileURL: URL,
        cooldown: TimeInterval = SnoozedServicesStore.defaultCooldown,
        now: @escaping () -> Date = Date.init
    ) {
        self.storageFileURL = storageFileURL
        self.cooldown = cooldown
        self.now = now
        self.snoozedAtBySlug = Self.load(from: storageFileURL)
    }

    /// The app's real snoozed-services file.
    static func standard() -> SnoozedServicesStore {
        return SnoozedServicesStore(
            storageFileURL: PerchSupportPaths.file("snoozed-services.json")
        )
    }

    /// Whether `toolkitSlug` is currently within its snooze cooldown.
    func isSnoozed(_ toolkitSlug: String) -> Bool {
        guard let snoozedAt = snoozedAtBySlug[toolkitSlug] else { return false }
        return now().timeIntervalSince1970 - snoozedAt < cooldown
    }

    /// Record a "Not now" for `toolkitSlug`, starting (or restarting) its
    /// cooldown, and write through.
    func recordSnoozed(_ toolkitSlug: String) {
        snoozedAtBySlug[toolkitSlug] = now().timeIntervalSince1970
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let directoryURL = storageFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let encoded = try encoder.encode(snoozedAtBySlug)
            try encoded.write(to: storageFileURL, options: .atomic)
        } catch {
            print("⚠️ SnoozedServicesStore: failed to persist snoozed services: \(error)")
        }
    }

    private static func load(from fileURL: URL) -> [String: TimeInterval] {
        guard let storedData = try? Data(contentsOf: fileURL) else { return [:] }
        do {
            return try JSONDecoder().decode([String: TimeInterval].self, from: storedData)
        } catch {
            print("⚠️ SnoozedServicesStore: failed to decode snoozed services: \(error)")
            return [:]
        }
    }
}
