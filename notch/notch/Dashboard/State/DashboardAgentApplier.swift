//
//  DashboardAgentApplier.swift
//  leanring-buddy
//
//  The single seam that turns the main agent's dashboard create/edit/snapshot request
//  (arriving over the subagent socket via `BrowserSubagentManager`) into mutations of
//  the Swift-owned dashboard. The agent decides the widget spec; this applier is the
//  only place that writes it to `DashboardWidgetStore`, places it on the pegboard, and
//  runs the first fetch — so the manager stays thin and the logic lives in one testable
//  spot.
//
//  Ownership split, kept clean:
//   • DATA (store mutation + first fetch) needs no live board — it goes straight through
//     `DashboardWidgetStore.shared` + `DashboardDataService.shared`, so a widget created
//     by voice while the board is closed still lands and populates.
//   • PLACEMENT needs the live `DashboardCanvasModel` (the pegboard geometry). The board
//     registers itself with `attach(canvasModel:)` on appear; when it's absent (board
//     never opened), the new widget is an "orphan" the model places via
//     `reconcileOrphanPlacements()` the moment it next comes up.
//
//  This replaces the deleted two-stage Swift interpreter path: the agent now produces a
//  ready fetch plan, so there is nothing to interpret here — only to apply.
//

import Foundation

@MainActor
final class DashboardAgentApplier {

    /// Shared instance the subagent manager calls and the canvas model registers with.
    static let shared = DashboardAgentApplier()

    /// The live pegboard model, registered on appear. Weak so the applier never keeps
    /// the board alive; `nil` when the board has never been opened (a created widget
    /// then lands in the store and is placed on the model's next orphan reconcile).
    private weak var canvasModel: DashboardCanvasModel?

    /// Called by `DashboardCanvasModel` when it comes alive, so create/edit can place
    /// and fit widgets on the real board.
    func attach(canvasModel: DashboardCanvasModel) {
        self.canvasModel = canvasModel
    }

    // MARK: - Snapshot (for the agent's edit step)

    /// The current data-driven widgets, serialized for the agent so an edit step can
    /// match the user's reference ("my news widget") to a concrete id. Builtins and
    /// drafts are omitted — the agent only creates/edits data-driven widgets.
    func snapshot() -> [[String: Any]] {
        DashboardWidgetStore.shared.widgets.compactMap { widget in
            guard widget.source.isDataDriven, let fetchPlan = widget.fetchPlan else {
                return nil
            }
            return [
                "id": widget.id,
                "title": widget.title,
                "source": widget.source.rawValue,
                "naturalLanguageSpec": widget.naturalLanguageSpec,
                "provider": widget.source.fetchProviderKey ?? "",
                "query": fetchPlan.query,
                "limit": fetchPlan.limit,
                "refreshCadenceSeconds": fetchPlan.refreshCadenceSeconds,
            ]
        }
    }

    // MARK: - Create

    /// Build a widget from the agent's spec, add (or replace a "+" draft) it in the
    /// store, place it on the board, and run the first fetch. Returns the result the
    /// manager sends back over the socket.
    func applyCreate(_ payload: [String: Any]) async -> [String: Any] {
        guard let source = Self.parseSource(payload["source"]) else {
            return ["ok": false, "error": "unknown widget source \(payload["source"] ?? "")"]
        }

        // Interactive builtin widgets (the Focus timer, Notes) carry no data source or
        // fetch plan — they are singletons keyed by their source raw value. Creating one
        // just ensures it exists in the store and is placed on the board, so "add a
        // timer" yields the real Focus widget (a live countdown) instead of a data card.
        if source.isBuiltin {
            return applyCreateBuiltin(source: source)
        }

        // An agent-authored interactive widget: store its sandboxed HTML document and
        // place it. No data fetch — it runs client-side in the web view.
        if source == .generated {
            return applyCreateGenerated(payload, source: source)
        }

        let title = (payload["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Widget"
        let fetchPlan = DashboardWidgetFetchPlan(
            provider: source,
            query: (payload["query"] as? String) ?? "",
            limit: Self.clampLimit(payload["limit"]),
            refreshCadenceSeconds: Self.clampCadence(payload["refreshCadenceSeconds"])
        )
        // A non-empty widgetId means the "+" compose textbox started this task: replace
        // its draft in place so the new widget keeps the draft's id + canvas slot.
        let existingWidgetID = (payload["widgetId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let widgetID = existingWidgetID ?? UUID().uuidString
        let widget = DashboardWidget(
            id: widgetID,
            title: title,
            naturalLanguageSpec: (payload["naturalLanguageSpec"] as? String) ?? "",
            source: source,
            fetchPlan: fetchPlan
        )

        let store = DashboardWidgetStore.shared
        let isReplacingDraft = existingWidgetID != nil && store.widget(for: widgetID) != nil
        if isReplacingDraft {
            store.replace(id: widgetID, with: widget)
        } else {
            store.add(widget)
        }

        // Make sure the board is open and the widget has a home on the pegboard. When
        // the board is closed, `canvasModel` is nil and the model places the orphan when
        // it next comes up (reconcileOrphanPlacements). Use REVEAL (not show): an
        // already-open board should just surface the new widget, not re-center or replay
        // the greeting splash — which read as the dashboard "restarting".
        NotificationCenter.default.post(name: .perchRevealDashboard, object: nil)
        canvasModel?.placeOrFitAgentWidget(widgetID: widgetID, source: source)

        // First fetch now, so the widget renders populated immediately rather than on
        // the next 30s refresh tick.
        let itemCount = await refreshIntoStore(widget)
        return [
            "ok": true,
            "widgetId": widgetID,
            "itemCount": itemCount,
            "summary": "Added \"\(title)\" — \(itemCount) item\(itemCount == 1 ? "" : "s").",
        ]
    }

    /// Add (or surface) an interactive builtin widget — the Focus countdown timer or the
    /// Notes pad. These are singletons keyed by their source raw value: if one already
    /// exists we don't duplicate it, we just make sure it's placed on the board. There is
    /// no fetch (a builtin has no data source), so this returns synchronously.
    private func applyCreateBuiltin(source: DashboardWidgetSource) -> [String: Any] {
        let store = DashboardWidgetStore.shared
        let builtinWidgetID = source.rawValue
        let displayTitle = Self.builtinDisplayTitle(source)

        // Idempotent: only seed the store record when this builtin isn't present yet.
        if store.widget(for: builtinWidgetID) == nil {
            store.add(.builtin(source, title: displayTitle))
        }

        // Reveal the board and give the builtin a home on the pegboard (placed at the
        // next free cell when new, or fit in place when it already sits on the board).
        NotificationCenter.default.post(name: .perchRevealDashboard, object: nil)
        canvasModel?.placeOrFitAgentWidget(widgetID: builtinWidgetID, source: source)

        return [
            "ok": true,
            "widgetId": builtinWidgetID,
            "summary": "Added the \(displayTitle) widget.",
        ]
    }

    /// Add (or replace a "+" draft with) an agent-authored interactive widget. The
    /// sidecar's widget generator already produced + sanitized the HTML; this stores it
    /// as a `GeneratedWidgetDocument`, places the widget on the board, and returns — there
    /// is no fetch (the widget runs client-side in its sandboxed web view).
    private func applyCreateGenerated(
        _ payload: [String: Any], source: DashboardWidgetSource
    ) -> [String: Any] {
        let html = (payload["generatedHtml"] as? String) ?? ""
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ["ok": false, "error": "the generated widget had no content"]
        }
        let title = (payload["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Widget"

        // A non-empty widgetId means the "+" compose textbox started this task: replace
        // its draft in place so the new widget keeps the draft's id + canvas slot.
        let existingWidgetID = (payload["widgetId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let widgetID = existingWidgetID ?? UUID().uuidString
        let document = GeneratedWidgetDocument(html: html, title: title, generatedAt: Date())
        let widget = DashboardWidget(
            id: widgetID,
            title: title,
            naturalLanguageSpec: (payload["naturalLanguageSpec"] as? String) ?? "",
            source: source,
            generatedDocument: document
        )

        let store = DashboardWidgetStore.shared
        if existingWidgetID != nil, store.widget(for: widgetID) != nil {
            store.replace(id: widgetID, with: widget)
        } else {
            store.add(widget)
        }

        NotificationCenter.default.post(name: .perchRevealDashboard, object: nil)
        canvasModel?.placeOrFitAgentWidget(widgetID: widgetID, source: source)
        return [
            "ok": true,
            "widgetId": widgetID,
            "summary": "Added the \"\(title)\" widget.",
        ]
    }

    /// The display title for a builtin widget added by the agent. The builtin's bespoke
    /// view carries its own on-card header, so this is only used as the store record's
    /// label.
    private static func builtinDisplayTitle(_ source: DashboardWidgetSource) -> String {
        switch source {
        case .builtinFocus: return "Focus"
        case .builtinNotes: return "Notes"
        case .builtinGreeting: return "Greeting"
        case .builtinWeather: return "Weather"
        case .builtinNeedsYou: return "Needs you"
        case .builtinToday: return "Today"
        default: return "Widget"
        }
    }

    // MARK: - Edit

    /// Merge the agent's patch onto an existing widget (only changed fields), replace it
    /// in the store, and re-fetch. Returns `ok: false` when the id no longer exists (the
    /// freshness guard) so the agent's step fails cleanly.
    func applyEdit(widgetId: String, patch: [String: Any]) async -> [String: Any] {
        let store = DashboardWidgetStore.shared
        guard let existing = store.widget(for: widgetId),
              let existingPlan = existing.fetchPlan else {
            return ["ok": false, "error": "no widget with id \(widgetId) to edit"]
        }
        let newSource = Self.parseSource(patch["source"]) ?? existing.source
        let mergedPlan = DashboardWidgetFetchPlan(
            provider: newSource,
            query: (patch["query"] as? String) ?? existingPlan.query,
            limit: patch["limit"] != nil ? Self.clampLimit(patch["limit"]) : existingPlan.limit,
            refreshCadenceSeconds: patch["refreshCadenceSeconds"] != nil
                ? Self.clampCadence(patch["refreshCadenceSeconds"])
                : existingPlan.refreshCadenceSeconds
        )
        let merged = DashboardWidget(
            id: existing.id,
            title: (patch["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? existing.title,
            naturalLanguageSpec: (patch["naturalLanguageSpec"] as? String) ?? existing.naturalLanguageSpec,
            source: newSource,
            fetchPlan: mergedPlan,
            expanded: existing.expanded,
            importanceScore: existing.importanceScore
        )
        store.replace(id: widgetId, with: merged)
        let itemCount = await refreshIntoStore(merged)
        return [
            "ok": true,
            "widgetId": widgetId,
            "itemCount": itemCount,
            "summary": "Updated \"\(merged.title)\".",
        ]
    }

    // MARK: - Helpers

    /// Fetch + rank a widget's items and write them back to the store, returning the
    /// count. Mirrors `DashboardCanvasModel.refreshWidget` but is board-independent so
    /// it runs even when the dashboard window is closed.
    private func refreshIntoStore(_ widget: DashboardWidget) async -> Int {
        guard let fetchPlan = widget.fetchPlan else { return 0 }
        let fetchedItems = await DashboardDataService.shared.fetch(plan: fetchPlan)
        let rankedItems = DashboardRankingService.rank(items: fetchedItems)
        DashboardWidgetStore.shared.updateItems(
            widgetID: widget.id, items: rankedItems, lastRefreshed: Date()
        )
        return rankedItems.count
    }

    private static func parseSource(_ raw: Any?) -> DashboardWidgetSource? {
        guard let rawValue = raw as? String, !rawValue.isEmpty else { return nil }
        return DashboardWidgetSource(rawValue: rawValue)
    }

    private static func clampLimit(_ raw: Any?) -> Int {
        let value = (raw as? Int) ?? (raw as? NSNumber)?.intValue ?? 12
        return max(1, min(value, 20))
    }

    private static func clampCadence(_ raw: Any?) -> Int {
        let value = (raw as? Int) ?? (raw as? NSNumber)?.intValue ?? 3600
        return max(300, value)
    }
}
