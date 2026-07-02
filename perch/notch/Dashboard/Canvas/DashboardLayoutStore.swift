//
//  DashboardLayoutStore.swift
//  Perch
//
//  Reads and writes the pegboard layout to `support/dashboard-layout.json`. Per the
//  project's on-disk-state rule, the path is resolved through `PerchSupportPaths`
//  (which keeps everything inside `<repo>/support/`, never Application Support).
//
//  Loading is forgiving: a missing or unreadable file falls back to the default
//  seed layout rather than throwing — the dashboard must always open.
//

import Foundation

/// Codable persistence for the dashboard canvas layout.
enum DashboardLayoutStore {

    /// The single JSON file holding the saved arrangement.
    private static var layoutFileURL: URL {
        PerchSupportPaths.file("dashboard-layout.json")
    }

    /// Load the saved snapshot, or the default seed when nothing valid is on disk.
    static func load() -> DashboardLayoutSnapshot {
        guard let savedData = try? Data(contentsOf: layoutFileURL) else {
            return .defaultSnapshot
        }
        guard let decodedSnapshot = try? JSONDecoder().decode(DashboardLayoutSnapshot.self, from: savedData) else {
            // Corrupt or out-of-date schema — start fresh from the seed.
            return .defaultSnapshot
        }
        // A snapshot with no items is meaningless; treat it as a fresh start.
        return decodedSnapshot.items.isEmpty ? .defaultSnapshot : decodedSnapshot
    }

    /// Persist the snapshot. Failures are logged, not thrown — a failed save must
    /// never interrupt the user's interaction with the board.
    static func save(_ snapshot: DashboardLayoutSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encodedData = try encoder.encode(snapshot)
            try encodedData.write(to: layoutFileURL, options: .atomic)
        } catch {
            NSLog("[Dashboard] Failed to save canvas layout: \(error.localizedDescription)")
        }
    }
}
