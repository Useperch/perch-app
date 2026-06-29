//
//  DashboardWidgetStore.swift
//  leanring-buddy
//
//  The source of truth for *what widgets exist* on the Daily Dashboard and their
//  content (the placement/geometry of each lives separately in `DashboardLayoutStore`).
//  Persists the widget list to `support/dashboard/widgets.json` and seeds the original
//  builtin widgets on first launch.
//
//  Mirrors `AgentRunHistoryStore`'s persistence approach: main-actor, `@Published
//  private(set)` array, iso8601 JSON, atomic writes, and a forgiving load that never
//  throws (the dashboard must always open). All mutations replace array elements with
//  fresh copies — nothing is mutated in place (project immutability rule).
//

import Foundation

@MainActor
final class DashboardWidgetStore: ObservableObject {

    /// Single source of truth, shared by the dashboard window and (Wave 3) the voice/
    /// chat agent in `CompanionManager`, which lives in a different object graph but
    /// must see the same ranked widgets.
    static let shared = DashboardWidgetStore()

    /// Every widget on the board, in no particular order (placement decides position).
    @Published private(set) var widgets: [DashboardWidget] = []

    private let storageFileURL: URL

    init() {
        storageFileURL = PerchSupportPaths
            .directory("dashboard")
            .appendingPathComponent("widgets.json")
        widgets = Self.loadWidgets(from: storageFileURL)
        seedBuiltinsIfEmpty()
        reconcileBuiltinFetchPlans()
    }

    // MARK: Lookup

    /// The widget for a placement record's `widgetID`, if it still exists.
    func widget(for widgetID: String) -> DashboardWidget? {
        widgets.first { $0.id == widgetID }
    }

    // MARK: Mutations (each persists; each replaces, never mutates in place)

    func add(_ widget: DashboardWidget) {
        widgets = widgets + [widget]
        persist()
    }

    func remove(id widgetID: String) {
        let remaining = widgets.filter { $0.id != widgetID }
        guard remaining.count != widgets.count else { return }
        widgets = remaining
        persist()
    }

    func replace(id widgetID: String, with updatedWidget: DashboardWidget) {
        widgets = widgets.map { $0.id == widgetID ? updatedWidget : $0 }
        persist()
    }

    /// Replace a data-driven widget's cached items after a fetch + rank pass.
    func updateItems(widgetID: String, items: [DashboardWidgetItem], lastRefreshed: Date?) {
        guard let existing = widget(for: widgetID) else { return }
        replace(id: widgetID, with: existing.withItems(items, lastRefreshed: lastRefreshed))
    }

    /// Toggle a widget's expand state (the canvas grows/shrinks its span in response).
    func setExpanded(widgetID: String, expanded: Bool) {
        guard let existing = widget(for: widgetID) else { return }
        replace(id: widgetID, with: existing.withExpanded(expanded))
    }

    /// Write a freshly-computed ranking score (Wave 5).
    func setImportance(widgetID: String, score: Double) {
        guard let existing = widget(for: widgetID) else { return }
        replace(id: widgetID, with: existing.withImportance(score))
    }

    // MARK: Seeding

    /// Seed the six builtin widgets the first time the dashboard opens (or after the
    /// widgets file is lost). No-op once any widgets exist so the user's custom widgets
    /// are never clobbered.
    func seedBuiltinsIfEmpty() {
        guard widgets.isEmpty else { return }
        widgets = DashboardWidget.defaultBuiltins
        persist()
    }

    /// Backfill the live-data fetch plans onto builtins that were persisted before those
    /// plans existed (Weather / Needs you / Today). Idempotent and non-destructive: it
    /// only fills a `nil` fetch plan and never touches cached items, geometry, or the
    /// user's custom widgets — so an existing board starts pulling live data on next launch.
    func reconcileBuiltinFetchPlans() {
        let defaultFetchPlansBySource: [DashboardWidgetSource: DashboardWidgetFetchPlan] =
            Dictionary(uniqueKeysWithValues: DashboardWidget.defaultBuiltins.compactMap { builtin in
                builtin.fetchPlan.map { (builtin.source, $0) }
            })

        var didChange = false
        widgets = widgets.map { widget in
            guard widget.fetchPlan == nil,
                  let defaultFetchPlan = defaultFetchPlansBySource[widget.source] else { return widget }
            var updated = widget
            updated.fetchPlan = defaultFetchPlan
            didChange = true
            return updated
        }
        if didChange { persist() }
    }

    // MARK: Persistence

    private func persist() {
        do {
            let directoryURL = storageFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encodedWidgets = try encoder.encode(widgets)
            try encodedWidgets.write(to: storageFileURL, options: .atomic)
        } catch {
            NSLog("[Dashboard] Failed to persist widgets: \(error.localizedDescription)")
        }
    }

    private static func loadWidgets(from fileURL: URL) -> [DashboardWidget] {
        guard let storedData = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([DashboardWidget].self, from: storedData)
        } catch {
            // Corrupt or out-of-date schema — start fresh; builtins re-seed.
            NSLog("[Dashboard] Failed to decode stored widgets, re-seeding: \(error.localizedDescription)")
            return []
        }
    }
}
