//
//  DismissedPatternStore.swift
//  leanring-buddy
//
//  Persists the rotation-invariant keys of proactive-offer patterns the user
//  has dismissed ("Not now"), as JSON at
//  ~/Library/Application Support/Perch/dismissed-patterns.json — the same
//  small append-mostly pattern as WorkflowScheduleStore / AgentRunHistoryStore.
//  The session-only `suppressedPatternKeys` in RepetitionDetector stops a
//  pattern from re-firing within one run; this store makes a DISMISSAL stick
//  ACROSS runs, so a pattern the user keeps rejecting stops being offered
//  permanently (docs/DECISIONS.md D7).
//
//  Deliberately NOT @MainActor / ObservableObject (same rationale as
//  WorkflowScheduleStore): the only consumer is the main-actor
//  RepetitionDetector, and staying plain lets the pure-logic CLI harness
//  compile it without a concurrency runtime. The storage file is injectable so
//  the harness and unit tests can round-trip into a temp dir.
//

import Foundation

final class DismissedPatternStore {

    /// Rotation-invariant pattern keys the user has dismissed across all runs.
    private(set) var dismissedKeys: Set<String>

    private let storageFileURL: URL

    init(storageFileURL: URL) {
        self.storageFileURL = storageFileURL
        self.dismissedKeys = Self.loadKeys(from: storageFileURL)
    }

    /// The app's real dismissed-patterns file.
    static func standard() -> DismissedPatternStore {
        return DismissedPatternStore(
            storageFileURL: PerchSupportPaths.file("dismissed-patterns.json")
        )
    }

    func contains(_ patternKey: String) -> Bool {
        dismissedKeys.contains(patternKey)
    }

    /// Record a dismissed pattern and write it through. No-op (no write) if the
    /// key is already persisted, so repeated dismissals don't rewrite the file.
    func recordDismissed(_ patternKey: String) {
        guard !dismissedKeys.contains(patternKey) else { return }
        dismissedKeys.insert(patternKey)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let directoryURL = storageFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            // Sorted so the on-disk file is stable/diffable across writes.
            let encodedKeys = try JSONEncoder().encode(dismissedKeys.sorted())
            try encodedKeys.write(to: storageFileURL, options: .atomic)
        } catch {
            print("⚠️ DismissedPatternStore: failed to persist dismissed patterns: \(error)")
        }
    }

    private static func loadKeys(from fileURL: URL) -> Set<String> {
        guard let storedData = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return Set(try JSONDecoder().decode([String].self, from: storedData))
        } catch {
            print("⚠️ DismissedPatternStore: failed to decode dismissed patterns: \(error)")
            return []
        }
    }
}
