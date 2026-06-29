//
//  DailyBriefStore.swift
//  notch
//
//  The source of truth for the brief's two USER-EDITABLE lists: "Catch up" and "Today's
//  priorities". The user can add, edit, delete, and (for priorities) check off items, and
//  the lists persist to `support/dailybrief/lists.json` so edits survive a relaunch.
//
//  Mirrors `DashboardLocalStore`: `@MainActor`, `@Published private(set)` state, a forgiving
//  load that never throws, atomic writes, debounced saves, and copy-on-write mutations
//  (nothing mutated in place — project immutability rule). On first launch (no file yet) the
//  lists are seeded from `DailyBriefSampleData` so the page reads well out of the box.
//

import Foundation

/// Which of the two editable lists a mutation targets.
enum DailyBriefListKind {
    case catchUp
    case priorities
}

/// The Codable on-disk shape — both lists in one versioned file (additive to extend later).
private struct DailyBriefListsState: Codable, Equatable {
    var catchUp: [DailyBriefItem]
    var priorities: [DailyBriefItem]
}

@MainActor
final class DailyBriefStore: ObservableObject {

    /// Shared so the brief window (and later any agent path) see the same lists.
    static let shared = DailyBriefStore()

    @Published private(set) var catchUp: [DailyBriefItem]
    @Published private(set) var priorities: [DailyBriefItem]

    private let storageFileURL: URL
    private var pendingSaveTask: Task<Void, Never>?

    init() {
        storageFileURL = PerchSupportPaths
            .directory("dailybrief")
            .appendingPathComponent("lists.json")

        if let loaded = Self.load(from: storageFileURL) {
            catchUp = loaded.catchUp
            priorities = loaded.priorities
        } else {
            // First launch: seed from the curated sample so the lists aren't empty.
            catchUp = DailyBriefSampleData.catchUp.map { DailyBriefItem(text: $0) }
            priorities = DailyBriefSampleData.priorities.map { DailyBriefItem(text: $0) }
        }
    }

    // MARK: Reads

    private func list(_ kind: DailyBriefListKind) -> [DailyBriefItem] {
        kind == .catchUp ? catchUp : priorities
    }

    // MARK: Mutations (each replaces, never mutates in place; each schedules a save)

    /// Insert a new empty item directly AFTER `afterID` (or at the end when `afterID` is nil
    /// or not found) and return its id, so the caller can focus it for immediate typing.
    /// This is the Return-key "new line below the current one" behavior.
    @discardableResult
    func insertItem(_ kind: DailyBriefListKind, afterID: String?) -> String {
        let newItem = DailyBriefItem(text: "")
        mutate(kind) { items in
            if let afterID, let index = items.firstIndex(where: { $0.id == afterID }) {
                items.insert(newItem, at: index + 1)
            } else {
                items.append(newItem)
            }
        }
        return newItem.id
    }

    /// Replace an item's text (called as the user types; the save is debounced).
    func updateText(_ kind: DailyBriefListKind, id: String, text: String) {
        mutate(kind) { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            guard items[index].text != text else { return }
            items[index].text = text
        }
    }

    /// Toggle a priority's checkbox (no-op semantics on catch-up, which has no checkbox).
    func toggleChecked(_ kind: DailyBriefListKind, id: String) {
        mutate(kind) { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].isChecked.toggle()
        }
    }

    /// Remove an item from a list.
    func deleteItem(_ kind: DailyBriefListKind, id: String) {
        mutate(kind) { items in
            items.removeAll { $0.id == id }
        }
    }

    /// Apply a copy-on-write edit to the chosen list, then persist.
    private func mutate(_ kind: DailyBriefListKind, _ edit: (inout [DailyBriefItem]) -> Void) {
        switch kind {
        case .catchUp:
            var updated = catchUp
            edit(&updated)
            catchUp = updated
        case .priorities:
            var updated = priorities
            edit(&updated)
            priorities = updated
        }
        scheduleSave()
    }

    // MARK: Persistence (debounced)

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let snapshot = DailyBriefListsState(catchUp: catchUp, priorities: priorities)
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            Self.persist(snapshot, to: storageFileURL)
        }
    }

    private static func persist(_ state: DailyBriefListsState, to fileURL: URL) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[DailyBrief] Failed to persist lists: \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> DailyBriefListsState? {
        guard let storedData = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DailyBriefListsState.self, from: storedData)
    }
}
