//
//  DashboardWidgetNotchDrag.swift
//  leanring-buddy
//
//  The dashboard side of "drag a widget into the notch": the custom pasteboard type the
//  drag carries, the notification posted when such a drag begins (so the notch can put up
//  its drop target), and the `NSItemProvider` factory.
//
//  This lives in the Dashboard module — not under UI/Notch — on purpose: the dashboard
//  files must stay self-contained so the standalone preview harness compiles them without
//  the notch/app graph (same reason `.perchShowDashboard` is defined here rather than in
//  NotchPanelManager). The notch's AppKit drop view reads the pasteboard type defined
//  here; the full app compiles both, so the reference resolves there.
//
//  The payload is intentionally just the widget id (a string): the widget's content lives
//  once in the shared `DashboardWidgetStore`, and the notch resolves the same record — so
//  a pinned widget is one backend with two faces, never a copy.
//

import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Carries a dragged dashboard widget's id from the dashboard window onto Perch's OWN
    /// notch (in-process). A private, app-specific identifier so only the notch's drop
    /// target accepts the drag — a stray text field won't treat it as droppable text.
    static let perchDashboardWidgetID = NSPasteboard.PasteboardType("com.perch.dashboard-widget-id")

    /// Carries a self-contained JSON snapshot of the widget so a SEPARATE app's notch
    /// (e.g. notch) can render it natively without access to Perch's store. This
    /// crosses the process boundary, so the snapshot carries the data, not just an id.
    static let perchDashboardWidgetSnapshot = NSPasteboard.PasteboardType("com.perch.dashboard-widget-snapshot")
}

/// A self-contained, cross-app snapshot of a dashboard widget — everything another app's
/// notch needs to render it natively (title, header icon, and the ranked items, each with
/// its already-resolved publisher name). The JSON shape is the contract both Perch and
/// notch agree on; keep the two decoders in sync.
struct DashboardWidgetPortableSnapshot: Codable {
    struct Item: Codable {
        let title: String
        let subtitle: String?
        let url: String?
        /// Pre-resolved outlet name (e.g. "TechCrunch") so the receiver needn't reimplement
        /// `DashboardNewsPublisher`. `nil` when the item carries no URL.
        let publisher: String?
    }
    let title: String
    /// SF Symbol for the card header (e.g. "newspaper").
    let iconSystemName: String
    /// True for web/news sources that render as publisher-kicker + headline.
    let isHeadlineOnly: Bool
    let items: [Item]
}

extension Notification.Name {
    /// Posted the moment a dashboard widget's pin-to-notch drag begins, so the notch can
    /// show its (otherwise absent) drop target for the duration of the drag. `userInfo`
    /// carries the widget id under `perchDashboardWidgetDragWidgetIDKey`.
    static let perchDashboardWidgetDragBegan = Notification.Name("perchDashboardWidgetDragBegan")
}

/// `userInfo` key carrying the dragged widget's id on `.perchDashboardWidgetDragBegan`.
let perchDashboardWidgetDragWidgetIDKey = "widgetID"

enum DashboardWidgetNotchDrag {

    /// How many items the cross-app snapshot carries (a notch shows only a few rows).
    private static let snapshotItemLimit = 6

    /// Posts the drag-began notification, then returns an item provider carrying BOTH:
    ///  • the widget id (in-process) for Perch's own notch, and
    ///  • a portable JSON snapshot (cross-app) for a separate app's notch (notch).
    /// Call from a SwiftUI `.onDrag` closure — it fires once when the drag begins.
    @MainActor
    static func beginDrag(widget: DashboardWidget) -> NSItemProvider {
        NotificationCenter.default.post(
            name: .perchDashboardWidgetDragBegan,
            object: nil,
            userInfo: [perchDashboardWidgetDragWidgetIDKey: widget.id]
        )

        let provider = NSItemProvider()

        // (1) In-process id — Perch's own notch resolves it against the shared store.
        let widgetIDData = Data(widget.id.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: NSPasteboard.PasteboardType.perchDashboardWidgetID.rawValue,
            visibility: .ownProcess
        ) { completion in
            completion(widgetIDData, nil)
            return nil
        }

        // (2) Cross-app snapshot — a separate app's notch renders this without our store.
        if let snapshotData = snapshotData(for: widget) {
            provider.registerDataRepresentation(
                forTypeIdentifier: NSPasteboard.PasteboardType.perchDashboardWidgetSnapshot.rawValue,
                visibility: .all
            ) { completion in
                completion(snapshotData, nil)
                return nil
            }
        }

        return provider
    }

    /// Build the portable JSON snapshot from a widget's cached items.
    private static func snapshotData(for widget: DashboardWidget) -> Data? {
        let snapshotItems = widget.cachedItems.prefix(snapshotItemLimit).map { item in
            DashboardWidgetPortableSnapshot.Item(
                title: item.title,
                subtitle: item.subtitle,
                url: item.url,
                publisher: DashboardNewsPublisher.displayName(forURLString: item.url)
            )
        }
        let snapshot = DashboardWidgetPortableSnapshot(
            title: widget.title,
            iconSystemName: widget.source.headerIconName,
            isHeadlineOnly: widget.source.isHeadlineOnly,
            items: Array(snapshotItems)
        )
        return try? JSONEncoder().encode(snapshot)
    }
}
