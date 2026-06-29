//
//  DashboardDataService.swift
//  leanring-buddy
//
//  The single seam between the dashboard's widgets and the outside world: it fetches a
//  widget's live items (`fetch`). The transport is injected as a protocol so the
//  dashboard's view layer stays self-contained — it has NO compile-time dependency on
//  `BrowserSubagentManager`. The full app registers the concrete transport at startup
//  (`CompanionManager.init`); the standalone dashboard preview runs with no transport
//  (empty widgets), so the board can still be compiled + previewed on its own.
//
//  Creating/editing a widget is no longer done here: the main agent's dashboard tool
//  family decides the widget spec and applies it via `DashboardAgentApplier`. This
//  service only reads data for widgets that already exist.
//
//  Everything degrades gracefully: an unregistered transport or a failed fetch yields
//  an empty item list (never throws), so a slow/offline widget renders a quiet empty
//  state instead of breaking the board.
//

import Foundation

// MARK: - Injected capabilities (kept free of app types)

/// Fetches a widget's raw items from somewhere live (the app wires this to the sidecar
/// `dashboard.fetch` RPC). Class-bound so the service can hold it weakly.
@MainActor
protocol DashboardFetchTransport: AnyObject {
    func sendDashboardFetch(provider: String, query: String, limit: Int) async throws -> [[String: Any]]
}

// MARK: - Service

@MainActor
final class DashboardDataService {

    /// Shared instance the dashboard uses for interpret + fetch. The app injects the
    /// concrete transport + interpreter via `attach(...)` at startup.
    static let shared = DashboardDataService()

    /// The live fetch bridge (weak so the dashboard never keeps the sidecar alive).
    private weak var transport: (any DashboardFetchTransport)?

    func attach(transport: any DashboardFetchTransport) {
        self.transport = transport
    }

    /// Fetch + shape a data-driven widget's items. Returns `[]` (never throws) when the
    /// transport is unregistered or the provider has no data.
    func fetch(plan: DashboardWidgetFetchPlan) async -> [DashboardWidgetItem] {
        guard let providerKey = plan.provider.fetchProviderKey else { return [] }
        guard let transport else {
            NSLog("[Dashboard] data service has no fetch transport attached yet")
            return []
        }
        do {
            let rawItems = try await transport.sendDashboardFetch(
                provider: providerKey,
                query: plan.query,
                limit: plan.limit
            )
            return rawItems.compactMap(Self.makeItem)
        } catch {
            NSLog("[Dashboard] dashboard.fetch failed for \(providerKey): \(error.localizedDescription)")
            return []
        }
    }

    /// Map one raw transport item dictionary into a `DashboardWidgetItem`, or `nil` if
    /// it has no title to show.
    private static func makeItem(_ raw: [String: Any]) -> DashboardWidgetItem? {
        guard let title = (raw["title"] as? String), !title.isEmpty else { return nil }
        let subtitle = raw["subtitle"] as? String
        let detail = raw["detail"] as? String
        let url = raw["url"] as? String
        let timestamp = (raw["timestamp"] as? String).flatMap(Self.parseTimestamp)
        // Stable id so a refresh doesn't churn SwiftUI identity for unchanged items.
        let stableID = url ?? "\(title)|\(subtitle ?? "")"
        return DashboardWidgetItem(
            id: stableID,
            title: title,
            subtitle: subtitle,
            detail: detail,
            url: url,
            importance: 0.5,
            timestamp: timestamp
        )
    }

    /// Parse an ISO-8601 timestamp (calendar events carry `start.dateTime`), tolerant
    /// of the fractional-seconds variant.
    private static func parseTimestamp(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) { return date }
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFormatter.date(from: value)
    }
}
