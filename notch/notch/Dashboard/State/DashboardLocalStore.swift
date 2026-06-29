//
//  DashboardLocalStore.swift
//  leanring-buddy
//
//  The source of truth for the Daily Dashboard's *local* widget content — the thing the
//  user owns directly rather than fetching from a service: their Notes scratchpad.
//  Persisted to `support/dashboard/local-state.json` so edits survive a relaunch.
//
//  Mirrors `DashboardWidgetStore`'s persistence approach: main-actor, `@Published
//  private(set)` state, iso8601 JSON, atomic writes, and a forgiving load that never
//  throws (the dashboard must always open). All mutations replace state with fresh copies
//  — nothing is mutated in place (project immutability rule). Saves are debounced so a
//  flurry of keystrokes in Notes coalesces into one write.
//

import Foundation

/// The Codable on-disk shape for all local dashboard content (one file, versioned by its
/// fields so adding more local widgets later is additive). An older file that also carried
/// a `tasks` array still decodes — the extra key is simply ignored.
private struct DashboardLocalState: Codable, Equatable {
    var notes: String
}

@MainActor
final class DashboardLocalStore: ObservableObject {

    /// Shared so the dashboard window and (later) the agent path see the same local state.
    static let shared = DashboardLocalStore()

    /// The free-form Notes scratchpad.
    @Published private(set) var notes: String

    private let storageFileURL: URL
    /// Debounce handle so rapid edits collapse into a single disk write.
    private var pendingSaveTask: Task<Void, Never>?

    init() {
        storageFileURL = PerchSupportPaths
            .directory("dashboard")
            .appendingPathComponent("local-state.json")

        // First launch (or a lost file) starts the Notes scratchpad empty — it holds the
        // user's own writing, never fabricated sample text.
        notes = Self.load(from: storageFileURL)?.notes ?? ""
    }

    // MARK: Mutations (each replaces, never mutates in place; each schedules a save)

    /// Replace the Notes body (called from the editor; the save is debounced).
    func updateNotes(_ updatedNotes: String) {
        guard updatedNotes != notes else { return }
        notes = updatedNotes
        scheduleSave()
    }

    // MARK: Persistence (debounced)

    /// Coalesce rapid edits (e.g. typing in Notes) into a single write ~0.4s after the
    /// last change.
    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let snapshot = DashboardLocalState(notes: notes)
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            Self.persist(snapshot, to: storageFileURL)
        }
    }

    private static func persist(_ state: DashboardLocalState, to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[Dashboard] Failed to persist local state: \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> DashboardLocalState? {
        guard let storedData = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DashboardLocalState.self, from: storedData)
    }
}
